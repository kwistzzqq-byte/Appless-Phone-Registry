import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { common } from '@kit.AbilityKit';

const MAX_AGENT_FILE_BYTES: number = 5 * 1024 * 1024;
const PPT_TRANSFER_MARKERS: string[] = ['发', '传', '给我', '给你', '给对方', '给对面', '过来'];
const PPT_DISCUSSION_MARKERS: string[] = ['怎么', '如何', '谁能', '知不知道', '是否', '为什么', '是什么', '介绍', '教程', '方法'];
const PPT_SEND_TO_PEER_MARKERS: string[] = ['给你', '给对方', '给对面', '我发', '我传'];

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

export enum ApplessPptTransferIntent {
  NONE,
  REQUEST_FROM_PEER,
  SEND_TO_PEER
}

function containsAny(text: string, markers: string[]): boolean {
  for (let index = 0; index < markers.length; index++) {
    if (text.indexOf(markers[index]) >= 0) return true;
  }
  return false;
}

export function pptTransferIntent(text: string): ApplessPptTransferIntent {
  const lower = text.toLowerCase();
  const mentionsPpt = lower.indexOf('ppt') >= 0 || text.indexOf('演示文稿') >= 0;
  if (!mentionsPpt || !containsAny(text, PPT_TRANSFER_MARKERS) ||
    containsAny(text, PPT_DISCUSSION_MARKERS)) return ApplessPptTransferIntent.NONE;
  if (containsAny(text, PPT_SEND_TO_PEER_MARKERS)) {
    return ApplessPptTransferIntent.SEND_TO_PEER;
  }
  return ApplessPptTransferIntent.REQUEST_FROM_PEER;
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

function latestRegistryInboxPpt(context: common.UIAbilityContext): ApplessAgentLocalFile | null {
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
      bytes: new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer), util.Type.BASIC),
      path: file.path
    };
  } finally {
    fs.closeSync(handle);
  }
}

export function latestRegistryInboxPptForTransfer(context: common.UIAbilityContext): ApplessAgentEncodedFile | null {
  const file = latestRegistryInboxPpt(context);
  return file === null ? null : encodeAgentFile(file);
}
