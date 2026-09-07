import { extractJsonObjects, LocalModel } from '@loop/agent-core';

type JsonValue = Object | string | number | boolean | null | undefined;
type JsonRecord = Record<string, JsonValue>;

export const REGISTRY_PEER_DIRECT_MODE_ENABLED: boolean = false;
export const REGISTRY_PEER_SEND_FILE_TOOL_ID: string = 'registry.peer.send_latest_file';

export enum ApplessRegistryPeerAgentAction {
  REPLY = 'reply',
  SEND_FILE = 'send_file'
}

export interface ApplessRegistryPeerAgentDecision {
  action: ApplessRegistryPeerAgentAction;
  reply: string;
}

function record(value: JsonValue): JsonRecord | null {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return null;
  return value as JsonRecord;
}

function exactKeys(value: JsonRecord, expected: string): boolean {
  return Object.keys(value).sort().join(',') === expected;
}

function peerAgentSystemPrompt(): string {
  return [
    'You are the action planner for one Appless peer conversation.',
    'The message came from the other phone. Choose the file tool only when that peer asks this phone to send its ' +
      'newest sandbox file. Otherwise reply naturally and briefly.',
    'The only available tool is ' + REGISTRY_PEER_SEND_FILE_TOOL_ID + '.',
    'To use it, return exactly {"action":"tool","toolId":"' + REGISTRY_PEER_SEND_FILE_TOOL_ID +
      '","arguments":{}}.',
    'When no tool is needed, return exactly {"action":"reply","reply":"short response"}.',
    'Never claim that a file was sent unless you select the tool.',
    'Return one JSON object only, with no markdown or extra keys.'
  ].join('\n');
}

export function parseRegistryPeerAgentDecision(
  raw: string
): ApplessRegistryPeerAgentDecision {
  const objects = extractJsonObjects(raw);
  if (objects.length !== 1) throw new Error('Peer Agent returned an invalid decision.');
  const value = record(JSON.parse(objects[0]) as JsonValue);
  if (value === null || typeof value['action'] !== 'string') {
    throw new Error('Peer Agent decision has no action.');
  }
  const action = value['action'] as string;
  if (action === 'tool' && exactKeys(value, 'action,arguments,toolId') &&
    value['toolId'] === REGISTRY_PEER_SEND_FILE_TOOL_ID) {
    const args = record(value['arguments']);
    if (args !== null && Object.keys(args).length === 0) {
      return { action: ApplessRegistryPeerAgentAction.SEND_FILE, reply: '' };
    }
  }
  if (action === 'reply' && exactKeys(value, 'action,reply') && typeof value['reply'] === 'string') {
    const reply = (value['reply'] as string).trim();
    if (reply.length > 0 && reply.length <= 2000) {
      return { action: ApplessRegistryPeerAgentAction.REPLY, reply };
    }
  }
  throw new Error('Peer Agent selected an unsupported action.');
}

export async function planRegistryPeerAgentAction(
  model: LocalModel,
  message: string
): Promise<ApplessRegistryPeerAgentDecision> {
  const prompt = '[Peer message]\n' + message.trim();
  const raw = await model.complete(prompt, undefined, peerAgentSystemPrompt());
  return parseRegistryPeerAgentDecision(raw);
}
