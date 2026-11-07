import { BorrowCycle, BorrowHistory } from '../model/PersonalTypes';
import { BorrowHistoryCard } from '../components/BorrowHistoryCard';

@Component
export struct BorrowHistoryPage {
  @Prop history: BorrowHistory[];
  onClose: () => void = () => {};
  onSearchBook: (keyword: string, isIsbn: boolean) => void = (_keyword: string, _isIsbn: boolean) => {};
  @State keyword: string = '';
  @State dateFrom: string = '';
  @State dateTo: string = '';

  private dateError(): string {
    const from = this.dateFrom.trim();
    const to = this.dateTo.trim();
    if ((from && !/^\d{4}-\d{2}-\d{2}$/.test(from)) ||
      (to && !/^\d{4}-\d{2}-\d{2}$/.test(to))) {
      return '日期请输入 YYYY-MM-DD 格式';
    }
    if (from && to && from > to) { return '起始日期不能晚于结束日期'; }
    return '';
  }

  private filteredHistory(): BorrowHistory[] {
    if (this.dateError()) { return []; }
    const keyword = this.keyword.trim().toLowerCase();
    const from = this.dateFrom.trim();
    const to = this.dateTo.trim();
    return this.history.filter((book: BorrowHistory): boolean => {
      const searchable = `${book.title} ${book.authors} ${book.isbn} ` +
        book.cycles.map((cycle: BorrowCycle): string => cycle.barcode).join(' ');
      if (keyword && !searchable.toLowerCase().includes(keyword)) { return false; }
      if (!from && !to) { return true; }
      const inRange = (value: string): boolean => {
        const day = value.slice(0, 10);
        return !!day && (!from || day >= from) && (!to || day <= to);
      };
      return book.cycles.some((cycle: BorrowCycle): boolean =>
        inRange(cycle.borrowedAt) || inRange(cycle.returnedAt)) ||
        book.otherEvents.some((event: string): boolean => inRange(event));
    });
  }

  @Builder
  private filters(): void {
    Column({ space: 10 }) {
      TextInput({ placeholder: '搜索书名、作者、ISBN 或条码', text: this.keyword })
        .onChange((value: string) => { this.keyword = value; })
        .height(48)
        .width('100%')
        .backgroundColor($r('app.color.card_bg'));
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text('起始日期').fontSize(12).fontColor($r('app.color.text_secondary'));
          TextInput({ placeholder: 'YYYY-MM-DD', text: this.dateFrom })
            .onChange((value: string) => { this.dateFrom = value; })
            .height(44)
            .width('100%')
            .backgroundColor($r('app.color.card_bg'));
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Column({ space: 4 }) {
          Text('结束日期').fontSize(12).fontColor($r('app.color.text_secondary'));
          TextInput({ placeholder: 'YYYY-MM-DD', text: this.dateTo })
            .onChange((value: string) => { this.dateTo = value; })
            .height(44)
            .width('100%')
            .backgroundColor($r('app.color.card_bg'));
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%');
      if (this.dateError()) {
        Text(this.dateError())
          .fontSize(12)
          .fontColor($r('app.color.accent'));
      }
      Row() {
        Text(`共 ${this.filteredHistory().length} 本`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1);
        if (this.keyword || this.dateFrom || this.dateTo) {
          Button('清除筛选')
            .height(44)
            .onClick(() => {
              this.keyword = '';
              this.dateFrom = '';
              this.dateTo = '';
            });
        }
      }
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .width('100%');
  }

  build(): void {
    NavDestination() {
      List({ space: 12 }) {
        ListItem() {
          Button('返回')
            .height(44)
            .margin({ left: 16, top: 12 })
            .onClick(() => { this.onClose(); });
        }
        ListItem() { this.filters(); }
        if (this.filteredHistory().length === 0) {
          ListItem() {
            Text(this.dateError() ? '请修正日期后查看借阅历史' : '没有符合条件的借阅历史')
              .fontColor($r('app.color.text_secondary'))
              .padding(20)
              .width('100%');
          }
        }
        ForEach(this.filteredHistory(), (item: BorrowHistory) => {
          ListItem() {
            BorrowHistoryCard({ item: item, onSearchBook: this.onSearchBook });
          }
          .padding({ left: 16, right: 16 });
        }, (item: BorrowHistory): string => item.id);
        ListItem() { Text('').height(72); }
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_bg'));
  }
}
