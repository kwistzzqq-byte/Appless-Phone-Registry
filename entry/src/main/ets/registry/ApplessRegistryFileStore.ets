import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { common } from '@kit.AbilityKit';
import { hash } from '@kit.CoreFileKit';
import { A2aInboundFile } from './ApplessA2aProtocol';
import { ApplessRegistryConfig } from './ApplessRegistryConfig';

const MAX_INLINE_FILE_BYTES: number = 5 * 1024 * 1024;
const MAX_RELAY_FILE_BYTES: number = 50 * 1024 * 1024;

export interface RegistryPeerStoredFile {
  attachmentId: string;
  name: string;
  mimeType: string;
  byteLength: number;
  sha256: string;
  path: string;
}

export function safeRegistryFileName(value: string): string {
  const name = value.trim();
  if (name.length === 0 || name.length > 180 || name === '.' || name === '..' ||
    name.indexOf('/') >= 0 || name.indexOf('\\') >= 0 || /[\u0000-\u001f\u007f]/.test(name)) return '';
  return name;
}

export function registryArtifactRelayUriAllowed(uri: string, registryBaseUrl: string): boolean {
  const base = registryBaseUrl.trim().replace(/\/+$/, '');
  const prefix = base + '/api/artifact-relay/uri/';
  if (base.length === 0 || !uri.startsWith(prefix) || uri.indexOf('#') >= 0) return false;
  const suffix = uri.substring(prefix.length);
  return suffix.length > 2 && suffix.indexOf('/') > 0 && suffix.indexOf('?') < 0;
}

function safePathSegment(value: string): string {
  const normalized = value.replace(/[^A-Za-z0-9._-]/g, '_');
  return normalized.length > 0 ? normalized.substring(0, 128) : 'peer';
}

function normalizedMimeType(value: string): string {
  const mime = value.trim().toLowerCase();
  return /^[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*$/.test(mime) ?
    mime : 'application/octet-stream';
}

function exactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) return bytes.buffer as ArrayBuffer;
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer as ArrayBuffer;
}

function inlineBytes(encoded: string): Uint8Array {
  const bytes = new util.Base64Helper().decodeSync(encoded, util.Type.BASIC);
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_INLINE_FILE_BYTES) {
    throw new Error('Inline file exceeds the 5 MiB receiver limit.');
  }
  return bytes;
}

async function relayBytes(uri: string, config: ApplessRegistryConfig): Promise<Uint8Array> {
  if (!registryArtifactRelayUriAllowed(uri, config.registryBaseUrl)) {
    throw new Error('Artifact Relay URI is outside the configured Registry origin.');
  }
  const request = http.createHttp();
  try {
    const response = await request.request(uri, {
      method: http.RequestMethod.GET,
      header: { 'Accept': 'application/octet-stream' },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 10000,
      readTimeout: 120000,
      maxRedirects: 0
    });
    if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
      throw new Error('Artifact Relay download failed with HTTP ' + response.responseCode.toString() + '.');
    }
    const bytes = new Uint8Array(response.result);
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_RELAY_FILE_BYTES) {
      throw new Error('Artifact Relay file is empty or exceeds the 50 MiB receiver limit.');
    }
    return bytes;
  } finally {
    request.destroy();
  }
}

function pathExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (_error) {
    return false;
  }
}

function deleteIfPresent(path: string): void {
  if (!pathExists(path)) return;
  try {
    fs.unlinkSync(path);
  } catch (_error) {
  }
}

export async function storeRegistryPeerFile(
  context: common.UIAbilityContext,
  config: ApplessRegistryConfig,
  senderServiceId: string,
  messageId: string,
  input: A2aInboundFile
): Promise<RegistryPeerStoredFile> {
  const name = safeRegistryFileName(input.name);
  if (name.length === 0) throw new Error('File name is unsafe.');
  const bytes = input.bytes.length > 0 ? inlineBytes(input.bytes) : await relayBytes(input.uri, config);
  const attachmentId = safePathSegment(senderServiceId) + '-' + Date.now().toString() + '-' +
    safePathSegment(messageId);
  const directory = context.filesDir + '/registry-peer-inbox/' + safePathSegment(senderServiceId) + '/' + attachmentId;
  fs.mkdirSync(directory, true);
  const finalPath = directory + '/' + name;
  const partialPath = finalPath + '.part';
  let file: fs.File | null = null;
  try {
    file = fs.openSync(partialPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const written = fs.writeSync(file.fd, exactArrayBuffer(bytes));
    fs.closeSync(file);
    file = null;
    if (written !== bytes.byteLength || fs.statSync(partialPath).size !== bytes.byteLength) {
      throw new Error('File write was incomplete.');
    }
    const digest = (await hash.hash(partialPath, 'sha256')).toLowerCase();
    fs.renameSync(partialPath, finalPath);
    return {
      attachmentId,
      name,
      mimeType: normalizedMimeType(input.mimeType),
      byteLength: bytes.byteLength,
      sha256: digest,
      path: finalPath
    };
  } catch (error) {
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (_closeError) {
      }
    }
    deleteIfPresent(partialPath);
    throw error instanceof Error ? error : new Error(JSON.stringify(error));
  }
}
