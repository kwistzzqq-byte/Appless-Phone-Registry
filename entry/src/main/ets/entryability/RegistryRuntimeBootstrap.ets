import { common } from '@kit.AbilityKit';
import util from '@ohos.util';
import { aiLogInfo } from '@loop/agent-core';
import { configureApplessRegistry } from '../registry/ApplessRegistryConfig';

const APPLESS_REGISTRY_CONFIG_RAWFILE: string = 'appless_registry_config.json';

export function loadApplessRegistryRuntimeConfig(context: common.Context): void {
  try {
    const bytes = context.resourceManager.getRawFileContentSync(APPLESS_REGISTRY_CONFIG_RAWFILE);
    const rawJson = util.TextDecoder.create('utf-8').decodeToString(bytes);
    const config = configureApplessRegistry(rawJson);
    aiLogInfo('[ApplessRegistryBootstrap] enabled=' + (config.enabled ? 'true' : 'false') +
      ' device=' + config.deviceId);
  } catch (_error) {
    aiLogInfo('[ApplessRegistryBootstrap] enabled=false reason=config_missing');
  }
}
