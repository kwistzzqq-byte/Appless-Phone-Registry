import http from '@ohos.net.http';
import { ApplessRegistryConfig } from './ApplessRegistryConfig';

type JsonValue = Object | string | number | boolean | null | undefined;
type JsonRecord = Record<string, JsonValue>;

export interface RegistryAgentSummary {
  serviceId: string;
  name: string;
  description: string;
  tunnelDeviceId: string;
  requiresBearer: boolean;
}

export interface RegistryAgentReply {
  serviceId: string;
  state: string;
  text: string;
}

export function visibleRegistryPeerReplyText(value: string): string {
  const text = value.trim();
  if (text === 'DELIVERED' ||
    /^DELIVERED .+ \d+ bytes sha256=[a-f0-9]{64}$/i.test(text)) return '';
  return text;
}

export interface RegistryTunnelStatus {
  connectedDevices: number;
  boundServices: number;
  pendingRequests: number;
  onlineDevices: string[];
}

interface OutboundTextPart {
  kind: string;
  text: string;
}

interface OutboundPeerChatMetadata {
  applessMode: string;
  senderServiceId: string;
}

interface OutboundMessage {
  messageId: string;
  role: string;
  parts: OutboundTextPart[];
  metadata?: OutboundPeerChatMetadata;
}

interface OutboundParams {
  message: OutboundMessage;
}

interface OutboundJsonRpcRequest {
  jsonrpc: string;
  id: string;
  method: string;
  params: OutboundParams;
}

function record(value: JsonValue): JsonRecord | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonRecord : null;
}

function stringValue(value: JsonRecord | null, key: string): string {
  if (value === null) return '';
  const item = value[key];
  return typeof item === 'string' ? item.trim() : '';
}

function listValues(root: JsonValue): Object[] {
  if (Array.isArray(root)) return root as Object[];
  const value = record(root);
  if (value === null) return [];
  const keys: string[] = ['services', 'items', 'data', 'results'];
  for (let index = 0; index < keys.length; index++) {
    const candidate = value[keys[index]];
    if (Array.isArray(candidate)) return candidate as Object[];
  }
  return [];
}

function agentCard(row: JsonRecord): JsonRecord {
  const direct = record(row['agent_card']);
  if (direct !== null) return direct;
  const metadata = record(row['metadata']);
  if (metadata === null) return {};
  const nested = record(metadata['agent_card']);
  return nested ?? metadata;
}

function tunnelDeviceId(card: JsonRecord, fallback: string): string {
  const metadata = record(card['metadata']);
  return stringValue(metadata, 'tunnelDeviceId') || stringValue(metadata, 'tunnel_device_id') ||
    stringValue(card, 'tunnelDeviceId') || fallback;
}

function bearerRequired(card: JsonRecord): boolean {
  const schemes = record(card['securitySchemes']);
  if (schemes === null) return false;
  const keys = Object.keys(schemes);
  for (let index = 0; index < keys.length; index++) {
    const scheme = record(schemes[keys[index]]);
    if (stringValue(scheme, 'type').toLowerCase() === 'http' &&
      stringValue(scheme, 'scheme').toLowerCase() === 'bearer') return true;
  }
  return false;
}

export function parseRegistryAgentListResponse(raw: string, selfServiceId: string): RegistryAgentSummary[] {
  const parsed = JSON.parse(raw) as JsonValue;
  const values = listValues(parsed);
  const agents: RegistryAgentSummary[] = [];
  values.forEach((item: Object): void => {
    const row = record(item);
    if (row === null) return;
    const serviceId = stringValue(row, 'service_id') || stringValue(row, 'id');
    if (serviceId.length === 0 || serviceId === selfServiceId) return;
    const card = agentCard(row);
    agents.push({
      serviceId,
      name: stringValue(row, 'name') || stringValue(card, 'name') || serviceId,
      description: stringValue(row, 'description') || stringValue(card, 'description'),
      tunnelDeviceId: tunnelDeviceId(card, serviceId),
      requiresBearer: bearerRequired(card)
    });
  });
  agents.sort((left: RegistryAgentSummary, right: RegistryAgentSummary): number =>
    left.serviceId.localeCompare(right.serviceId));
  return agents;
}

function collectPartTexts(partsValue: JsonValue): string[] {
  const texts: string[] = [];
  if (!Array.isArray(partsValue)) return texts;
  (partsValue as Object[]).forEach((partValue: Object): void => {
    const part = record(partValue);
    const text = stringValue(part, 'text');
    if (text.length > 0) texts.push(text);
  });
  return texts;
}

function responseText(root: JsonRecord): string {
  const result = record(root['result']);
  if (result === null) return '';
  const artifacts = result['artifacts'];
  const texts: string[] = [];
  if (!Array.isArray(artifacts)) {
    const status = record(result['status']);
    const message = status === null ? null : record(status['message']);
    return collectPartTexts(message === null ? null : message['parts']).join('\n').trim() ||
      stringValue(result, 'text');
  }
  (artifacts as Object[]).forEach((artifactValue: Object): void => {
    const artifact = record(artifactValue);
    const parts = artifact === null ? null : artifact['parts'];
    collectPartTexts(parts).forEach((text: string): void => {
      texts.push(text);
    });
  });
  if (texts.length === 0) {
    const status = record(result['status']);
    const message = status === null ? null : record(status['message']);
    collectPartTexts(message === null ? null : message['parts']).forEach((text: string): void => {
      texts.push(text);
    });
  }
  return texts.join('\n').trim();
}

function errorMessage(root: JsonRecord | null, status: number): string {
  const error = root === null ? null : record(root['error']);
  return stringValue(error, 'message') || stringValue(root, 'detail') ||
    'Registry A2A request failed with HTTP ' + status.toString() + '.';
}

export function parseRegistryAgentReply(raw: string, serviceId: string): RegistryAgentReply {
  const root = record(JSON.parse(raw) as JsonValue);
  if (root === null) throw new Error('Registry A2A response is invalid.');
  const result = record(root['result']);
  const status = result === null ? null : record(result['status']);
  const state = stringValue(status, 'state') || 'completed';
  const text = responseText(root);
  if (text.length === 0) throw new Error('Remote Agent returned no text artifact.');
  return { serviceId, state, text };
}

function registryMessageRequestJson(text: string, metadata?: OutboundPeerChatMetadata): string {
  const requestId = 'appless-outbound-' + Date.now().toString();
  const part: OutboundTextPart = { kind: 'text', text };
  const message: OutboundMessage = {
    messageId: requestId + '-message',
    role: 'user',
    parts: [part]
  };
  if (metadata !== undefined) message.metadata = metadata;
  const params: OutboundParams = { message };
  const request: OutboundJsonRpcRequest = {
    jsonrpc: '2.0',
    id: requestId,
    method: 'message/send',
    params
  };
  return JSON.stringify(request);
}

export function registryA2aRequestJson(text: string): string {
  return registryMessageRequestJson(text);
}

export function registryPeerChatRequestJson(text: string, senderServiceId: string): string {
  return registryMessageRequestJson(text, {
    applessMode: 'peer_chat',
    senderServiceId
  });
}

function joinUrl(baseUrl: string, path: string): string {
  return baseUrl.replace(/\/+$/, '') + (path.startsWith('/') ? path : '/' + path);
}

function stringResult(response: http.HttpResponse): string {
  return typeof response.result === 'string' ? response.result : '';
}

function numberValue(value: JsonRecord | null, key: string): number {
  if (value === null) return 0;
  const item = value[key];
  return typeof item === 'number' && Number.isFinite(item) ? item : 0;
}

export function parseRegistryTunnelStatusResponse(raw: string): RegistryTunnelStatus {
  const root = record(JSON.parse(raw) as JsonValue);
  const onlineDevices: string[] = [];
  const values = root === null ? undefined : root['online_devices'];
  if (Array.isArray(values)) {
    (values as Object[]).forEach((value: Object): void => {
      if (typeof value === 'string' && value.trim().length > 0 &&
        onlineDevices.indexOf(value.trim()) < 0) {
        onlineDevices.push(value.trim());
      }
    });
  }
  onlineDevices.sort();
  return {
    connectedDevices: numberValue(root, 'connected_devices'),
    boundServices: numberValue(root, 'bound_services'),
    pendingRequests: numberValue(root, 'pending_requests'),
    onlineDevices
  };
}

export async function getRegistryTunnelStatus(config: ApplessRegistryConfig): Promise<RegistryTunnelStatus> {
  const request = http.createHttp();
  const headers: Record<string, string> = {};
  headers['Accept'] = 'application/json';
  if (config.registryHttpBearerToken.length > 0) {
    headers['Authorization'] = 'Bearer ' + config.registryHttpBearerToken;
  }
  try {
    const response = await request.request(joinUrl(config.registryBaseUrl, '/api/tunnel/status'), {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    });
    const raw = stringResult(response);
    const root = record(raw.length > 0 ? JSON.parse(raw) as JsonValue : null);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(errorMessage(root, response.responseCode));
    }
    return parseRegistryTunnelStatusResponse(raw);
  } finally {
    request.destroy();
  }
}

export async function listRegistryAgents(config: ApplessRegistryConfig): Promise<RegistryAgentSummary[]> {
  const request = http.createHttp();
  const headers: Record<string, string> = {};
  headers['Accept'] = 'application/json';
  if (config.registryHttpBearerToken.length > 0) {
    headers['Authorization'] = 'Bearer ' + config.registryHttpBearerToken;
  }
  try {
    const url = joinUrl(config.registryBaseUrl, '/api/datasets/' + encodeURIComponent(config.dataset) +
      '/services?fields=detail');
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    });
    const raw = stringResult(response);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(errorMessage(record(raw.length > 0 ? JSON.parse(raw) as JsonValue : null), response.responseCode));
    }
    return parseRegistryAgentListResponse(raw, config.serviceId);
  } finally {
    request.destroy();
  }
}

async function postRegistryAgentMessage(
  config: ApplessRegistryConfig,
  serviceId: string,
  requestJson: string
): Promise<RegistryAgentReply> {
  const request = http.createHttp();
  const headers: Record<string, string> = {};
  headers['Content-Type'] = 'application/json';
  headers['Accept'] = 'application/json';
  if (config.outboundPeerBearerToken.length > 0) {
    headers['Authorization'] = 'Bearer ' + config.outboundPeerBearerToken;
  }
  try {
    const url = joinUrl(config.registryBaseUrl, '/a2a/' + encodeURIComponent(config.dataset) + '/' +
      encodeURIComponent(serviceId));
    const response = await request.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: requestJson,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 120000
    });
    const raw = stringResult(response);
    const root = record(raw.length > 0 ? JSON.parse(raw) as JsonValue : null);
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(errorMessage(root, response.responseCode));
    }
    return parseRegistryAgentReply(raw, serviceId);
  } finally {
    request.destroy();
  }
}

export async function sendRegistryAgentMessage(
  config: ApplessRegistryConfig,
  serviceId: string,
  text: string
): Promise<RegistryAgentReply> {
  return postRegistryAgentMessage(config, serviceId, registryA2aRequestJson(text));
}

export async function sendRegistryPeerChatMessage(
  config: ApplessRegistryConfig,
  serviceId: string,
  text: string
): Promise<RegistryAgentReply> {
  return postRegistryAgentMessage(
    config,
    serviceId,
    registryPeerChatRequestJson(text, config.serviceId)
  );
}
