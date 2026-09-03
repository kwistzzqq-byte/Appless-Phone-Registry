import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import util from '@ohos.util';
import { aiLogError, aiLogInfo } from '@loop/agent-core';
import { ApplessRegistryConfig } from './ApplessRegistryConfig';
import {
  TunnelForwardRequest,
  TunnelHttpResponse,
  tunnelForwardRequestFromJson,
  tunnelForwardResponseJson,
  tunnelRegistrationJson
} from './ApplessA2aProtocol';

export type ApplessTunnelRequestHandler = (request: TunnelForwardRequest) => Promise<TunnelHttpResponse>;

export class ApplessTunnelClient {
  private readonly config: ApplessRegistryConfig;
  private readonly handler: ApplessTunnelRequestHandler;
  private socket: webSocket.WebSocket | null = null;
  private active: boolean = false;
  private connected: boolean = false;
  private reconnectTimer: number = -1;

  constructor(config: ApplessRegistryConfig, handler: ApplessTunnelRequestHandler) {
    this.config = config;
    this.handler = handler;
  }

  start(): void {
    if (this.active || !this.config.enabled) return;
    this.active = true;
    this.connect();
  }

  stop(): void {
    this.active = false;
    this.connected = false;
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    const current = this.socket;
    this.socket = null;
    if (current !== null) {
      current.close({ code: 1000, reason: 'Appless page left foreground' }).catch(() => {});
    }
  }

  private connect(): void {
    if (!this.active || this.socket !== null) return;
    const socket = webSocket.createWebSocket();
    this.socket = socket;
    socket.on('open', (error: BusinessError | undefined): void => {
      if (error) {
        this.onDisconnected('open_error_' + error.code.toString());
        return;
      }
      this.connected = true;
      aiLogInfo('[ApplessRegistryTunnel] stage=open device=' + this.config.deviceId);
      socket.send(tunnelRegistrationJson(this.config)).catch((sendError: Error): void => {
        this.onDisconnected('register_send_failed_' + sendError.message.substring(0, 80));
      });
    });
    socket.on('message', (error: BusinessError | undefined, value: string | ArrayBuffer): void => {
      if (error) {
        aiLogError('[ApplessRegistryTunnel] stage=message error=' + error.code.toString());
        return;
      }
      const raw = typeof value === 'string' ? value : util.TextDecoder.create('utf-8').decodeToString(
        new Uint8Array(value)
      );
      this.handleMessage(raw);
    });
    socket.on('close', (_error: BusinessError | undefined): void => {
      this.onDisconnected('closed');
    });
    socket.on('error', (error: BusinessError): void => {
      this.onDisconnected('socket_error_' + error.code.toString());
    });
    socket.connect(this.config.relayUrl).catch((error: Error): void => {
      this.onDisconnected('connect_failed_' + error.message.substring(0, 80));
    });
  }

  private handleMessage(raw: string): void {
    let frame: Record<string, Object | string | number | boolean | null | undefined> | null = null;
    try {
      const parsed = JSON.parse(raw) as Object;
      frame = parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed) ?
        parsed as Record<string, Object | string | number | boolean | null | undefined> : null;
    } catch (_error) {
      aiLogError('[ApplessRegistryTunnel] stage=decode result=invalid_json');
      return;
    }
    if (frame === null) return;
    const type = typeof frame['type'] === 'string' ? frame['type'] as string : '';
    if (type === 'registered') {
      aiLogInfo('[ApplessRegistryTunnel] stage=registered device=' + this.config.deviceId);
      return;
    }
    if (type === 'ping') {
      this.sendJson('{"type":"pong"}');
      return;
    }
    const request = tunnelForwardRequestFromJson(raw);
    if (request === null) return;
    this.handler(request).then((response: TunnelHttpResponse): void => {
      this.sendJson(tunnelForwardResponseJson(request.messageId, response));
    }).catch((_error: Error): void => {
      aiLogError('[ApplessRegistryTunnel] stage=forward result=handler_failed');
    });
  }

  private sendJson(raw: string): void {
    const current = this.socket;
    if (!this.connected || current === null) return;
    current.send(raw).catch((_error: Error): void => {
      this.onDisconnected('send_failed');
    });
  }

  private onDisconnected(reason: string): void {
    const wasConnected = this.connected;
    this.connected = false;
    this.socket = null;
    if (wasConnected || reason !== 'closed') {
      aiLogInfo('[ApplessRegistryTunnel] stage=disconnected reason=' + reason);
    }
    if (!this.active || this.reconnectTimer >= 0) return;
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      this.connect();
    }, this.config.reconnectIntervalMs);
  }
}
