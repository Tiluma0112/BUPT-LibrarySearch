import { webview } from '@kit.ArkWeb';
import { LIBRARY_LOGIN_URL, OPAC_BASE_URL, PORTAL_BASE_URL, PORTAL_LOGIN_URL } from '../common/AppConfig';
import { ReaderProfile } from '../model/PersonalTypes';
import { PortalProfileBridge } from '../service/PortalProfileBridge';

@Component
export struct LibraryLogin {
  onAuthenticated: (profile: ReaderProfile) => void = (_profile: ReaderProfile) => {};
  onClose: () => void = () => {};
  @State statusText: string = '正在打开北邮统一身份认证…';
  private controller: webview.WebviewController = new webview.WebviewController();
  private completed: boolean = false;
  private verifying: boolean = false;
  private portalStage: boolean = false;
  private portalChecking: boolean = false;
  private verifyGeneration: number = 0;

  private async verifyPortal(): Promise<void> {
    const generation = ++this.verifyGeneration;

    // 1. 持久化 ArkWeb Cookie；当前会话的有效性仍须由网页资料验证。
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (_e) { /* 落盘失败不阻断，继续尝试读取 */ }

    // 2. 检查 OPAC 域名是否有 Cookie。存在 Cookie 本身并不等于认证成功。
    let hasSession = false;
    try {
      const cookie = webview.WebCookieManager.fetchCookieSync(OPAC_BASE_URL, false, true);
      hasSession = cookie.length > 0;
    } catch (_e) {
      hasSession = false;
    }

    if (this.completed || generation !== this.verifyGeneration) { return; }

    if (!hasSession) {
      this.portalChecking = false;
      this.statusText = '登录会话未建立，请重新完成认证';
      return;
    }

    // 3. Cookie 已确认存在，再通过桥接读取个人资料
    const profile = await PortalProfileBridge.read(this.controller);
    if (this.completed || generation !== this.verifyGeneration) { return; }

    this.portalChecking = false;
    if (profile) {
      this.completed = true;
      this.onAuthenticated(profile);
    } else {
      this.statusText = '登录成功但资料读取失败，请重试';
    }
  }

  build(): void {
    NavDestination() {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Button('返回')
            .height(44)
            .onClick(() => { this.onClose(); });
          Text('北邮统一身份认证')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .layoutWeight(1);
        }
        .padding({ left: 12, right: 16, top: 8, bottom: 4 })
        .width('100%')
        .backgroundColor($r('app.color.page_bg'));

        Text(this.statusText)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 16, right: 16, top: 4, bottom: 8 })
          .width('100%');

        Web({ src: LIBRARY_LOGIN_URL, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .metaViewport(true)
          .textZoomRatio(100)
          .onPageEnd((event: OnPageEndEvent) => {
            if (this.completed) { return; }

            if (event.url.startsWith('https://auth.bupt.edu.cn/')) {
              this.statusText = '请在北邮统一身份认证页面完成登录';
            } else if (this.portalStage && event.url.startsWith(PORTAL_BASE_URL) &&
              event.url.indexOf('/sso/login') < 0) {
              if (!this.portalChecking) {
                this.portalChecking = true;
                this.statusText = '正在核对登录状态…';
                this.verifyPortal();
              }
            } else if (event.url.startsWith(`${OPAC_BASE_URL}/reader-setting.html`)) {
              this.portalStage = true;
              this.statusText = '正在连接图书馆个人服务…';
              this.controller.loadUrl(PORTAL_LOGIN_URL);
            } else if (event.url.startsWith(OPAC_BASE_URL) &&
              event.url.indexOf('/cas/') < 0 && !this.verifying) {
              this.verifying = true;
              this.statusText = '正在验证图书馆会话…';
              this.controller.loadUrl(`${OPAC_BASE_URL}/reader-setting.html`);
            } else if (event.url.startsWith(`${OPAC_BASE_URL}/index.html`) && this.verifying) {
              this.statusText = '图书馆会话验证未通过，请重新登录';
              this.verifying = false;
            }
          })
          .width('100%')
          .layoutWeight(1);

        Button('重新打开认证页')
          .height(44)
          .margin({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => {
            this.verifyGeneration++;
            this.portalChecking = false;
            this.verifying = false;
            this.portalStage = false;
            this.completed = false;
            this.controller.loadUrl(LIBRARY_LOGIN_URL);
          });
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'));
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_bg'));
  }
}
