import { A2uiLabelValueData, DataResult, DynamicGenericToolResult } from '@loop/agent-core';
import { applessRegistryConfig } from './ApplessRegistryConfig';
import {
  getRegistryTunnelStatus,
  listRegistryAgents,
  RegistryAgentReply,
  RegistryAgentSummary,
  RegistryTunnelStatus,
  sendRegistryAgentMessage
} from './ApplessRegistryOutboundClient';

type ArgValue = Object | string | number | boolean | null | undefined;
type ArgRecord = Record<string, ArgValue>;

interface RegistryToolData {
  summary: string;
  results: DynamicGenericToolResult[];
  entityRefs: string[];
}

export const REGISTRY_LIST_TOOL_ID: string = 'registry.list';
export const REGISTRY_STATUS_TOOL_ID: string = 'registry.status';
export const REGISTRY_SEND_TOOL_ID: string = 'registry.send';

export function isApplessRegistryToolId(toolId: string): boolean {
  return toolId === REGISTRY_LIST_TOOL_ID || toolId === REGISTRY_STATUS_TOOL_ID ||
    toolId === REGISTRY_SEND_TOOL_ID;
}

function containsAny(text: string, words: string[]): boolean {
  for (let index = 0; index < words.length; index++) {
    if (text.indexOf(words[index]) >= 0) return true;
  }
  return false;
}

function explicitRegistryReference(text: string): boolean {
  const lower = text.toLowerCase();
  return text.indexOf('注册中心') >= 0 || lower.indexOf('agent registry') >= 0 ||
    lower.indexOf('registry.') >= 0 || lower.indexOf('a2a') >= 0 || lower.indexOf('tunnel') >= 0 ||
    /HW-(Phone|PC)\d*|JiuwenSwarm|jiuwenclaw|Appless-Phone/i.test(text);
}

export function registryStandardToolsOwnPrompt(prompt: string, recentConversationTexts: string[]): boolean {
  if (explicitRegistryReference(prompt)) return true;
  if (!containsAny(prompt, ['在线', '连接', '这些', '它们', '哪个', '哪些', '现在', '刚才',
    '第一个', '第二个', '第1个', '第2个', '给他', '发给'])) {
    return false;
  }
  const start = Math.max(0, recentConversationTexts.length - 6);
  for (let index = recentConversationTexts.length - 1; index >= start; index--) {
    if (explicitRegistryReference(recentConversationTexts[index])) return true;
  }
  return false;
}

function textArg(args: Object, keys: string[]): string {
  const values = args as ArgRecord;
  for (let index = 0; index < keys.length; index++) {
    const value = values[keys[index]];
    if (typeof value === 'string' && value.trim().length > 0) return value.trim();
  }
  return '';
}

function registryResult(
  toolId: string,
  status: 'success' | 'partial' | 'error',
  title: string,
  summary: string,
  rows: A2uiLabelValueData[],
  rawPreview: string,
  entityRefs: string[] = []
): DataResult {
  const result: DynamicGenericToolResult = {
    sourceTag: 'Appless Agent Registry',
    toolName: toolId,
    title,
    status,
    summary,
    rows,
    rawPreview
  };
  const data: RegistryToolData = { summary, results: [result], entityRefs: entityRefs.slice() };
  return {
    toolId,
    outputSchema: 'genericToolResults',
    status,
    sources: [{
      provider: 'Appless Agent Registry',
      backend: 'local_adapter',
      operation: toolId,
      fetchedAt: new Date().toISOString()
    }],
    data: data as Object,
    warnings: []
  };
}

export function registryAgentEntityRefs(agents: RegistryAgentSummary[]): string[] {
  const refs: string[] = [];
  for (let index = 0; index < agents.length; index++) {
    const serviceId = agents[index].serviceId.trim();
    if (serviceId.length > 0 && refs.indexOf(serviceId) < 0) refs.push(serviceId);
  }
  return refs;
}

function agentListSummary(agents: RegistryAgentSummary[]): string {
  if (agents.length === 0) return '注册中心没有发现其他 Agent。';
  const lines: string[] = ['注册中心发现 ' + agents.length.toString() + ' 个其他 Agent：'];
  for (let index = 0; index < agents.length; index++) {
    lines.push(agents[index].name + '（serviceId=' + agents[index].serviceId + '）');
  }
  return lines.join('\n');
}

function compactIdentity(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function matchingRegistryTargets(target: string, agents: RegistryAgentSummary[]): RegistryAgentSummary[] {
  const wanted = target.trim().toLowerCase();
  const compactWanted = compactIdentity(target);
  const exact: RegistryAgentSummary[] = [];
  for (let index = 0; index < agents.length; index++) {
    if (agents[index].serviceId.toLowerCase() === wanted || agents[index].name.toLowerCase() === wanted ||
      compactIdentity(agents[index].serviceId) === compactWanted || compactIdentity(agents[index].name) === compactWanted) {
      exact.push(agents[index]);
    }
  }
  if (exact.length > 0) return exact;
  const fuzzy: RegistryAgentSummary[] = [];
  if (compactWanted.length === 0) return fuzzy;
  for (let index = 0; index < agents.length; index++) {
    if (compactIdentity(agents[index].serviceId).indexOf(compactWanted) >= 0 ||
      compactIdentity(agents[index].name).indexOf(compactWanted) >= 0) {
      fuzzy.push(agents[index]);
    }
  }
  return fuzzy;
}

function targetCandidatesText(target: string, candidates: RegistryAgentSummary[]): string {
  if (candidates.length === 0) {
    return '注册中心找不到与“' + target + '”匹配的 Agent。请先使用 registry.list 查看完整 serviceId。';
  }
  const ids: string[] = [];
  for (let index = 0; index < candidates.length; index++) ids.push(candidates[index].serviceId);
  return '“' + target + '”匹配到多个 Agent，请明确选择完整 serviceId：' + ids.join('、') + '。';
}

function statusSummary(status: RegistryTunnelStatus): string {
  const details = status.onlineDevices.length > 0 ?
    '；当前在线设备：' + status.onlineDevices.join('、') + '。' :
    '。状态接口当前只提供汇总，不能据此断言每一条注册记录都在线。';
  return 'Tunnel 当前连接设备 ' + status.connectedDevices.toString() + ' 个，绑定服务 ' +
    status.boundServices.toString() + ' 个，待处理请求 ' + status.pendingRequests.toString() +
    ' 个' + details;
}

export function registryStatusWithoutSelf(
  status: RegistryTunnelStatus,
  selfDeviceId: string
): RegistryTunnelStatus {
  return {
    connectedDevices: status.connectedDevices,
    boundServices: status.boundServices,
    pendingRequests: status.pendingRequests,
    onlineDevices: status.onlineDevices.filter((deviceId: string): boolean =>
      deviceId !== selfDeviceId)
  };
}

export async function executeApplessRegistryTool(
  toolId: string,
  prompt: string,
  args: Object
): Promise<DataResult> {
  const config = applessRegistryConfig();
  if (!config.enabled) throw new Error('APPLESS_REGISTRY_NOT_CONFIGURED');
  if (toolId === REGISTRY_LIST_TOOL_ID) {
    const agents = await listRegistryAgents(config);
    const summary = agentListSummary(agents);
    const rows: A2uiLabelValueData[] = [];
    rows.push({ label: '其他 Agent', value: agents.length.toString() });
    return registryResult(
      toolId,
      'success',
      '注册中心 Agent',
      summary,
      rows,
      JSON.stringify(agents),
      registryAgentEntityRefs(agents)
    );
  }
  if (toolId === REGISTRY_STATUS_TOOL_ID) {
    const status = registryStatusWithoutSelf(await getRegistryTunnelStatus(config), config.deviceId);
    const summary = statusSummary(status);
    const rows: A2uiLabelValueData[] = [];
    rows.push({ label: '连接设备', value: status.connectedDevices.toString() });
    rows.push({ label: '绑定服务', value: status.boundServices.toString() });
    rows.push({ label: '待处理请求', value: status.pendingRequests.toString() });
    for (let index = 0; index < status.onlineDevices.length; index++) {
      rows.push({ label: '在线设备 ' + (index + 1).toString(), value: status.onlineDevices[index] });
    }
    return registryResult(toolId, 'success', '注册中心在线状态', summary, rows, JSON.stringify(status));
  }
  if (toolId !== REGISTRY_SEND_TOOL_ID) throw new Error('APPLESS_REGISTRY_TOOL_UNKNOWN');
  const targetValue = textArg(args, ['serviceId', 'target', 'peer', 'agentId']);
  const message = textArg(args, ['message', 'text', 'request', 'prompt']) || prompt.trim();
  if (targetValue.length === 0 || message.length === 0) throw new Error('REGISTRY_SEND_ARGS_INVALID');
  const agents = await listRegistryAgents(config);
  const candidates = matchingRegistryTargets(targetValue, agents);
  if (candidates.length !== 1) {
    const summary = targetCandidatesText(targetValue, candidates);
    const rows: A2uiLabelValueData[] = [];
    rows.push({ label: '目标输入', value: targetValue });
    for (let index = 0; index < candidates.length; index++) {
      rows.push({ label: '候选 ' + (index + 1).toString(), value: candidates[index].serviceId });
    }
    return registryResult(toolId, 'partial', '需要确认目标 Agent', summary, rows, JSON.stringify(candidates));
  }
  const target = candidates[0];
  if (message.length > config.maxPromptChars) throw new Error('REGISTRY_MESSAGE_TOO_LARGE');
  if (target.requiresBearer && config.outboundPeerBearerToken.length === 0) {
    throw new Error('REGISTRY_TARGET_BEARER_MISSING');
  }
  const reply: RegistryAgentReply = await sendRegistryAgentMessage(config, target.serviceId, message);
  const summary = target.name + ' 返回 ' + reply.state + '：' + reply.text;
  const rows: A2uiLabelValueData[] = [];
  rows.push({ label: '目标', value: target.name + ' (' + target.serviceId + ')' });
  rows.push({ label: '状态', value: reply.state });
  rows.push({ label: '回复', value: reply.text });
  return registryResult(
    toolId,
    reply.state === 'completed' ? 'success' : 'error',
    'A2A Agent 回复',
    summary,
    rows,
    JSON.stringify(reply)
  );
}
