import { ApplessRegistryConfig } from './ApplessRegistryConfig';

type JsonValue = Object | string | number | boolean | null | undefined;
type JsonRecord = Record<string, JsonValue>;

export interface TunnelHttpRequest {
  method: string;
  path: string;
  headers: Record<string, string>;
  body: JsonValue;
}

export interface TunnelForwardRequest {
  type: string;
  messageId: string;
  sourceDevice: string;
  targetDevice: string;
  dataset: string;
  serviceId: string;
  httpRequest: TunnelHttpRequest;
}

export interface TunnelHttpResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export interface A2aTextRequest {
  ok: boolean;
  status: number;
  error: string;
  requestId: JsonValue;
  text: string;
  peerChat: boolean;
  senderServiceId: string;
  file: A2aInboundFile | null;
}

export interface A2aInboundFile {
  name: string;
  mimeType: string;
  bytes: string;
  uri: string;
}

interface PeerChatMetadata {
  claimed: boolean;
  senderServiceId: string;
}

interface JsonRpcErrorDetail {
  code: number;
  message: string;
}

interface JsonRpcErrorBody {
  jsonrpc: string;
  id: JsonValue;
  error: JsonRpcErrorDetail;
}

interface A2aCompletedStatus {
  state: string;
  timestamp: string;
}

interface A2aTextPart {
  kind: string;
  text: string;
}

interface A2aArtifact {
  artifactId: string;
  name: string;
  parts: A2aTextPart[];
}

interface A2aCompletedResult {
  id: string;
  contextId: string;
  status: A2aCompletedStatus;
  artifacts: A2aArtifact[];
}

interface JsonRpcCompletedBody {
  jsonrpc: string;
  id: JsonValue;
  result: A2aCompletedResult;
}

interface TunnelRegistrationFrame {
  type: string;
  device_id: string;
  token?: string;
}

interface TunnelForwardResponseFrame {
  type: string;
  message_id: string;
  http_response: TunnelHttpResponse;
  status: number;
}

interface ApplessAgentCardSkill {
  id: string;
  name: string;
  description: string;
  tags: string[];
  examples: string[];
  inputModes: string[];
  outputModes: string[];
}

interface ApplessAgentCardCapabilities {
  streaming: boolean;
  pushNotifications: boolean;
  stateTransitionHistory: boolean;
}

interface ApplessAgentCardSecurityScheme {
  type: string;
  scheme: string;
}

interface ApplessAgentCard {
  name: string;
  description: string;
  version: string;
  protocolVersion: string;
  url: string;
  preferredTransport: string;
  capabilities: ApplessAgentCardCapabilities;
  skills: ApplessAgentCardSkill[];
  defaultInputModes: string[];
  defaultOutputModes: string[];
  security: Object[];
  securitySchemes: Record<string, ApplessAgentCardSecurityScheme>;
  metadata: Record<string, string>;
}

function record(value: JsonValue): JsonRecord | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonRecord : null;
}

function stringValue(recordValue: JsonRecord | null, key: string): string {
  if (recordValue === null) return '';
  const value = recordValue[key];
  return typeof value === 'string' ? value : '';
}

function normalizedHeaders(value: JsonValue): Record<string, string> {
  const source = record(value);
  const result: Record<string, string> = {};
  if (source === null) return result;
  Object.keys(source).forEach((key: string) => {
    const item = source[key];
    if (typeof item === 'string') result[key.toLowerCase()] = item;
  });
  return result;
}

export function tunnelForwardRequestFromJson(raw: string): TunnelForwardRequest | null {
  let root: JsonRecord | null = null;
  try {
    root = record(JSON.parse(raw) as Object);
  } catch (_error) {
    return null;
  }
  if (root === null || stringValue(root, 'type') !== 'forward_request') return null;
  const http = record(root['http_request']);
  const messageId = stringValue(root, 'message_id');
  if (http === null || messageId.length === 0) return null;
  return {
    type: 'forward_request',
    messageId,
    sourceDevice: stringValue(root, 'source_device'),
    targetDevice: stringValue(root, 'target_device'),
    dataset: stringValue(root, 'dataset'),
    serviceId: stringValue(root, 'service_id'),
    httpRequest: {
      method: stringValue(http, 'method').toUpperCase(),
      path: stringValue(http, 'path'),
      headers: normalizedHeaders(http['headers']),
      body: http['body']
    }
  };
}

function requestBody(value: JsonValue): JsonRecord | null {
  if (typeof value === 'string') {
    try {
      return record(JSON.parse(value) as Object);
    } catch (_error) {
      return null;
    }
  }
  return record(value);
}

function requestText(body: JsonRecord): string {
  const params = record(body['params']);
  const message = params === null ? null : record(params['message']);
  const parts = message === null ? null : message['parts'];
  if (!Array.isArray(parts)) return '';
  const texts: string[] = [];
  (parts as Object[]).forEach((item: Object) => {
    const part = record(item);
    if (part === null) return;
    const kind = stringValue(part, 'kind');
    const text = stringValue(part, 'text').trim();
    if ((kind.length === 0 || kind === 'text') && text.length > 0) texts.push(text);
  });
  return texts.join('\n').trim();
}

function requestFile(body: JsonRecord): A2aInboundFile | null {
  const params = record(body['params']);
  const message = params === null ? null : record(params['message']);
  const parts = message === null ? null : message['parts'];
  if (!Array.isArray(parts)) return null;
  let result: A2aInboundFile | null = null;
  (parts as Object[]).forEach((item: Object): void => {
    const part = record(item);
    if (part === null || stringValue(part, 'kind') !== 'file') return;
    const file = record(part['file']);
    if (file === null || result !== null) {
      result = { name: '', mimeType: '', bytes: '', uri: '' };
      return;
    }
    result = {
      name: stringValue(file, 'name').trim(),
      mimeType: stringValue(file, 'mimeType').trim(),
      bytes: stringValue(file, 'bytes').trim(),
      uri: stringValue(file, 'uri').trim()
    };
  });
  return result;
}

function validFileName(value: string): boolean {
  return value.length > 0 && value.length <= 180 && value !== '.' && value !== '..' &&
    value.indexOf('/') < 0 && value.indexOf('\\') < 0 && !/[\u0000-\u001f\u007f]/.test(value);
}

function validInlineBase64(value: string): boolean {
  if (value.length === 0 || value.length > 7_000_000 || value.length % 4 !== 0) return false;
  return /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value);
}

function validFileInput(file: A2aInboundFile | null): boolean {
  if (file === null || !validFileName(file.name)) return false;
  if (file.mimeType.length > 128 || file.uri.length > 2048) return false;
  const sourceCount = (file.bytes.length > 0 ? 1 : 0) + (file.uri.length > 0 ? 1 : 0);
  if (sourceCount !== 1) return false;
  return file.bytes.length === 0 || validInlineBase64(file.bytes);
}

function peerChatMetadata(body: JsonRecord): PeerChatMetadata {
  const params = record(body['params']);
  const message = params === null ? null : record(params['message']);
  const metadata = message === null ? null : record(message['metadata']);
  const claimed = stringValue(metadata, 'applessMode') === 'peer_chat';
  return {
    claimed,
    senderServiceId: claimed ? stringValue(metadata, 'senderServiceId').trim() : ''
  };
}

function denied(status: number, error: string): A2aTextRequest {
  return { ok: false, status, error, requestId: null, text: '', peerChat: false, senderServiceId: '', file: null };
}

function matchesRegistryBinding(request: TunnelForwardRequest, config: ApplessRegistryConfig): boolean {
  const registryRelayBinding = request.dataset === config.dataset && request.serviceId === config.serviceId;
  const peerTunnelBinding = request.dataset.length === 0 && request.serviceId.length === 0 &&
    request.targetDevice === config.deviceId;
  return registryRelayBinding || peerTunnelBinding;
}

export function validateA2aTextRequest(
  request: TunnelForwardRequest,
  config: ApplessRegistryConfig
): A2aTextRequest {
  if (!matchesRegistryBinding(request, config)) {
    return denied(404, 'A2A service binding does not match Appless.');
  }
  if (request.httpRequest.method !== 'POST' ||
    request.httpRequest.path !== '/a2a' && request.httpRequest.path !== '/a2a/jsonrpc') {
    return denied(404, 'A2A endpoint was not found.');
  }
  const authorization = request.httpRequest.headers['authorization'] ?? '';
  if (authorization !== 'Bearer ' + config.inboundBearerToken) {
    return denied(401, 'A2A peer authorization is missing or invalid.');
  }
  const body = requestBody(request.httpRequest.body);
  if (body === null || stringValue(body, 'jsonrpc') !== '2.0') {
    return denied(400, 'A2A JSON-RPC request is invalid.');
  }
  const method = stringValue(body, 'method');
  if (method !== 'message/send' && method !== 'SendMessage') {
    return denied(400, 'A2A method is not supported.');
  }
  const text = requestText(body);
  const file = requestFile(body);
  if (text.length > config.maxPromptChars) {
    return denied(400, 'A2A text input is too large.');
  }
  if (text.length === 0 && file === null) {
    return denied(400, 'A2A message has no supported content.');
  }
  if (file !== null && !validFileInput(file)) {
    return denied(400, 'A2A FilePart is invalid or ambiguous.');
  }
  const peerChat = peerChatMetadata(body);
  const senderServiceId = peerChat.senderServiceId || (file !== null ? request.sourceDevice.trim() : '');
  if ((peerChat.claimed || file !== null) && !/^[A-Za-z0-9._-]{1,128}$/.test(senderServiceId)) {
    return denied(400, 'Peer chat sender serviceId is invalid.');
  }
  const requestId = body['id'];
  return {
    ok: true,
    status: 200,
    error: '',
    requestId,
    text,
    peerChat: peerChat.claimed || file !== null,
    senderServiceId,
    file
  };
}

function errorBody(requestId: JsonValue, status: number, message: string): Object {
  const error: JsonRpcErrorDetail = {
    code: -32000 - status,
    message
  };
  const body: JsonRpcErrorBody = {
    jsonrpc: '2.0',
    id: requestId ?? null,
    error
  };
  return body;
}

export function a2aErrorResponse(status: number, message: string, requestId: JsonValue = null): TunnelHttpResponse {
  const headers: Record<string, string> = {};
  headers['content-type'] = 'application/json';
  return {
    status,
    headers,
    body: JSON.stringify(errorBody(requestId, status, message))
  };
}

export function applessAgentCardResponse(
  request: TunnelForwardRequest,
  config: ApplessRegistryConfig
): TunnelHttpResponse | null {
  if (!matchesRegistryBinding(request, config) ||
    request.httpRequest.method !== 'GET' ||
    request.httpRequest.path !== '/.well-known/agent-card.json' &&
    request.httpRequest.path !== '/.well-known/agent.json') {
    return null;
  }
  const skill: ApplessAgentCardSkill = {
    id: 'appless.chat',
    name: 'Appless Chat',
    description: 'Process one text request while Appless is in the foreground',
    tags: ['mobile', 'text', 'read-only'],
    examples: [],
    inputModes: ['text/plain', 'application/octet-stream'],
    outputModes: ['text/plain']
  };
  const capabilities: ApplessAgentCardCapabilities = {
    streaming: false,
    pushNotifications: false,
    stateTransitionHistory: false
  };
  const bearer: ApplessAgentCardSecurityScheme = { type: 'http', scheme: 'bearer' };
  const securitySchemes: Record<string, ApplessAgentCardSecurityScheme> = {};
  securitySchemes['bearer'] = bearer;
  const securityEntry: Record<string, Object[]> = {};
  securityEntry['bearer'] = [];
  const metadata: Record<string, string> = {};
  metadata['tunnelDeviceId'] = config.deviceId;
  const card: ApplessAgentCard = {
    name: 'Appless Phone',
    description: 'Foreground read-only text agent hosted by the Appless HarmonyOS app',
    version: '0.1.0',
    protocolVersion: '0.3.0',
    url: 'http://127.0.0.1:18800/a2a/jsonrpc',
    preferredTransport: 'JSONRPC',
    capabilities,
    skills: [skill],
    defaultInputModes: ['text/plain', 'application/octet-stream'],
    defaultOutputModes: ['text/plain'],
    security: [securityEntry],
    securitySchemes,
    metadata
  };
  const headers: Record<string, string> = {};
  headers['content-type'] = 'application/json';
  return { status: 200, headers, body: JSON.stringify(card) };
}

export function a2aCompletedResponse(requestId: JsonValue, text: string): TunnelHttpResponse {
  const responseId = 'appless-' + Date.now().toString();
  const status: A2aCompletedStatus = {
    state: 'completed',
    timestamp: new Date().toISOString()
  };
  const part: A2aTextPart = { kind: 'text', text };
  const artifact: A2aArtifact = {
    artifactId: responseId + '-text',
    name: 'Appless response',
    parts: [part]
  };
  const result: A2aCompletedResult = {
    id: responseId,
    contextId: responseId,
    status,
    artifacts: [artifact]
  };
  const body: JsonRpcCompletedBody = {
    jsonrpc: '2.0',
    id: requestId ?? null,
    result
  };
  const headers: Record<string, string> = {};
  headers['content-type'] = 'application/json';
  return {
    status: 200,
    headers,
    body: JSON.stringify(body)
  };
}

export function tunnelRegistrationJson(config: ApplessRegistryConfig): string {
  const registration: TunnelRegistrationFrame = {
    type: 'register',
    device_id: config.deviceId
  };
  if (config.tunnelToken.length > 0) registration.token = config.tunnelToken;
  return JSON.stringify(registration);
}

export function tunnelForwardResponseJson(messageId: string, response: TunnelHttpResponse): string {
  const frame: TunnelForwardResponseFrame = {
    type: 'forward_response',
    message_id: messageId,
    http_response: response,
    status: response.status
  };
  return JSON.stringify(frame);
}
