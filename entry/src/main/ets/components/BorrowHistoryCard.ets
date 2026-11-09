import { BorrowCycle, BorrowHistory } from '../model/PersonalTypes';

@Component
export struct BorrowHistoryCard {
  @Prop item: BorrowHistory;
  onSearchBook: (keyword: string, isIsbn: boolean) => void = (_keyword: string, _isIsbn: boolean) => {};

  build(): void {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
        Text(this.item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1);
        Text(this.item.status)
          .fontSize(13)
          .fontColor($r('app.color.accent'));
      }
      .width('100%');
      if (this.item.authors || this.item.publication) {
        Text([this.item.authors, this.item.publication]
          .filter((value: string): boolean => value.length > 0).join(' · '))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'));
      }
      ForEach(this.item.cycles, (cycle: BorrowCycle) => {
        Column({ space: 4 }) {
          if (cycle.barcode) {
            Text(`馆藏条码 ${cycle.barcode}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'));
          }
          Text(`借书时间 ${cycle.borrowedAt || '无记录'}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'));
          Text(`还书时间 ${cycle.returnedAt || '无记录'}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'));
          Text(`${cycle.status}${cycle.renewalCount > 0 ? ` · 续借 ${cycle.renewalCount} 次` : ''}`)
            .fontSize(13)
            .fontColor($r('app.color.accent'));
        }
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .width('100%')
        .backgroundColor($r('app.color.page_bg'))
        .borderRadius(10);
      }, (cycle: BorrowCycle): string => cycle.id);
      ForEach(this.item.otherEvents, (event: string, index: number) => {
        Text(event)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'));
      }, (event: string, index: number): string => `${this.item.id}-event-${index}`);
      Row() {
        Blank().layoutWeight(1);
        Button('检索此书')
          .height(44)
          .onClick(() => {
            const identifier = this.item.isbn.trim();
            this.onSearchBook(identifier || this.item.title, !!identifier);
          });
      }
      .width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16);
  }
}
