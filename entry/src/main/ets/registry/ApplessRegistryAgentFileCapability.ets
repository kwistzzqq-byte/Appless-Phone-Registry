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
}

export function isPptTransferRequest(text: string): boolean {
  const lower = text.toLowerCase();
  const mentionsPpt = lower.indexOf('ppt') >= 0 || text.indexOf('演示文稿') >= 0;
  const requestsTransfer = text.indexOf('发') >= 0 || text.indexOf('传') >= 0 ||
    text.indexOf('给我') >= 0 || text.indexOf('过来') >= 0;
  return mentionsPpt && requestsTransfer;
}

export function newestAgentPpt(files: ApplessAgentLocalFile[]): ApplessAgentLocalFile | null {
  let newest: ApplessAgentLocalFile | null = null;
  files.forEach((file: ApplessAgentLocalFile): void => {
    const lower = file.name.toLowerCase();
    if (!lower.endsWith('.ppt') && !lower.endsWith('.pptx')) return;
    if (newest === null || file.modifiedAt > newest.modifiedAt) newest = file;
  });
  return newest;
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
          mimeType: name.toLowerCase().endsWith('.pptx') ?
            'application/vnd.openxmlformats-officedocument.presentationml.presentation' :
            'application/vnd.ms-powerpoint',
          byteLength: stat.size,
          modifiedAt: stat.mtime,
          path: child
        });
      }
    } catch (_error) {
    }
  });
}

export function latestAgentPpt(context: common.UIAbilityContext): ApplessAgentLocalFile | null {
  const files: ApplessAgentLocalFile[] = [];
  collectFiles(context.filesDir + '/registry-peer-inbox', 0, files);
  return newestAgentPpt(files);
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
      bytes: new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer), util.Type.BASIC)
    };
  } finally {
    fs.closeSync(handle);
  }
}
