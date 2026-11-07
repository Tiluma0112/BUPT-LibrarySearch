import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { OPAC_BASE_URL, PORTAL_BASE_URL, PORTAL_MY_LIBRARY_URL } from '../common/AppConfig';
import { formatLibraryDateTime } from '../common/Format';
import { BorrowCycle, BorrowHistory, CurrentLoan, PersonalLibrarySnapshot, ReaderProfile } from '../model/PersonalTypes';

interface PrivateResult {
  code?: number;
  msg?: string;
}

interface PrivateListResponse<T> {
  result?: PrivateResult;
  data?: T[];
  pageNo?: number;
  totalPage?: number;
  total?: number;
}

interface RawCurrentLoan {
  recCtrlId?: string;
  title?: string;
  bookBarcode?: string;
  bookSearchNo?: string;
  depName?: string;
  statusDesc?: string;
  mydate?: string;
  guoqi?: number;
}

interface RawHistory {
  recCtrlId?: string;
  bookBarcode?: string;
  isn?: string;
  title?: string;
  authors?: string;
  pubdateDate?: string;
  publisher?: string;
  operateDate?: string;
  operateCode?: string | number;
}

interface DatedHistoryEvent {
  raw: RawHistory;
  index: number;
  at: string;
}

interface RawPortalUser {
  uid?: string | number | null;
  realname?: string;
  studentId?: string;
  studentNo?: string;
  userNo?: string;
  uname?: string;
}

interface RawPortalUserResponse {
  code?: number;
  data?: RawPortalUser;
}

export class LibraryDataService {
  private static operationText(code?: string | number): string {
    const value = String(code ?? '').trim();
    if (!value) { return ''; }
    switch (value) {
      case '1': return '借书';
      case '2': return '还书';
      case '3': return '续借';
      case '4': return '预约';
      case '5': return '预约解除';
      case 'A': return '预借借出';
    }
    return /^[0-9A-Z]+$/.test(value) ? `操作代码 ${value}` : value;
  }

  static async loadPortalProfile(): Promise<ReaderProfile | null> {
    const connection = http.createHttp();
    try {
      const cookie = webview.WebCookieManager.fetchCookieSync(PORTAL_BASE_URL, false, true);
      if (!cookie) { return null; }
      const response = await connection.request(`${PORTAL_BASE_URL}/engine2/header/user-info`, {
        method: http.RequestMethod.GET,
        header: { 'Cookie': cookie, 'Referer': PORTAL_MY_LIBRARY_URL,
          'Accept': 'application/json' },
        connectTimeout: 6000,
        readTimeout: 10000
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') { return null; }
      const parsed = JSON.parse(response.result) as RawPortalUserResponse;
      const user = parsed.data;
      console.info(`Portal profile: HTTP ${response.responseCode}, code ${parsed.code ?? 'missing'}, ` +
        `name ${!!user?.realname}, uid ${!!user?.uid}, ` +
        `student ID ${!!(user?.uname || user?.studentId || user?.studentNo || user?.userNo)}`);
      if (parsed.code !== 1 || !user?.realname) { return null; }
      const uid = user.uid ? String(user.uid) : '';
      return {
        name: user.realname,
        studentId: user.uname || user.studentId || user.studentNo || user.userNo || '',
        avatarUrl: uid ? `https://libadmin.bupt.edu.cn/photo/p/${encodeURIComponent(uid)}_80` : '',
        avatarLocalUri: ''
      };
    } catch (_error) {
      return null;
    } finally {
      connection.destroy();
    }
  }

  private static async requestList<T>(path: string, referer: string,
    form: string): Promise<PrivateListResponse<T>> {
    const cookie = webview.WebCookieManager.fetchCookieSync(OPAC_BASE_URL, false, true);
    if (!cookie) { throw new Error('认证已失效，请重新登录'); }
    const connection = http.createHttp();
    try {
      const response = await connection.request(`${OPAC_BASE_URL}/${path}`, {
        method: http.RequestMethod.POST,
        header: { 'Cookie': cookie, 'Referer': `${OPAC_BASE_URL}/${referer}`,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
        extraData: form,
        connectTimeout: 6000,
        readTimeout: 10000
      });
      const body = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode === 401 || response.responseCode === 403 ||
        body.trim().startsWith('<')) {
        throw new Error('认证已失效，请重新登录');
      }
      if (response.responseCode !== 200) { throw new Error('图书馆请求失败，请稍后重试'); }
      const parsed = JSON.parse(body) as PrivateListResponse<T>;
      console.info(`OPAC ${path}: HTTP ${response.responseCode}, result ${parsed.result?.code ?? 'missing'}, ` +
        `records ${Array.isArray(parsed.data) ? parsed.data.length : 'missing'}, ` +
        `total ${parsed.total ?? 'missing'}, pages ${parsed.totalPage ?? 'missing'}`);
      if (parsed.result?.code !== 0) {
        throw new Error('认证已失效，请重新登录');
      }
      return parsed;
    } finally {
      connection.destroy();
    }
  }

  private static async requestPages<T>(path: string, referer: string,
    extra: string = '', pageSize: number = 50): Promise<T[]> {
    const form = (page: number): string =>
      `pageNo=${page}&pageSize=${pageSize}${extra}`;
    const first = await LibraryDataService.requestList<T>(path, referer, form(1));
    if (!Array.isArray(first.data)) { throw new Error('借阅接口返回格式不正确'); }
    const totalPages = first.totalPage ?? Math.ceil((first.total ?? first.data.length) / pageSize);
    if (totalPages > 40) { throw new Error('借阅记录过多，请在图书馆网页查看完整历史'); }
    const records: T[] = [...first.data];
    for (let page = 2; page <= totalPages; page++) {
      const response = await LibraryDataService.requestList<T>(path, referer, form(page));
      if (!Array.isArray(response.data)) { throw new Error('借阅接口返回格式不正确'); }
      records.push(...response.data);
    }
    return records;
  }

  private static groupHistory(records: RawHistory[], current: RawCurrentLoan[]): BorrowHistory[] {
    const events: DatedHistoryEvent[] = records.map((raw: RawHistory, index: number): DatedHistoryEvent => ({
      raw: raw, index: index, at: formatLibraryDateTime(raw.operateDate)
    }));
    const order = (code?: string | number): number => {
      const value = String(code ?? '');
      if (value === '1' || value === 'A') { return 0; }
      if (value === '2') { return 2; }
      return 1;
    };
    events.sort((a: DatedHistoryEvent, b: DatedHistoryEvent): number => {
      const timeOrder = a.at.localeCompare(b.at);
      if (timeOrder !== 0) { return timeOrder; }
      return order(a.raw.operateCode) - order(b.raw.operateCode) || a.index - b.index;
    });

    const books = new Map<string, BorrowHistory>();
    const openByItem = new Map<string, BorrowCycle[]>();
    events.forEach((event: DatedHistoryEvent) => {
      const raw = event.raw;
      const bookKey = raw.recCtrlId || raw.isn || `${raw.title || ''}|${raw.authors || ''}`;
      let book = books.get(bookKey);
      if (!book) {
        book = {
          id: bookKey, title: raw.title || '未命名图书', isbn: raw.isn || '', authors: raw.authors || '',
          publication: [raw.publisher || '', raw.pubdateDate || ''].filter((value: string): boolean =>
            value.length > 0).join(' · '),
          status: '', latestAt: event.at, cycles: [], otherEvents: []
        };
        books.set(bookKey, book);
      }
      if (event.at > book.latestAt) { book.latestAt = event.at; }
      const itemKey = `${bookKey}|${raw.bookBarcode || ''}`;
      const open = openByItem.get(itemKey) || [];
      const code = String(raw.operateCode ?? '');
      if (code === '1' || code === 'A') {
        const cycle: BorrowCycle = {
          id: `${bookKey}-${event.index}`, barcode: raw.bookBarcode || '',
          borrowedAt: event.at, returnedAt: '', renewalCount: 0, status: ''
        };
        book.cycles.push(cycle);
        open.push(cycle);
        openByItem.set(itemKey, open);
      } else if (code === '2') {
        const cycle = open.pop();
        if (cycle) {
          cycle.returnedAt = event.at;
        } else {
          book.cycles.push({
            id: `${bookKey}-${event.index}`, barcode: raw.bookBarcode || '',
            borrowedAt: '', returnedAt: event.at, renewalCount: 0, status: ''
          });
        }
      } else if (code === '3' && open.length > 0) {
        open[open.length - 1].renewalCount++;
      } else {
        book.otherEvents.push(`${event.at || '时间未知'} · ${LibraryDataService.operationText(raw.operateCode)}`);
      }
    });

    const activeBarcodes = new Set<string>(current.map((loan: RawCurrentLoan): string =>
      loan.bookBarcode || '').filter((barcode: string): boolean => !!barcode));
    const activeBookIds = new Set<string>(current.map((loan: RawCurrentLoan): string =>
      loan.recCtrlId || '').filter((id: string): boolean => !!id));
    const grouped = Array.from(books.values());
    grouped.forEach((book: BorrowHistory) => {
      book.cycles.forEach((cycle: BorrowCycle) => {
        cycle.status = cycle.returnedAt ? '已归还' :
          ((cycle.barcode && activeBarcodes.has(cycle.barcode)) ||
            (!cycle.barcode && activeBookIds.has(book.id))) ? '借阅中' : '未见还书记录';
      });
      book.cycles.sort((a: BorrowCycle, b: BorrowCycle): number =>
        (b.returnedAt || b.borrowedAt).localeCompare(a.returnedAt || a.borrowedAt));
      book.otherEvents.reverse();
      book.status = book.cycles.some((cycle: BorrowCycle): boolean => cycle.status === '借阅中') ?
        '借阅中' : book.cycles.some((cycle: BorrowCycle): boolean => cycle.status === '未见还书记录') ?
          '记录不完整' : book.cycles.length > 0 ? '已归还' : '其他记录';
    });
    return grouped.sort((a: BorrowHistory, b: BorrowHistory): number =>
      b.latestAt.localeCompare(a.latestAt));
  }

  static async loadSnapshot(): Promise<PersonalLibrarySnapshot> {
    const responses = await Promise.all([
      LibraryDataService.requestPages<RawCurrentLoan>('reader-borrowinfo.json', 'reader-borrowinfo.html'),
      LibraryDataService.requestPages<RawHistory>('reader-history.json', 'reader-history.html',
        '&name=&date=&dateEnd=&type=all', 10)
    ]);
    const borrowed = responses[0] as RawCurrentLoan[];
    const history = responses[1] as RawHistory[];
    return {
      currentLoans: borrowed.map((raw: RawCurrentLoan, index: number): CurrentLoan => ({
        id: raw.recCtrlId || `loan-${index}`,
        title: raw.title || '未命名图书',
        barcode: raw.bookBarcode || '',
        callNumber: raw.bookSearchNo || '',
        department: raw.depName || '',
        status: raw.statusDesc || '',
        dueDate: raw.mydate || '',
        overdue: (raw.guoqi ?? 0) > 0
      })),
      history: LibraryDataService.groupHistory(history, borrowed)
    };
  }

}

