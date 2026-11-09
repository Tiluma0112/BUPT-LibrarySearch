import { uiMaterial } from '@kit.ArkUI';
import { displayCount, displayYear } from '../common/Format';
import { BookSummary, Campus, SearchField, SearchQuery } from '../model/Types';
import { OpacService } from '../service/OpacService';
import { BookDetail } from './BookDetail';
import { LibraryLogin } from './LibraryLogin';
import { LibraryPortal } from './LibraryPortal';
import { MyLibrary } from './MyLibrary';
import { BorrowHistoryPage } from './BorrowHistoryPage';
import { LoginSettingsStore } from '../service/LoginSettingsStore';
import { ReaderProfileStore } from '../service/ReaderProfileStore';
import { PortalProfileBridge } from '../service/PortalProfileBridge';
import { LibraryDataService } from '../service/LibraryDataService';
import { BorrowHistory, ReaderProfile } from '../model/PersonalTypes';
import { webview } from '@kit.ArkWeb';
import { OPAC_BASE_URL } from '../common/AppConfig';
import { LIBRARY_LOGIN_URL, PORTAL_BASE_URL, PORTAL_LOGIN_URL } from '../common/AppConfig';

type SortField = 'title' | 'year' | 'available';
type AvailabilityFilter = 'all' | 'available' | 'unavailable';

@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();
  private tabsController: TabsController = new TabsController();
  @State keyword: string = '';
  @State activeTab: number = 0;
  @State tabSwipeProgress: number = 0;
  private tabsWidth: number = 1;
  @State favoritesRefreshVersion: number = 0;
  @State historyForPage: BorrowHistory[] = [];
  @State field: SearchField = 'title';
  @State campus: Campus = 'all';
  @State pageSize: number = 20;
  @State page: number = 1;
  @State total: number = 0;
  @State totalPages: number = 0;
  @State sortField: SortField = 'title';
  @State availabilityFilter: AvailabilityFilter = 'all';
  @State results: BookSummary[] = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State errorText: string = '';
  @State searched: boolean = false;
  private requestVersion: number = 0;
  private autoRenewStarted: boolean = false;
  @State silentRenewal: boolean = false;
  private silentController: webview.WebviewController = new webview.WebviewController();
  private silentPortalStage: boolean = false;
  private silentVerifying: boolean = false;
  private silentChecking: boolean = false;
  private silentGeneration: number = 0;
  private silentPageVersion: number = 0;

  aboutToAppear(): void {
    this.autoRenewSession();
  }

  private async verifySilentPortal(generation: number): Promise<void> {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (_error) {}
    try {
      await LibraryDataService.verifyOpacSession();
    } catch (error) {
      if (!this.silentRenewal || generation !== this.silentGeneration) { return; }
      this.silentChecking = false;
      this.silentRenewal = false;
      if (error instanceof Error && error.message === '认证已失效，请重新登录') {
        LoginSettingsStore.markExpired(getContext(this));
      }
      this.favoritesRefreshVersion++;
      return;
    }
    if (!this.silentRenewal || generation !== this.silentGeneration) { return; }
    const apiProfile = await LibraryDataService.loadPortalProfile();
    const pageProfile = await PortalProfileBridge.read(this.silentController);
    if (!this.silentRenewal || generation !== this.silentGeneration) { return; }
    this.silentChecking = false;
    if (apiProfile || pageProfile) {
      const cached = ReaderProfileStore.load(getContext(this));
      ReaderProfileStore.save(getContext(this), {
        name: pageProfile?.name || apiProfile?.name || cached.name,
        studentId: pageProfile?.studentId || apiProfile?.studentId || cached.studentId,
        avatarUrl: pageProfile?.avatarUrl || apiProfile?.avatarUrl || cached.avatarUrl,
        avatarLocalUri: cached.avatarLocalUri
      });
    }
    this.silentRenewal = false;
    this.favoritesRefreshVersion++;
  }

  onPageShow(): void {
    this.autoRenewSession();
  }

  onPageHide(): void {
    this.autoRenewStarted = false;
  }

  private autoRenewSession(): void {
    if (this.autoRenewStarted || this.silentRenewal || this.pathStack.size() > 0) { return; }
    this.autoRenewStarted = true;
    try {
      if (LoginSettingsStore.isWithinValidPeriod(getContext(this))) {
        this.silentGeneration++;
        this.silentPortalStage = false;
        this.silentVerifying = false;
        this.silentChecking = false;
        this.silentRenewal = true;
        const generation = this.silentGeneration;
        setTimeout(() => {
          if (this.silentRenewal && generation === this.silentGeneration) {
            this.silentRenewal = false;
            this.silentChecking = false;
            this.silentGeneration++;
            this.favoritesRefreshVersion++;
          }
        }, 45000);
      }
    } catch (_error) {}
  }

  private onSilentPageEnd(url: string): void {
    if (!this.silentRenewal) { return; }
    const generation = this.silentGeneration;
    const pageVersion = ++this.silentPageVersion;
    if (url.startsWith('https://auth.bupt.edu.cn/')) {
      setTimeout(() => {
        if (this.silentRenewal && generation === this.silentGeneration &&
          pageVersion === this.silentPageVersion) {
          this.silentRenewal = false;
          LoginSettingsStore.markExpired(getContext(this));
          this.favoritesRefreshVersion++;
        }
      }, 12000);
    } else if (this.silentPortalStage && url.startsWith(PORTAL_BASE_URL) &&
      url.indexOf('/sso/login') < 0) {
      if (!this.silentChecking) {
        this.silentChecking = true;
        this.verifySilentPortal(generation);
      }
    } else if (url.startsWith(`${OPAC_BASE_URL}/reader-setting.html`)) {
      this.silentPortalStage = true;
      this.silentController.loadUrl(PORTAL_LOGIN_URL);
    } else if (this.silentVerifying && url.startsWith(`${OPAC_BASE_URL}/index.html`)) {
      this.silentRenewal = false;
      LoginSettingsStore.markExpired(getContext(this));
      this.favoritesRefreshVersion++;
    } else if (url.startsWith(OPAC_BASE_URL) && url.indexOf('/cas/') < 0 && !this.silentVerifying) {
      this.silentVerifying = true;
      this.silentController.loadUrl(`${OPAC_BASE_URL}/reader-setting.html`);
    }
  }

  private sortedResults(): BookSummary[] {
    const copy = this.results.filter((book: BookSummary): boolean => {
      if (this.availabilityFilter === 'available') { return (book.available_count ?? 0) > 0; }
      if (this.availabilityFilter === 'unavailable') { return (book.available_count ?? 0) === 0; }
      return true;
    });
    if (this.sortField === 'year') {
      return copy.sort((a: BookSummary, b: BookSummary): number =>
        (parseInt(b.publication_year) || 0) - (parseInt(a.publication_year) || 0));
    }
    if (this.sortField === 'available') {
      return copy.sort((a: BookSummary, b: BookSummary): number =>
        (b.available_count ?? -1) - (a.available_count ?? -1));
    }
    return copy.sort((a: BookSummary, b: BookSummary): number => a.title.localeCompare(b.title, 'zh-CN'));
  }

  private async loadPage(nextPage: number): Promise<void> {
    if (!this.keyword.trim()) {
      this.errorText = '请输入检索词';
      this.searched = false;
      this.refreshing = false;
      return;
    }
    const version = ++this.requestVersion;
    this.loading = true;
    this.errorText = '';
    this.searched = true;
    const query: SearchQuery = {
      q: this.keyword, field: this.field, campus: this.campus,
      page: nextPage, page_size: this.pageSize
    };
    try {
      const response = await OpacService.search(query);
      if (version !== this.requestVersion) {
        return;
      }
      this.results = response.items;
      this.page = nextPage;
      this.total = response.total;
      this.totalPages = response.total_pages;
    } catch (error) {
      if (version === this.requestVersion) {
        this.errorText = error instanceof Error ? error.message : '网络请求失败，请重试';
        this.results = [];
      }
    } finally {
      if (version === this.requestVersion) {
        this.loading = false;
        this.refreshing = false;
      }
    }
  }

  private searchHistoryBook(keyword: string, isIsbn: boolean): void {
    const search = (): void => {
      this.keyword = keyword;
      this.field = isIsbn ? 'isbn' : 'title';
      this.campus = 'all';
      this.availabilityFilter = 'all';
      this.tabsController.changeIndex(0);
      this.loadPage(1);
    };
    if (this.pathStack.size() > 0) {
      this.pathStack.pop();
      setTimeout(search, 320);
    } else {
      search();
    }
  }

  private tabStrength(index: number): number {
    return Math.max(0, 1 - Math.abs(this.tabSwipeProgress - index));
  }

  private settleTabProgress(index: number, duration: number): void {
    this.getUIContext()?.animateTo({ duration: duration, curve: Curve.EaseOut }, () => {
      this.tabSwipeProgress = index;
    });
  }

  @Builder
  private floatingTab(label: string, index: number): void {
    Stack() {
      Row()
        .width(104)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.tab_selected_bg'))
        .opacity(this.tabStrength(index))
        .scale({ x: 0.86 + 0.14 * this.tabStrength(index),
          y: 0.86 + 0.14 * this.tabStrength(index) });
      Stack() {
        Text(label)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .opacity(1 - this.tabStrength(index));
        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
          .opacity(this.tabStrength(index));
      }
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height(56);
  }

  @Builder
  private detailDestination(name: string, param: string): void {
    if (name === 'BookDetail') {
      BookDetail({ bookId: param, onClose: () => { this.pathStack.pop(); } });
    } else if (name === 'BorrowHistoryPage') {
      BorrowHistoryPage({
        history: this.historyForPage,
        onClose: () => { this.pathStack.pop(); },
        onSearchBook: (keyword: string, isIsbn: boolean) => {
          this.searchHistoryBook(keyword, isIsbn);
        }
      });
    } else if (name === 'LibraryLogin') {
      LibraryLogin({ onAuthenticated: (profile: ReaderProfile) => {
        if (param !== 'auto') {
          LoginSettingsStore.markAuthenticated(getContext(this));
        }
        ReaderProfileStore.save(getContext(this), profile);
        this.pathStack.pop();
        this.activeTab = 1;
        this.favoritesRefreshVersion++;
      }, onClose: () => { this.pathStack.pop(); } });
    } else if (name === 'LibraryPortal') {
      LibraryPortal({ onClose: () => { this.pathStack.pop(); },
        onProfile: (profile: ReaderProfile) => {
          ReaderProfileStore.save(getContext(this), profile);
          this.favoritesRefreshVersion++;
        } });
    }
  }

  @Builder
  private searchControls(): void {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入书名、作者或 ISBN', text: this.keyword })
          .onChange((value: string) => { this.keyword = value; })
          .onSubmit(() => { this.loadPage(1); })
          .height(48)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_bg'));
        Button('检索')
          .onClick(() => { this.loadPage(1); })
          .height(48)
          .width(72);
      }
      .width('100%');

      Column({ space: 4 }) {
        Text('检索字段').fontColor($r('app.color.text_secondary')).fontSize(13);
        Select([
          { value: '题名' }, { value: '责任者' }, { value: 'ISBN/ISSN' },
          { value: '出版年' }, { value: '出版社' }, { value: '主题词' }
        ])
          .selected(['title', 'author', 'isbn', 'year', 'publisher', 'subject'].indexOf(this.field))
          .value(['题名', '责任者', 'ISBN/ISSN', '出版年', '出版社', '主题词'][
            ['title', 'author', 'isbn', 'year', 'publisher', 'subject'].indexOf(this.field)])
          .onSelect((index: number) => {
            const fields: SearchField[] = ['title', 'author', 'isbn', 'year', 'publisher', 'subject'];
            this.field = fields[index];
          })
          .fontColor($r('app.color.text_primary'))
          .optionFontColor($r('app.color.text_primary'))
          .selectedOptionFontColor($r('app.color.accent'))
          .menuBackgroundColor($r('app.color.card_bg'))
          .backgroundColor($r('app.color.card_bg'))
          .systemMaterial(uiMaterial.Material.empty)
          .menuSystemMaterial(uiMaterial.Material.empty)
          .height(44)
          .width('100%');
      }
      .width('100%');

      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text('校区位置').fontColor($r('app.color.text_secondary')).fontSize(13);
          Select([{ value: '全部校区' }, { value: '本部' }, { value: '宏福' }, { value: '沙河' }])
            .selected(['all', 'main', 'hongfu', 'shahe'].indexOf(this.campus))
            .value(['全部校区', '本部', '宏福', '沙河'][['all', 'main', 'hongfu', 'shahe'].indexOf(this.campus)])
            .onSelect((index: number) => {
              const campuses: Campus[] = ['all', 'main', 'hongfu', 'shahe'];
              this.campus = campuses[index];
              if (this.searched) { this.loadPage(1); }
            })
            .fontColor($r('app.color.text_primary'))
            .optionFontColor($r('app.color.text_primary'))
            .selectedOptionFontColor($r('app.color.accent'))
            .menuBackgroundColor($r('app.color.card_bg'))
            .backgroundColor($r('app.color.card_bg'))
            .systemMaterial(uiMaterial.Material.empty)
            .menuSystemMaterial(uiMaterial.Material.empty)
            .height(44)
            .width('100%');
        }
        .layoutWeight(1);
        Column({ space: 4 }) {
          Text('每页条数').fontColor($r('app.color.text_secondary')).fontSize(13);
          Select([{ value: '10 条' }, { value: '20 条' }, { value: '50 条' }])
            .selected([10, 20, 50].indexOf(this.pageSize))
            .value(`${this.pageSize} 条`)
            .onSelect((index: number) => {
              this.pageSize = [10, 20, 50][index];
              if (this.searched) { this.loadPage(1); }
            })
            .fontColor($r('app.color.text_primary'))
            .optionFontColor($r('app.color.text_primary'))
            .selectedOptionFontColor($r('app.color.accent'))
            .menuBackgroundColor($r('app.color.card_bg'))
            .backgroundColor($r('app.color.card_bg'))
            .systemMaterial(uiMaterial.Material.empty)
            .menuSystemMaterial(uiMaterial.Material.empty)
            .height(44)
            .width('100%');
        }
        .layoutWeight(1);
      }
      .width('100%');

      if (this.searched) {
        Row() {
          Text(`共 ${this.total} 条 · 第 ${this.page} 页`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1);
          Text('排序').fontColor($r('app.color.text_secondary')).fontSize(13);
          Select([{ value: '题名' }, { value: '出版年' }, { value: '可借数量' }])
            .selected(['title', 'year', 'available'].indexOf(this.sortField))
            .value(['题名', '出版年', '可借数量'][['title', 'year', 'available'].indexOf(this.sortField)])
            .onSelect((index: number) => {
              const fields: SortField[] = ['title', 'year', 'available'];
              this.sortField = fields[index];
            })
            .fontColor($r('app.color.text_primary'))
            .optionFontColor($r('app.color.text_primary'))
            .menuBackgroundColor($r('app.color.card_bg'))
            .backgroundColor($r('app.color.card_bg'))
            .systemMaterial(uiMaterial.Material.empty)
            .menuSystemMaterial(uiMaterial.Material.empty)
            .height(44);
        }
        .width('100%');
        Row({ space: 8 }) {
          Text('可借状态').fontColor($r('app.color.text_secondary')).fontSize(13);
          Select([{ value: '全部' }, { value: '有可借馆藏' }, { value: '暂无可借' }])
            .selected(['all', 'available', 'unavailable'].indexOf(this.availabilityFilter))
            .value(['全部', '有可借馆藏', '暂无可借'][
              ['all', 'available', 'unavailable'].indexOf(this.availabilityFilter)])
            .onSelect((index: number) => {
              const filters: AvailabilityFilter[] = ['all', 'available', 'unavailable'];
              this.availabilityFilter = filters[index];
            })
            .fontColor($r('app.color.text_primary'))
            .optionFontColor($r('app.color.text_primary'))
            .menuBackgroundColor($r('app.color.card_bg'))
            .backgroundColor($r('app.color.card_bg'))
            .systemMaterial(uiMaterial.Material.empty)
            .menuSystemMaterial(uiMaterial.Material.empty)
            .height(44)
            .layoutWeight(1);
        }
        .width('100%');
        Text('可借状态按检索结果的可借数量筛选当前页')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%');
      }
    }
    .padding({ left: 16, right: 16, top: 28, bottom: 10 })
    .width('100%');
  }

  @Builder
  private bookCard(book: BookSummary): void {
    Column({ space: 6 }) {
      Text(book.title || '无题名')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text(book.authors || '作者未知')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1);
      Text(`${book.publisher || '出版社未知'} · ${displayYear(book.publication_year)}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1);
      Text(`索书号 ${book.call_number || '暂无'}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .width('100%');
      Row({ space: 12 }) {
        Text(`馆藏 ${displayCount(book.holdings_count)}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'));
        Text(`可借 ${displayCount(book.available_count)}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'));
      }
      .width('100%');
      Row({ space: 4 }) {
        Blank().layoutWeight(1);
        Text('查看馆藏详情')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'));
        SymbolGlyph($r('sys.symbol.chevron_forward'))
          .fontSize(18)
          .fontColor([$r('app.color.accent')]);
      }
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .constraintSize({ minHeight: 112 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .onClick(() => { this.pathStack.pushPathByName('BookDetail', book.id); })
  }

  build(): void {
    Stack() {
      Navigation(this.pathStack) {
      Tabs({ barPosition: BarPosition.End, index: this.activeTab, controller: this.tabsController }) {
        TabContent() {
          Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 10 }) {
          ListItem() { this.searchControls(); }

          if (this.loading && !this.refreshing) {
            ListItem() {
              Row({ space: 10 }) {
                LoadingProgress().width(24).height(24);
                Text('正在检索…').fontColor($r('app.color.text_secondary'));
              }
              .padding(24)
              .width('100%')
              .justifyContent(FlexAlign.Center);
            }
          } else if (this.errorText) {
            ListItem() {
              Column({ space: 12 }) {
                Text(this.errorText).fontColor($r('app.color.text_primary'));
                Button('重试').height(44).onClick(() => { this.loadPage(this.page); });
              }
              .padding(28)
              .width('100%');
            }
          } else if (!this.searched || this.sortedResults().length === 0) {
            ListItem() {
              Text(this.searched ? (this.results.length > 0 ? '当前页没有符合筛选条件的书目' :
                '没有找到相关书目，试试其他关键词') : '输入关键词，开始检索北邮图书馆馆藏')
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
                .padding(32)
                .width('100%');
            }
          } else {
            ForEach(this.sortedResults(), (book: BookSummary) => {
              ListItem() { this.bookCard(book); }
                .padding({ left: 16, right: 16 });
            }, (book: BookSummary) => book.id);
            ListItem() {
              Row({ space: 16 }) {
                Button('上一页')
                  .enabled(this.page > 1)
                  .height(44)
                  .onClick(() => { this.loadPage(this.page - 1); });
                Text(`${this.page} / ${this.totalPages}`)
                  .fontColor($r('app.color.text_secondary'));
                Button('下一页')
                  .enabled(this.page < this.totalPages)
                  .height(44)
                  .onClick(() => { this.loadPage(this.page + 1); });
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 10, bottom: 10 });
            }
          }
          ListItem() { Text('').height(104); }
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .backgroundColor($r('app.color.page_bg'))
        .clipContent(ContentClipMode.SAFE_AREA)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
          }
          .onRefreshing(() => {
            this.refreshing = true;
            this.loadPage(this.page);
          })
          .width('100%')
          .height('100%');
        }
        .tabBar(this.floatingTab('检索', 0));
        TabContent() {
          MyLibrary({
            renewalInProgress: this.silentRenewal,
            onLogin: () => {
              this.silentRenewal = false;
              this.pathStack.pushPathByName('LibraryLogin', 'manual');
            },
            onOpenPortal: () => { this.pathStack.pushPathByName('LibraryPortal', ''); },
            onOpenBook: (id: string) => { this.pathStack.pushPathByName('BookDetail', id); },
            onSearchBook: (keyword: string, isIsbn: boolean) => {
              this.searchHistoryBook(keyword, isIsbn);
            },
            onOpenHistory: (history: BorrowHistory[]) => {
              this.historyForPage = history;
              this.pathStack.pushPathByName('BorrowHistoryPage', '');
            },
            refreshVersion: this.favoritesRefreshVersion
          });
        }
        .tabBar(this.floatingTab('我的', 1));
      }
      .onChange((index: number) => {
        this.activeTab = index;
        this.tabSwipeProgress = index;
        if (index === 1) { this.favoritesRefreshVersion++; }
      })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const width = Number(newValue.width);
        if (width > 0) { this.tabsWidth = width; }
      })
      .animationDuration(280)
      .animationCurve(Curve.EaseOut)
      .onAnimationStart((index: number, targetIndex: number, event: TabsAnimationEvent) => {
        this.settleTabProgress(targetIndex, 280);
      })
      .onAnimationEnd((index: number, event: TabsAnimationEvent) => {
        this.tabSwipeProgress = index;
      })
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        this.tabSwipeProgress = Math.max(0, Math.min(1,
          index - event.currentOffset / this.tabsWidth));
      })
      .scrollable(true)
      .barHeight(56)
      .barOverlap(true)
      .barFloatingStyle({
        barWidth: { smallBarWidth: 232, mediumBarWidth: 280, largeBarWidth: 320 },
        barSideMargin: 16,
        barBottomMargin: 12,
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          applyShadow: true,
          interactive: true,
          lightEffect: { color: $r('app.color.accent') }
        })
      })
      .width('100%')
      .height('100%');
    }
    .navDestination(this.detailDestination)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
      .backgroundColor($r('app.color.page_bg'));
      if (this.silentRenewal) {
        Web({ src: LIBRARY_LOGIN_URL, controller: this.silentController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageEnd((event: OnPageEndEvent) => { this.onSilentPageEnd(event.url); })
          .width(1)
          .height(1)
          .opacity(0);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'));
  }
}
