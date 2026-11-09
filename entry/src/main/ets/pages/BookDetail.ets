import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { displayText } from '../common/Format';
import { BookDetailResponse, Holding } from '../model/Types';
import { OpacService } from '../service/OpacService';
import { FavoritesStore } from '../service/FavoritesStore';
import { FavoriteBook } from '../model/FavoriteBook';

interface HoldingLocation {
  url: string;
  text: string;
}

@Component
export struct BookDetail {
  @Prop bookId: string;
  onClose: () => void = () => {};
  @State detail: BookDetailResponse | null = null;
  @State loading: boolean = false;
  @State errorText: string = '';
  @State mapUrl: string = '';
  @State mapStatus: string = 'none';
  @State mapExpanded: boolean = false;
  @State expandedHoldingKey: string = '';
  @State holdingLocations: HoldingLocation[] = [];
  @State isFavorite: boolean = false;
  @State mapTopInset: number = 0;
  @State mapBottomInset: number = 0;
  private mapVersion: number = 0;
  private detailVersion: number = 0;
  private locationRequests: Map<string, Promise<string>> = new Map();
  private mapController: webview.WebviewController = new webview.WebviewController();
  private fullMapController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    window.getLastWindow(getContext(this) as common.UIAbilityContext).then((appWindow: window.Window) => {
      this.mapTopInset = this.getUIContext().px2vp(
        appWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
      this.mapBottomInset = this.getUIContext().px2vp(
        appWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
    }).catch(() => {});
    this.isFavorite = FavoritesStore.contains(getContext(this), this.bookId);
    this.loadDetail();
  }

  aboutToDisappear(): void {
    this.detailVersion++;
    this.mapVersion++;
  }

  private toggleFavorite(): void {
    if (!this.detail) { return; }
    const book: FavoriteBook = {
      id: this.detail.id,
      title: this.detail.title,
      responsibility: this.detail.responsibility || '',
      publication: this.detail.publication || ''
    };
    this.isFavorite = FavoritesStore.toggle(getContext(this), book);
  }

  private async loadDetail(): Promise<void> {
    const version = ++this.detailVersion;
    this.loading = true;
    this.errorText = '';
    this.holdingLocations = [];
    this.mapVersion++;
    this.mapExpanded = false;
    this.expandedHoldingKey = '';
    this.mapUrl = '';
    this.mapStatus = 'none';
    this.locationRequests.clear();
    try {
      const detail = await OpacService.detail(this.bookId);
      if (version !== this.detailVersion) { return; }
      this.detail = detail;
      this.loadAllHoldingLocations(detail.holdings, version);
    } catch (error) {
      if (version === this.detailVersion) {
        this.errorText = error instanceof Error ? error.message : '详情加载失败，请重试';
      }
    } finally {
      if (version === this.detailVersion) { this.loading = false; }
    }
  }

  private async resolveLocation(url: string, version: number): Promise<string> {
    const cached = this.holdingLocations.find((item: HoldingLocation): boolean => item.url === url);
    if (cached) { return cached.text; }
    const pending = this.locationRequests.get(url);
    if (pending) { return pending; }
    const request = OpacService.shelfLocationFromMap(url);
    this.locationRequests.set(url, request);
    let location = '';
    try {
      location = await request;
    } catch (_error) {}
    if (version === this.detailVersion) {
      if (location) {
        this.holdingLocations = [...this.holdingLocations, { url: url, text: location }];
      }
      this.locationRequests.delete(url);
    }
    return location;
  }

  private async loadAllHoldingLocations(holdings: Holding[], version: number): Promise<void> {
    const urls: string[] = [];
    holdings.forEach((holding: Holding) => {
      if (holding.navigation_url && urls.indexOf(holding.navigation_url) < 0) {
        urls.push(holding.navigation_url);
      }
    });
    let next = 0;
    const worker = async (): Promise<void> => {
      while (next < urls.length && version === this.detailVersion) {
        const url = urls[next++];
        await this.resolveLocation(url, version);
      }
    };
    await Promise.all([worker(), worker(), worker()]);
  }

  private holdingLocation(holding: Holding): string {
    const found = this.holdingLocations.find((item: HoldingLocation): boolean =>
      item.url === holding.navigation_url);
    if (found) { return found.text; }
    return holding.shelf_location ||
      `按索书号 ${displayText(holding.call_number)} 查找`;
  }

  private async toggleHoldingMap(holding: Holding, key: string): Promise<void> {
    const version = ++this.mapVersion;
    if (this.expandedHoldingKey === key) {
      this.expandedHoldingKey = '';
      this.mapStatus = 'none';
      return;
    }
    this.expandedHoldingKey = key;
    this.mapUrl = OpacService.mapPreviewUrl(holding.navigation_url);
    this.mapStatus = 'checking';
    const available = await OpacService.navigationAvailable(holding.navigation_url);
    if (version === this.mapVersion && this.expandedHoldingKey === key) {
      this.mapStatus = available ? 'available' : 'unavailable';
    }
  }

  @Builder
  private fullMap(): void {
    Column({ space: 0 }) {
      Row() {
        Text('馆藏架位地图')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1);
        Button('关闭')
          .height(44)
          .onClick(() => { this.mapExpanded = false; });
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 });
      Stack() {
        Web({ src: this.mapUrl, controller: this.fullMapController })
          .onControllerAttached(() => {
            this.fullMapController.setCustomUserAgent(`${this.fullMapController.getUserAgent()} Android`);
          })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .metaViewport(true)
          .zoomAccess(true)
          .width('100%')
          .height('100%');
      }
      .width('100%')
      .layoutWeight(1);
      Text('双指捏合可缩放地图')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.mapTopInset, bottom: this.mapBottomInset })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.page_bg'));
  }

  @Builder
  private inlineMap(holding: Holding): void {
    Column({ space: 8 }) {
      Row() {
        Text('此馆藏架位地图')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1);
        if (this.mapStatus === 'available') {
          Button('全屏预览')
            .height(44)
            .onClick(() => { this.mapExpanded = true; });
        }
      }
      .width('100%');
      if (this.mapStatus === 'available') {
        Web({ src: this.mapUrl, controller: this.mapController })
          .onControllerAttached(() => {
            this.mapController.setCustomUserAgent(`${this.mapController.getUserAgent()} Android`);
          })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .metaViewport(true)
          .zoomAccess(true)
          .width('100%')
          .height(260);
      } else if (this.mapStatus === 'checking') {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20);
          Text('正在连接架位地图…').fontColor($r('app.color.text_secondary'));
        }
        .height(72);
      } else {
        Image($r('app.media.shelf_navigation'))
          .width('100%')
          .height(124)
          .objectFit(ImageFit.Contain);
        Text('当前网络无法访问馆方架位服务，请连接校园网后重试。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'));
        Button('重新检测')
          .height(44)
          .onClick(() => {
            this.mapStatus = 'checking';
            const version = ++this.mapVersion;
            OpacService.navigationAvailable(holding.navigation_url).then((available: boolean) => {
              if (version === this.mapVersion) {
                this.mapStatus = available ? 'available' : 'unavailable';
              }
            });
          });
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8 })
    .width('100%')
    .borderRadius(12);
  }

  private departments(): string[] {
    if (!this.detail) { return []; }
    const names: string[] = [];
    this.detail.holdings.forEach((holding: Holding) => {
      const name = holding.department || '未标注馆藏部门';
      if (names.indexOf(name) < 0) { names.push(name); }
    });
    return names;
  }

  private holdingsIn(department: string): Holding[] {
    return this.detail?.holdings.filter((holding: Holding): boolean =>
      (holding.department || '未标注馆藏部门') === department) ?? [];
  }

  @Builder
  private metadataRow(label: string, value?: string): void {
    if (value && value.trim()) {
      Row() {
        Text(label)
          .fontColor($r('app.color.text_secondary'))
          .fontSize(14)
          .width(92);
        Text(value)
          .fontColor($r('app.color.text_primary'))
          .fontSize(14)
          .copyOption(CopyOptions.LocalDevice)
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 6, bottom: 6 });
    }
  }

  @Builder
  private holdingCard(holding: Holding, key: string): void {
    Column({ space: 8 }) {
      Row() {
        Text(holding.status || '状态未知')
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .layoutWeight(1);
        Text(holding.volume || '')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'));
      }
      .width('100%');
      this.metadataRow('索书号', displayText(holding.call_number));
      this.metadataRow('图书条码', displayText(holding.barcode));
      this.metadataRow('登录号', holding.accession_number);
      Row() {
        Text('图书架位')
          .fontColor($r('app.color.text_secondary')).fontSize(14).width(92);
        Text(this.holdingLocations.find((item: HoldingLocation): boolean =>
          item.url === holding.navigation_url)?.text || holding.shelf_location ||
          `按索书号 ${displayText(holding.call_number)} 查找`)
          .fontColor($r('app.color.text_primary')).fontSize(14)
          .copyOption(CopyOptions.LocalDevice).layoutWeight(1);
      }
      .width('100%').alignItems(VerticalAlign.Top).padding({ top: 6, bottom: 6 });
      if (holding.navigation_url) {
        Button(this.expandedHoldingKey === key ? '收起架位地图' : '查看架位地图')
          .height(44)
          .onClick(() => { this.toggleHoldingMap(holding, key); });
        if (this.expandedHoldingKey === key) {
          this.inlineMap(holding);
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16);
  }

  build(): void {
    NavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          Row() {
            Button('返回')
              .height(44)
              .onClick(() => { this.onClose(); });
          }
          .width('100%');
          if (this.loading) {
            Row({ space: 10 }) {
              LoadingProgress().width(24).height(24);
              Text('正在加载详情…').fontColor($r('app.color.text_secondary'));
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding(28);
          } else if (this.errorText) {
            Column({ space: 12 }) {
              Text(this.errorText).fontColor($r('app.color.text_primary'));
              Button('重试').height(44).onClick(() => { this.loadDetail(); });
            }
            .padding(28)
            .width('100%');
          } else if (this.detail) {
            Column({ space: 8 }) {
              Text(this.detail.title)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .copyOption(CopyOptions.LocalDevice);
              Text('长按书目信息可复制')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'));
              Button(this.isFavorite ? '取消收藏' : '加入收藏')
                .height(44)
                .onClick(() => { this.toggleFavorite(); });
              this.metadataRow('责任者', this.detail.responsibility);
              this.metadataRow('出版', this.detail.publication);
              this.metadataRow('ISBN/ISSN', this.detail.isbn_issn);
              this.metadataRow('中图分类号', this.detail.classification);
              this.metadataRow('载体形态', this.detail.physical_description);
              this.metadataRow('并列题名', this.detail.parallel_title);
              this.metadataRow('价格', this.detail.price);
            }
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16);

            Text(`馆藏 (${this.detail.holdings.length})`)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%');
            if (this.detail.holdings.length === 0) {
              Text('暂无单册馆藏信息')
                .fontColor($r('app.color.text_secondary'))
                .padding(24)
                .width('100%');
            }
            ForEach(this.departments(), (department: string) => {
              Text(department)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%');
              ForEach(this.holdingsIn(department), (holding: Holding, index: number) => {
                this.holdingCard(holding, `${department}-${holding.barcode}-${index}`);
              }, (holding: Holding, index: number) => `${department}-${holding.barcode}-${index}`);
            }, (department: string) => department);
          }
        }
        .padding({ left: 16, right: 16, top: 16, bottom: 56 })
        .width('100%');
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
    }
    .hideTitleBar(true)
    .bindContentCover(this.mapExpanded, this.fullMap())
    .backgroundColor($r('app.color.page_bg'));
  }
}
