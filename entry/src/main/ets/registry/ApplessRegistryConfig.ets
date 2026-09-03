export interface ApplessRegistryConfig {
  enabled: boolean;
  registryBaseUrl: string;
  relayUrl: string;
  deviceId: string;
  dataset: string;
  serviceId: string;
  tunnelToken: string;
  inboundBearerToken: string;
  outboundPeerBearerToken: string;
  registryHttpBearerToken: string;
  modelBaseUrl: string;
  modelName: string;
  modelApiKey: string;
  modelCustomParametersJson: string;
  maxPromptChars: number;
  reconnectIntervalMs: number;
}

type ConfigValue = Object | string | number | boolean | null | undefined;
type ConfigRecord = Record<string, ConfigValue>;

const DEFAULT_CONFIG: ApplessRegistryConfig = {
  enabled: false,
  registryBaseUrl: '',
  relayUrl: '',
  deviceId: '',
  dataset: '',
  serviceId: '',
  tunnelToken: '',
  inboundBearerToken: '',
  outboundPeerBearerToken: '',
  registryHttpBearerToken: '',
  modelBaseUrl: '',
  modelName: '',
  modelApiKey: '',
  modelCustomParametersJson: '',
  maxPromptChars: 4000,
  reconnectIntervalMs: 3000
};

let currentConfig: ApplessRegistryConfig = cloneConfig(DEFAULT_CONFIG);

function text(record: ConfigRecord, key: string): string {
  const value = record[key];
  return typeof value === 'string' ? value.trim() : '';
}

function boundedInteger(record: ConfigRecord, key: string, fallback: number, minimum: number, maximum: number): number {
  const value = record[key];
  if (typeof value !== 'number' || !Number.isInteger(value)) return fallback;
  return Math.min(maximum, Math.max(minimum, value));
}

function validIdentity(value: string): boolean {
  return /^[A-Za-z0-9._-]{1,128}$/.test(value);
}

function cloneConfig(config: ApplessRegistryConfig): ApplessRegistryConfig {
  return {
    enabled: config.enabled,
    registryBaseUrl: config.registryBaseUrl,
    relayUrl: config.relayUrl,
    deviceId: config.deviceId,
    dataset: config.dataset,
    serviceId: config.serviceId,
    tunnelToken: config.tunnelToken,
    inboundBearerToken: config.inboundBearerToken,
    outboundPeerBearerToken: config.outboundPeerBearerToken,
    registryHttpBearerToken: config.registryHttpBearerToken,
    modelBaseUrl: config.modelBaseUrl,
    modelName: config.modelName,
    modelApiKey: config.modelApiKey,
    modelCustomParametersJson: config.modelCustomParametersJson,
    maxPromptChars: config.maxPromptChars,
    reconnectIntervalMs: config.reconnectIntervalMs
  };
}

export function parseApplessRegistryConfig(rawJson: string): ApplessRegistryConfig {
  const parsed = JSON.parse(rawJson) as ConfigRecord;
  const relayUrl = text(parsed, 'relayUrl');
  const registryBaseUrl = text(parsed, 'registryBaseUrl');
  const deviceId = text(parsed, 'deviceId');
  const dataset = text(parsed, 'dataset');
  const serviceId = text(parsed, 'serviceId');
  const inboundBearerToken = text(parsed, 'inboundBearerToken');
  const outboundPeerBearerToken = text(parsed, 'outboundPeerBearerToken') || inboundBearerToken;
  const enabled = parsed['enabled'] === true;
  const valid = enabled && /^https?:\/\/[^\s]+$/.test(registryBaseUrl) && /^ws:\/\/[^\s]+$/.test(relayUrl) &&
    validIdentity(deviceId) &&
    validIdentity(dataset) && validIdentity(serviceId) && inboundBearerToken.length >= 8;
  return {
    enabled: valid,
    registryBaseUrl,
    relayUrl,
    deviceId,
    dataset,
    serviceId,
    tunnelToken: text(parsed, 'tunnelToken'),
    inboundBearerToken,
    outboundPeerBearerToken,
    registryHttpBearerToken: text(parsed, 'registryHttpBearerToken'),
    modelBaseUrl: text(parsed, 'modelBaseUrl'),
    modelName: text(parsed, 'modelName'),
    modelApiKey: text(parsed, 'modelApiKey'),
    modelCustomParametersJson: text(parsed, 'modelCustomParametersJson'),
    maxPromptChars: boundedInteger(parsed, 'maxPromptChars', 4000, 1, 12000),
    reconnectIntervalMs: boundedInteger(parsed, 'reconnectIntervalMs', 3000, 500, 30000)
  };
}

export function configureApplessRegistry(rawJson: string): ApplessRegistryConfig {
  currentConfig = parseApplessRegistryConfig(rawJson);
  return cloneConfig(currentConfig);
}

export function applessRegistryConfig(): ApplessRegistryConfig {
  return cloneConfig(currentConfig);
}

export function resetApplessRegistryConfigForTests(): void {
  currentConfig = cloneConfig(DEFAULT_CONFIG);
}
