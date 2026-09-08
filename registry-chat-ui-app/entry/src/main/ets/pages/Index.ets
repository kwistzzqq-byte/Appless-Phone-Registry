import { webview } from '@kit.ArkWeb';

@Entry
@Component
struct Index {
  private readonly controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Stack() {
      Web({ src: $rawfile('peer-chat.html'), controller: this.controller })
        .javaScriptAccess(false)
        .domStorageAccess(false)
        .width('100%')
        .height('100%')
        .backgroundColor('#FFF9F4')
    }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFF9F4')
  }
}
