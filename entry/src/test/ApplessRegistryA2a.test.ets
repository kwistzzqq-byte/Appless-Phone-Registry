import { describe, expect, it } from '@ohos/hypium';
import {
  ApplessRegistryConfig,
  parseApplessRegistryConfig,
  resetApplessRegistryConfigForTests
} from '../main/ets/registry/ApplessRegistryConfig';
import {
  a2aCompletedResponse,
  applessAgentCardResponse,
  tunnelForwardRequestFromJson,
  tunnelForwardResponseJson,
  tunnelRegistrationJson,
  validateA2aTextRequest
} from '../main/ets/registry/ApplessA2aProtocol';
import {
  parseRegistryAgentListResponse,
  parseRegistryAgentReply,
  parseRegistryTunnelStatusResponse,
  registryA2aRequestJson,
  registryPeerChatRequestJson
} from '../main/ets/registry/ApplessRegistryOutboundClient';
import {
  isApplessRegistryToolId,
  matchingRegistryTargets,
  registryAgentEntityRefs,
  registryStatusWithoutSelf,
  REGISTRY_LIST_TOOL_ID,
  REGISTRY_SEND_TOOL_ID,
  REGISTRY_STATUS_TOOL_ID,
  registryStandardToolsOwnPrompt
} from '../main/ets/registry/ApplessRegistryTools';

function config(token: string = ''): ApplessRegistryConfig {
  return {
    enabled: true,
    registryBaseUrl: 'http://registry.example.test:8000',
    relayUrl: 'ws://registry.example.test:8001',
    deviceId: 'Appless-Phone1',
    dataset: 'openclaw_devices',
    serviceId: 'Appless-Phone1',
    tunnelToken: token,
    inboundBearerToken: 'peer-bearer-token-that-is-long-enough',
    outboundPeerBearerToken: 'peer-bearer-token-that-is-long-enough',
    registryHttpBearerToken: '',
    modelBaseUrl: 'https://models.example.test/v1',
    modelName: 'test-model',
    modelApiKey: 'test-model-key',
    modelCustomParametersJson: '',
    maxPromptChars: 4000,
    reconnectIntervalMs: 3000
  };
}

function forwardRequest(authorization: string = 'Bearer peer-bearer-token-that-is-long-enough'): string {
  return '{"type":"forward_request","message_id":"forward-1",' +
    '"dataset":"openclaw_devices","service_id":"Appless-Phone1",' +
    '"http_request":{"method":"POST","path":"/a2a/jsonrpc",' +
    '"headers":{"Content-Type":"application/json","Authorization":' + JSON.stringify(authorization) + '},' +
    '"body":{"jsonrpc":"2.0","id":"rpc-1","method":"message/send",' +
    '"params":{"message":{"role":"user","parts":[' +
    '{"kind":"text","text":"只回复 ACK APPLESS_PHONE"}]}}}}}';
}

function agentCardRequest(): string {
  return '{"type":"forward_request","message_id":"card-1",' +
    '"dataset":"openclaw_devices","service_id":"Appless-Phone1",' +
    '"http_request":{"method":"GET","path":"/.well-known/agent-card.json","headers":{},"body":null}}';
}

function peerTunnelRequest(): string {
  return '{"type":"forward_request","message_id":"peer-1",' +
    '"source_device":"JiuwenSwarm-Mac","target_device":"Appless-Phone1",' +
    '"http_request":{"method":"POST","path":"/a2a/jsonrpc",' +
    '"headers":{"Authorization":"Bearer peer-bearer-token-that-is-long-enough"},' +
    '"body":{"jsonrpc":"2.0","id":"peer-rpc-1","method":"message/send",' +
    '"params":{"message":{"role":"user","parts":[{"kind":"text","text":"peer ping"}]}}}}}';
}

function peerChatRequest(senderServiceId: string = 'Appless-Phone2'): string {
  return '{"type":"forward_request","message_id":"peer-chat-1",' +
    '"dataset":"openclaw_devices","service_id":"Appless-Phone1",' +
    '"http_request":{"method":"POST","path":"/a2a/jsonrpc",' +
    '"headers":{"Authorization":"Bearer peer-bearer-token-that-is-long-enough"},' +
    '"body":{"jsonrpc":"2.0","id":"peer-chat-rpc-1","method":"message/send",' +
    '"params":{"message":{"role":"user","metadata":{"applessMode":"peer_chat",' +
    '"senderServiceId":' + JSON.stringify(senderServiceId) + '},"parts":[' +
    '{"kind":"text","text":"hello from phone 2"}]}}}}}';
}

export default function applessRegistryA2aTest(): void {
  describe('ApplessRegistryA2a', () => {
    it('accepts only complete ws Registry config without exposing credentials', 0, () => {
      resetApplessRegistryConfigForTests();
      const parsed = parseApplessRegistryConfig(JSON.stringify(config()));
      expect(parsed.enabled).assertTrue();
      expect(parsed.modelName).assertEqual('test-model');
      const invalidInput = config();
      invalidInput.relayUrl = 'http://registry';
      const invalid = parseApplessRegistryConfig(JSON.stringify(invalidInput));
      expect(invalid.enabled).assertFalse();
    });

    it('keeps Tunnel token optional and separate from peer Bearer', 0, () => {
      const withoutToken = JSON.parse(tunnelRegistrationJson(config())) as Record<string, string>;
      expect(withoutToken['device_id']).assertEqual('Appless-Phone1');
      expect(withoutToken['token']).assertUndefined();
      const withToken = JSON.parse(tunnelRegistrationJson(config('tunnel-secret'))) as Record<string, string>;
      expect(withToken['token']).assertEqual('tunnel-secret');
    });

    it('validates binding endpoint A2A method and Bearer before returning text', 0, () => {
      const request = tunnelForwardRequestFromJson(forwardRequest());
      expect(request === null).assertFalse();
      if (request === null) return;
      const accepted = validateA2aTextRequest(request, config());
      expect(accepted.ok).assertTrue();
      expect(accepted.requestId).assertEqual('rpc-1');
      expect(accepted.text).assertEqual('只回复 ACK APPLESS_PHONE');
      expect(accepted.peerChat).assertFalse();

      const missingBearerRequest = tunnelForwardRequestFromJson(forwardRequest(''));
      expect(missingBearerRequest === null).assertFalse();
      if (missingBearerRequest === null) return;
      expect(validateA2aTextRequest(missingBearerRequest, config()).status).assertEqual(401);
    });

    it('marks direct Appless peer chat without routing it through the Agent model', 0, () => {
      const request = tunnelForwardRequestFromJson(peerChatRequest());
      expect(request === null).assertFalse();
      if (request === null) return;
      const accepted = validateA2aTextRequest(request, config());
      expect(accepted.ok).assertTrue();
      expect(accepted.peerChat).assertTrue();
      expect(accepted.senderServiceId).assertEqual('Appless-Phone2');
      expect(accepted.text).assertEqual('hello from phone 2');

      const invalidRequest = tunnelForwardRequestFromJson(peerChatRequest('not a valid id'));
      expect(invalidRequest === null).assertFalse();
      if (invalidRequest === null) return;
      expect(validateA2aTextRequest(invalidRequest, config()).status).assertEqual(400);

      const outbound = JSON.parse(registryPeerChatRequestJson(
        'hello from phone 1', 'Appless-Phone1')) as Record<string, Object | string>;
      const params = outbound['params'] as Record<string, Object>;
      const message = params['message'] as Record<string, Object>;
      const metadata = message['metadata'] as Record<string, string>;
      expect(metadata['applessMode']).assertEqual('peer_chat');
      expect(metadata['senderServiceId']).assertEqual('Appless-Phone1');
    });

    it('serves the Agent Card through the same Tunnel before Jiuwen sends A2A', 0, () => {
      const request = tunnelForwardRequestFromJson(agentCardRequest());
      expect(request === null).assertFalse();
      if (request === null) return;
      const response = applessAgentCardResponse(request, config());
      expect(response === null).assertFalse();
      if (response === null) return;
      expect(response.status).assertEqual(200);
      const card = JSON.parse(response.body) as Record<string, Object | string>;
      expect(card['protocolVersion']).assertEqual('0.3.0');
      expect(card['url']).assertEqual('http://127.0.0.1:18800/a2a/jsonrpc');
    });

    it('accepts Jiuwen device-to-device Tunnel binding only for the configured target', 0, () => {
      const request = tunnelForwardRequestFromJson(peerTunnelRequest());
      expect(request === null).assertFalse();
      if (request === null) return;
      expect(validateA2aTextRequest(request, config()).ok).assertTrue();
      request.targetDevice = 'Another-Phone';
      expect(validateA2aTextRequest(request, config()).status).assertEqual(404);
    });

    it('returns the A2A completed artifact shape used by existing Jiuwen tooling', 0, () => {
      const response = a2aCompletedResponse('rpc-1', 'ACK APPLESS_PHONE');
      const body = JSON.parse(response.body) as Record<string, Object | string>;
      const result = body['result'] as Record<string, Object>;
      const status = result['status'] as Record<string, string>;
      const artifacts = result['artifacts'] as Object[];
      expect(response.status).assertEqual(200);
      expect(status['state']).assertEqual('completed');
      expect(artifacts.length).assertEqual(1);
      const frame = JSON.parse(tunnelForwardResponseJson('forward-1', response)) as Record<string, Object | string>;
      expect(frame['type']).assertEqual('forward_response');
      expect(frame['message_id']).assertEqual('forward-1');
    });

    it('discovers other Registry Agents and keeps Agent Card auth metadata', 0, () => {
      const raw = '[{"id":"Appless-Phone1","name":"Appless Phone","metadata":{}},' +
        '{"id":"HW-PC1","name":"HW-PC1-Agent1","description":"Remote desktop Agent",' +
        '"metadata":{"securitySchemes":{"bearer":{"type":"http","scheme":"bearer"}},' +
        '"metadata":{"tunnelDeviceId":"HW-PC1"}}}]';
      const agents = parseRegistryAgentListResponse(raw, 'Appless-Phone1');
      expect(agents.length).assertEqual(1);
      expect(agents[0].serviceId).assertEqual('HW-PC1');
      expect(agents[0].requiresBearer).assertTrue();
      expect(agents[0].tunnelDeviceId).assertEqual('HW-PC1');
      expect(registryAgentEntityRefs(agents).join(',')).assertEqual('HW-PC1');
    });

    it('reads optional live Tunnel device details without breaking old status responses', 0, () => {
      const detailed = parseRegistryTunnelStatusResponse('{"connected_devices":2,"bound_services":2,' +
        '"pending_requests":0,"online_devices":["HW-Phone1","Appless-Phone1","HW-Phone1"]}');
      expect(detailed.onlineDevices.join(',')).assertEqual('Appless-Phone1,HW-Phone1');
      const legacy = parseRegistryTunnelStatusResponse('{"connected_devices":2,"bound_services":2,' +
        '"pending_requests":0}');
      expect(legacy.onlineDevices.length).assertEqual(0);
    });

    it('filters the current Appless device only from the displayed online device list', 0, () => {
      const status = parseRegistryTunnelStatusResponse('{"connected_devices":3,"bound_services":3,' +
        '"pending_requests":0,"online_devices":["Appless-Phone1","Appless-Phone2","HW-PC1"]}');
      const visible = registryStatusWithoutSelf(status, 'Appless-Phone1');
      expect(visible.connectedDevices).assertEqual(3);
      expect(visible.boundServices).assertEqual(3);
      expect(visible.onlineDevices.join(',')).assertEqual('Appless-Phone2,HW-PC1');
    });

    it('builds standard message/send JSON-RPC and reads completed remote text', 0, () => {
      const request = JSON.parse(registryA2aRequestJson('hello peer')) as Record<string, Object | string>;
      expect(request['method']).assertEqual('message/send');
      const reply = parseRegistryAgentReply('{"jsonrpc":"2.0","id":"rpc-2",' +
        '"result":{"status":{"state":"completed"},"artifacts":[' +
        '{"parts":[{"kind":"text","text":"ACK OUTBOUND"}]}]}}', 'HW-PC1');
      expect(reply.state).assertEqual('completed');
      expect(reply.text).assertEqual('ACK OUTBOUND');
      const failed = parseRegistryAgentReply('{"jsonrpc":"2.0","id":"rpc-3",' +
        '"result":{"status":{"state":"failed","message":{"parts":[' +
        '{"kind":"text","text":"remote model unavailable"}]}}}}', 'HW-PC1');
      expect(failed.state).assertEqual('failed');
      expect(failed.text).assertEqual('remote model unavailable');
    });

    it('exposes Registry operations as standard Agent tools', 0, () => {
      expect(isApplessRegistryToolId(REGISTRY_LIST_TOOL_ID)).assertTrue();
      expect(isApplessRegistryToolId(REGISTRY_STATUS_TOOL_ID)).assertTrue();
      expect(isApplessRegistryToolId(REGISTRY_SEND_TOOL_ID)).assertTrue();
      expect(isApplessRegistryToolId('registry.keyword.router')).assertFalse();
      expect(registryStandardToolsOwnPrompt('注册中心有什么设备在线', [])).assertTrue();
      expect(registryStandardToolsOwnPrompt('现在在线的呢', ['注册中心有什么设备'])).assertTrue();
      expect(registryStandardToolsOwnPrompt('现在在线的呢', ['今晚吃什么'])).assertFalse();
      expect(registryStandardToolsOwnPrompt('今天有什么新闻', [])).assertFalse();
      const targets = parseRegistryAgentListResponse('[{"id":"HW-PC1","name":"HW-PC1-Agent1"},' +
        '{"id":"JiuwenSwarm-HW-PC1","name":"JiuwenSwarm-HW-PC1"}]', 'Appless-Phone1');
      expect(matchingRegistryTargets('pc1', targets).length).assertEqual(2);
      expect(matchingRegistryTargets('HW-PC1', targets).length).assertEqual(1);
      expect(matchingRegistryTargets('HW-PC1', targets)[0].serviceId).assertEqual('HW-PC1');
    });

  });
}
