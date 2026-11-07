import { webview } from '@kit.ArkWeb';
import { PORTAL_BASE_URL, PORTAL_MY_LIBRARY_URL } from '../common/AppConfig';
import { ReaderProfile } from '../model/PersonalTypes';
import { PortalProfileBridge } from '../service/PortalProfileBridge';
import { LibraryDataService } from '../service/LibraryDataService';
import { ReaderProfileStore } from '../service/ReaderProfileStore';

@Component
export struct LibraryPortal {
  onClose: () => void = () => {};
  onProfile: (profile: ReaderProfile) => void = (_profile: ReaderProfile) => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private reading: boolean = false;

  private async syncProfile(): Promise<void> {
    const apiProfile = await LibraryDataService.loadPortalProfile();
    const pageProfile = await PortalProfileBridge.read(this.controller);
    this.reading = false;
    if (apiProfile || pageProfile) {
      const cached = ReaderProfileStore.load(getContext(this));
      this.onProfile({
        name: pageProfile?.name || apiProfile?.name || cached.name,
        studentId: pageProfile?.studentId || apiProfile?.studentId || cached.studentId,
        avatarUrl: pageProfile?.avatarUrl || apiProfile?.avatarUrl || cached.avatarUrl,
        avatarLocalUri: cached.avatarLocalUri
      });
    }
  }

  build(): void {
    NavDestination() {
      Column() {
        Row({ space: 12 }) {
          Button('返回')
            .height(44)
            .onClick(() => { this.onClose(); });
          Text('我的图书馆 · 网页')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1);
        }
        .padding({ left: 12, right: 16, top: 8, bottom: 4 })
        .width('100%');
        Web({ src: PORTAL_MY_LIBRARY_URL, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .metaViewport(true)
          .textZoomRatio(100)
          .onPageEnd((event: OnPageEndEvent) => {
            if (!this.reading && event.url.startsWith(PORTAL_BASE_URL) &&
              event.url.indexOf('/sso/login') < 0) {
              this.reading = true;
              this.syncProfile();
            }
          })
          .width('100%')
          .layoutWeight(1);
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'));
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_bg'));
  }
}
