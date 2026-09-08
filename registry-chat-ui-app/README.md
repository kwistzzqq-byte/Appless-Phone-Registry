# Appless Chat UI

独立 HarmonyOS 静态聊天界面 Demo。启动后直接显示聊天页，不包含设备列表、网络、Registry、Tunnel、LLM、消息发送或文件读写。

## 构建

```bash
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

未签名 HAP 输出到 `entry/build/default/outputs/default/entry-default-unsigned.hap`。
