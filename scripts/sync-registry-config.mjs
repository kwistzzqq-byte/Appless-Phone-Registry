import { chmodSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const rootDir = resolve(import.meta.dirname, '..');
const sourcePath = process.argv[2] ? resolve(process.argv[2]) : '';
const outputPath = resolve(rootDir, 'entry/src/main/resources/rawfile/appless_registry_config.json');

if (sourcePath.length === 0) {
  console.error('Usage: node scripts/sync-registry-config.mjs /absolute/path/to/a2a-sidecar.json');
  process.exit(1);
}

const source = JSON.parse(readFileSync(sourcePath, 'utf8'));
const plugin = source.pluginConfig ?? {};
const tunnel = plugin.tunnel ?? {};
const registry = plugin.registry ?? {};
const peerAuth = registry.defaultPeerAuth ?? {};
const bearer = typeof peerAuth.token === 'string' ? peerAuth.token.trim() : '';
const modelBaseUrl = (process.env.APPLESS_REGISTRY_MODEL_BASE_URL ?? 'https://yibuapi.com/v1').trim();
const modelName = (process.env.APPLESS_REGISTRY_MODEL_NAME ?? 'qwen3.8-max').trim();
const modelApiKey = (process.env.APPLESS_REGISTRY_MODEL_API_KEY ?? '').trim();
const modelCustomParametersJson = (process.env.APPLESS_REGISTRY_MODEL_CUSTOM_PARAMETERS_JSON ??
  '{"enable_thinking":false}').trim();
if (bearer.length < 8) {
  console.error('Source sidecar config is missing registry.defaultPeerAuth.token.');
  process.exit(1);
}
if (!/^https:\/\/[^\s]+$/.test(modelBaseUrl) || modelName.length === 0 || modelApiKey.length === 0) {
  console.error('Set APPLESS_REGISTRY_MODEL_API_KEY and a valid HTTPS model endpoint/model.');
  process.exit(1);
}

const config = {
  enabled: true,
  registryBaseUrl: typeof registry.baseUrl === 'string' ? registry.baseUrl : 'http://121.37.53.35:8000',
  relayUrl: typeof tunnel.relayUrl === 'string' ? tunnel.relayUrl : 'ws://121.37.53.35:8001',
  deviceId: 'Appless-Phone1',
  dataset: 'openclaw_devices',
  serviceId: 'Appless-Phone1',
  tunnelToken: typeof tunnel.token === 'string' ? tunnel.token : '',
  inboundBearerToken: bearer,
  outboundPeerBearerToken: bearer,
  registryHttpBearerToken: typeof registry.authToken === 'string' ? registry.authToken : '',
  modelBaseUrl,
  modelName,
  modelApiKey,
  modelCustomParametersJson,
  maxPromptChars: 4000,
  reconnectIntervalMs: 3000
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
chmodSync(outputPath, 0o600);
console.log('Synced Appless Registry config without printing credentials.');
