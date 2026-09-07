import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { common } from '@kit.AbilityKit';

const MAX_AGENT_FILE_BYTES: number = 5 * 1024 * 1024;

export interface ApplessAgentLocalFile {
  name: string;
  mimeType: string;
  byteLength: number;
  modifiedAt: number;
  path: string;
}

export interface ApplessAgentEncodedFile {
  name: string;
  mimeType: string;
  byteLength: number;
  bytes: string;
  path: string;
}

export function newestAgentFile(files: ApplessAgentLocalFile[]): ApplessAgentLocalFile | null {
  let newest: ApplessAgentLocalFile | null = null;
  files.forEach((file: ApplessAgentLocalFile): void => {
    if (file.name.toLowerCase().endsWith('.part')) return;
    if (newest === null || file.modifiedAt > newest.modifiedAt) newest = file;
  });
  return newest;
}

function mimeTypeForName(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
  if (lower.endsWith('.txt')) return 'text/plain';
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) return 'text/markdown';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.pptx')) {
    return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
  }
  if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
  return 'application/octet-stream';
}

function collectFiles(path: string, depth: number, result: ApplessAgentLocalFile[]): void {
  if (depth > 5) return;
  let entries: string[] = [];
  try {
    entries = fs.listFileSync(path);
  } catch (_error) {
    return;
  }
  entries.forEach((name: string): void => {
    const child = path + '/' + name;
    try {
      const stat = fs.statSync(child);
      if (stat.isDirectory()) {
        collectFiles(child, depth + 1, result);
      } else if (stat.isFile()) {
        result.push({
          name,
          mimeType: mimeTypeForName(name),
          byteLength: stat.size,
          modifiedAt: stat.mtime,
          path: child
        });
      }
    } catch (_error) {
    }
  });
}

function latestRegistryInboxFile(context: common.UIAbilityContext): ApplessAgentLocalFile | null {
  const files: ApplessAgentLocalFile[] = [];
  collectFiles(context.filesDir + '/registry-peer-inbox', 0, files);
  return newestAgentFile(files);
}

export function encodeAgentFile(file: ApplessAgentLocalFile): ApplessAgentEncodedFile {
  if (file.byteLength <= 0 || file.byteLength > MAX_AGENT_FILE_BYTES) {
    throw new Error('Agent file is empty or exceeds the 5 MiB inline limit.');
  }
  const handle = fs.openSync(file.path, fs.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(file.byteLength);
    const read = fs.readSync(handle.fd, buffer);
    if (read !== file.byteLength) throw new Error('Agent file read was incomplete.');
    return {
      name: file.name,
      mimeType: file.mimeType,
      byteLength: file.byteLength,
      bytes: new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer), util.Type.BASIC),
      path: file.path
    };
  } finally {
    fs.closeSync(handle);
  }
}

export function latestRegistryInboxFileForTransfer(context: common.UIAbilityContext): ApplessAgentEncodedFile | null {
  const file = latestRegistryInboxFile(context);
  return file === null ? null : encodeAgentFile(file);
}
