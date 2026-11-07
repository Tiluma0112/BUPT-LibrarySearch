import { FavoriteBook } from '../model/FavoriteBook';
import { FavoritesStore } from '../service/FavoritesStore';
import { LoginSettingsStore } from '../service/LoginSettingsStore';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { GITHUB_REPO_URL, OPAC_BASE_URL, PORTAL_MY_LIBRARY_URL } from '../common/AppConfig';
import { uiMaterial } from '@kit.ArkUI';
import { LibraryDataService } from '../service/LibraryDataService';
import { ReaderProfileStore } from '../service/ReaderProfileStore';
import { PortalProfileBridge } from '../service/PortalProfileBridge';
import { BorrowHistory, CurrentLoan, ReaderProfile } from '../model/PersonalTypes';
import { BorrowHistoryCard } from '../components/BorrowHistoryCard';

@Component
export struct MyLibrary {
  onLogin: () => void = () => {};
  onOpenPortal: () => void = () => {};
  onOpenBook: (id: string) => void = (_id: string) => {};
  onSearchBook: (keyword: string, isIsbn: boolean) => void = (_keyword: string, _isIsbn: boolean) => {};
  onOpenHistory: (history: BorrowHistory[]) => void = (_history: BorrowHistory[]) => {};
  @Prop @Watch('reloadFavorites') refreshVersion: number = 0;
  @State favorites: FavoriteBook[] = [];
  @State loginDays: number = 7;
  @State sessionPresent: boolean = false;
  @State sessionExpired: boolean = false;
  @State profile: ReaderProfile = { name: '', studentId: '', avatarUrl: '', avatarLocalUri: '' };
  @State loans: CurrentLoan[] = [];
  @State history: BorrowHistory[] = [];
  @State personalLoading: boolean = false;
  @State refreshing: boolean = false;
  @State personalError: string = '';
  private personalRequestVersion: number = 0;
  private profileGeneration: number = 0;
  private profileController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.reloadFavorites();
  }

  private reloadFavorites(): void {
    this.favorites = FavoritesStore.list(getContext(this));
    this.loginDays = LoginSettingsStore.days(getContext(this));
    this.profile = ReaderProfileStore.load(getContext(this));
    this.sessionExpired = LoginSettingsStore.isExpired(getContext(this));
    try {
      this.sessionPresent = LoginSettingsStore.isWithinValidPeriod(getContext(this)) &&
        !!webview.WebCookieManager.fetchCookieSync(OPAC_BASE_URL, false, true);
    } catch (_error) {
      this.sessionPresent = false;
    }
    if (this.sessionPresent) {
      this.loadPersonalData();
      this.syncProfileFromApi();
    }
  }

  private async syncProfileFromApi(): Promise<void> {
    const generation = this.profileGeneration;
    const profile = await LibraryDataService.loadPortalProfile();
    if (!profile || generation !== this.profileGeneration || !this.sessionPresent) { return; }
    profile.studentId = profile.studentId || this.profile.studentId;
    profile.avatarUrl = profile.avatarUrl || this.profile.avatarUrl;
    profile.avatarLocalUri = profile.avatarUrl ?
      await ReaderProfileStore.cacheAvatar(getContext(this), profile.avatarUrl) : this.profile.avatarLocalUri;
    if (generation !== this.profileGeneration || !this.sessionPresent) { return; }
    this.profile = profile;
    ReaderProfileStore.save(getContext(this), profile);
  }

  private async syncProfileFromPage(): Promise<void> {
    const generation = this.profileGeneration;
    const profile = await PortalProfileBridge.read(this.profileController);
    if (!profile || generation !== this.profileGeneration || !this.sessionPresent) { return; }
    if (this.profile.name === profile.name && this.profile.studentId === profile.studentId &&
      this.profile.avatarUrl === profile.avatarUrl && this.profile.avatarLocalUri) { return; }
    profile.name = profile.name || this.profile.name;
    profile.studentId = profile.studentId || this.profile.studentId;
    profile.avatarUrl = profile.avatarUrl || this.profile.avatarUrl;
    profile.avatarLocalUri = profile.avatarUrl ?
      await ReaderProfileStore.cacheAvatar(getContext(this), profile.avatarUrl) : this.profile.avatarLocalUri;
    if (generation !== this.profileGeneration || !this.sessionPresent) { return; }
    this.profile = profile;
    ReaderProfileStore.save(getContext(this), profile);
  }

  private async loadPersonalData(): Promise<void> {
    const version = ++this.personalRequestVersion;
    this.personalLoading = true;
    this.personalError = '';
    try {
      const snapshot = await LibraryDataService.loadSnapshot();
      if (version !== this.personalRequestVersion) { return; }
      this.loans = snapshot.currentLoans;
      this.history = snapshot.history;
    } catch (error) {
      if (version !== this.personalRequestVersion) { return; }
      this.personalError = error instanceof Error ? error.message : '个人数据加载失败，请重试';
      if (this.personalError === '认证已失效，请重新登录') {
        LoginSettingsStore.markExpired(getContext(this));
        this.sessionPresent = false;
        this.sessionExpired = true;
        this.loans = [];
        this.history = [];
      }
    } finally {
      if (version === this.personalRequestVersion) {
        this.personalLoading = false;
        this.refreshing = false;
      }
    }
  }

  private signOut(): void {
    this.personalRequestVersion++;
    this.profileGeneration++;
    LoginSettingsStore.clear(getContext(this));
    webview.WebCookieManager.clearAllCookiesSync();
    ReaderProfileStore.clear(getContext(this));
    this.sessionPresent = false;
    this.sessionExpired = false;
    this.profile = { name: '', studentId: '', avatarUrl: '', avatarLocalUri: '' };
    this.loans = [];
    this.history = [];
    this.personalError = '';
    this.personalLoading = false;
    this.refreshing = false;
  }

  // 打开 GitHub 项目主页
  private async openGithub(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: GITHUB_REPO_URL
      });
    } catch (_error) {
      // 打开浏览器失败时静默忽略，不影响页面其它功能
    }
  }

  @Builder
  private sectionTitle(title: string): void {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%');
  }

  build(): void {
    Stack() {
    Refresh({ refreshing: $$this.refreshing }) {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          if (this.profile.avatarLocalUri || this.profile.avatarUrl) {
            Image(this.profile.avatarLocalUri || this.profile.avatarUrl)
              .width(56)
              .height(56)
              .borderRadius(28)
              .objectFit(ImageFit.Cover);
          } else {
            Text('👤')
              .fontSize(28)
              .textAlign(TextAlign.Center)
              .width(56)
              .height(56)
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(28);
          }
          Column({ space: 5 }) {
            Text(this.profile.name || '个人信息')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'));
            Text(this.profile.studentId ? `学工号 ${this.profile.studentId}` :
              (this.sessionPresent ? '个人资料待同步' :
                (this.sessionExpired ? '认证已失效，请重新登录' : '登录后查看个人信息')))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'));
            Text('查看图书馆网页  ›')
              .fontSize(13)
              .fontColor($r('app.color.accent'));
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .padding(16)
        .width('100%')
        .constraintSize({ minHeight: 88 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(16)
        .onClick(() => { this.onOpenPortal(); });

        if (!this.sessionPresent) {
          Button(this.sessionExpired ? '认证已失效，请重新登录' : '北邮统一身份认证登录')
            .height(48)
            .width('100%')
            .onClick(() => { this.onLogin(); });
        }

        if (this.personalLoading) {
          Row({ space: 8 }) {
            LoadingProgress().width(20).height(20);
            Text('正在同步借阅数据…').fontColor($r('app.color.text_secondary'));
          }
          .width('100%');
        }
        if (this.personalError && this.sessionPresent) {
          Row({ space: 8 }) {
            Text(this.personalError)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1);
            Button('重试')
              .height(44)
              .onClick(() => { this.loadPersonalData(); });
          }
          .padding(12)
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12);
        }

        this.sectionTitle('当前借阅');
        if (this.loans.length === 0 && !this.personalLoading) {
          Text(this.sessionPresent ? (this.personalError ? '借阅数据加载失败' :
            '接口暂未返回当前借阅，可点击上方卡片查看网页') :
            '登录后查看当前借阅')
            .fontColor($r('app.color.text_secondary'))
            .padding(20)
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16);
        }
        ForEach(this.loans, (loan: CurrentLoan, index: number) => {
          Column({ space: 7 }) {
            Text(loan.title)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'));
            Text(`${loan.department} · ${loan.callNumber}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'));
            Text(`条码 ${loan.barcode} · ${loan.status}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'));
            Text(loan.dueDate ? `预计归还 ${loan.dueDate}${loan.overdue ? ' · 已逾期' : ''}` : '应还日期待更新')
              .fontSize(14)
              .fontColor($r('app.color.accent'));
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16);
        }, (loan: CurrentLoan, index: number): string => `${loan.id}-${index}`);

        this.sectionTitle('借阅历史');
        if (this.history.length === 0 && !this.personalLoading) {
          Text(this.sessionPresent ? (this.personalError ? '借阅历史加载失败' :
            '接口暂未返回借阅历史，可点击上方卡片查看网页') :
            '登录后查看借阅历史')
            .fontColor($r('app.color.text_secondary'))
            .padding(20)
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16);
        }
        ForEach(this.history.slice(0, 3), (item: BorrowHistory) => {
          BorrowHistoryCard({ item: item, onSearchBook: this.onSearchBook });
        }, (item: BorrowHistory): string => item.id);
        if (this.history.length > 3) {
          Button(`查看全部借阅历史（${this.history.length} 本）`)
            .height(44)
            .width('100%')
            .onClick(() => { this.onOpenHistory(this.history); });
        }

        this.sectionTitle(`本地收藏 (${this.favorites.length})`);
        if (this.favorites.length === 0) {
          Text('在书目详情页可添加收藏')
            .fontColor($r('app.color.text_secondary'))
            .padding(20)
            .width('100%')
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(16);
        }
        ForEach(this.favorites, (book: FavoriteBook) => {
          Row({ space: 10 }) {
            Column({ space: 6 }) {
              Text(book.title)
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .maxLines(2);
              Text(book.responsibility || book.publication)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'));
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            Button('详情')
              .height(44)
              .onClick(() => { this.onOpenBook(book.id); });
          }
          .padding(16)
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(16);
        }, (book: FavoriteBook) => book.id);

        this.sectionTitle('关于与登录管理');
        Text('自动续登有效期')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%');
        Select([{ value: '1 天' }, { value: '7 天' }, { value: '30 天' }])
          .selected([1, 7, 30].indexOf(this.loginDays))
          .value(`${this.loginDays} 天`)
          .onSelect((index: number) => {
            this.loginDays = [1, 7, 30][index];
            LoginSettingsStore.setDays(getContext(this), this.loginDays);
            this.reloadFavorites();
          })
          .fontColor($r('app.color.text_primary'))
          .optionFontColor($r('app.color.text_primary'))
          .menuBackgroundColor($r('app.color.card_bg'))
          .backgroundColor($r('app.color.card_bg'))
          .systemMaterial(uiMaterial.Material.empty)
          .menuSystemMaterial(uiMaterial.Material.empty)
          .height(44)
          .width('100%');
        if (this.sessionPresent) {
          Button('退出登录')
            .height(44)
            .onClick(() => { this.signOut(); });
        }
        Text('北邮图书馆 OPAC 客户端 · 公开书目与本地收藏')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%');
        Text('本App开发与北京邮电大学官方无关，接口来自于公开文档与图书馆网页，仅供交流与学习使用。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%');
        Text('GitHub 项目主页')
          .fontSize(13)
          .fontColor($r('app.color.accent'))
          .textAlign(TextAlign.Center)
          .decoration({ type: TextDecorationType.Underline, color: $r('app.color.accent') })
          .width('100%')
          .onClick(() => { this.openGithub(); });

      }
      .padding({ left: 16, right: 16, top: 24, bottom: 112 })
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.page_bg'));
    }
    .onRefreshing(() => {
      if (this.sessionPresent && !this.personalLoading) {
        this.refreshing = true;
        this.loadPersonalData();
        this.syncProfileFromApi();
      } else {
        this.refreshing = false;
      }
    })
    .width('100%')
    .height('100%');
    if (this.sessionPresent) {
      Web({ src: PORTAL_MY_LIBRARY_URL, controller: this.profileController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onPageEnd(() => { this.syncProfileFromPage(); })
        .width(1)
        .height(1)
        .opacity(0);
    }
    }
    .width('100%')
    .height('100%');
  }
}
