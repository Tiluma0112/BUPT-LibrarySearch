import { http } from '@kit.NetworkKit';
import { OPAC_BASE_URL, SHELF_MAP_BASE_URL } from '../common/AppConfig';
import { BookDetailResponse, BookSummary, Campus, Holding, SearchField, SearchQuery, SearchResponse } from '../model/Types';

interface RawSearchRecord {
  recCtrlId?: string;
  title?: string;
  authors?: string;
  publisher?: string;
  pubdateDate?: string;
  isn?: string;
  bookSearchNo?: string;
  guancangCount?: number | null;
  kejieCount?: number | null;
}

interface RawSearchResponse {
  result?: RawResult;
  total?: number;
  totalPage?: number;
  data?: RawSearchRecord[];
}

interface RawResult {
  code?: number;
  msg?: string;
}

interface RawShelfLayer {
  displayName?: string;
  name?: string;
}

interface RawShelf {
  name?: string;
}

interface RawShelfInventory {
  bookShelf?: RawShelf;
  bookShelfLayer?: RawShelfLayer;
}

interface RawShelfResult {
  collectionInventory?: RawShelfInventory;
}

interface RawShelfResponse {
  errorCode?: number | string;
  result?: RawShelfResult;
}

export class OpacService {
  static mapPreviewUrl(url: string): string {
    // 馆方只识别 iOS/Android UA；HarmonyOS 直接进入其手机布局路由。
    return url.startsWith(`${SHELF_MAP_BASE_URL}/position?`) ?
      url.replace('/position?', '/phone/position?') : url;
  }

  static async shelfLocationFromMap(url: string): Promise<string> {
    if (!url.startsWith(`${SHELF_MAP_BASE_URL}/position?`)) { return ''; }
    const libraryCode = /[?&]libraryCode=([A-Za-z0-9-]+)/.exec(url)?.[1] ?? '';
    const bookSn = /[?&]bookSn=([A-Za-z0-9-]+)/.exec(url)?.[1] ?? '';
    if (!libraryCode || !bookSn) { return ''; }
    const path = `/tunano/ldc/lc/v1/ldc/lc/BookCollection/libraryCode/${libraryCode}` +
      `/bookSn/${bookSn}?isCurrent=true`;
    const connection = http.createHttp();
    try {
      const response = await connection.request(`${SHELF_MAP_BASE_URL}${path}`, {
        method: http.RequestMethod.GET,
        connectTimeout: 4000,
        readTimeout: 6000
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') { return ''; }
      const parsed = JSON.parse(response.result) as RawShelfResponse;
      console.info(`OPAC shelf: library ${libraryCode}, code ${parsed.errorCode ?? 'missing'}`);
      if (Number(parsed.errorCode) !== 0) { return ''; }
      const layer = parsed.result?.collectionInventory?.bookShelfLayer;
      const shelf = parsed.result?.collectionInventory?.bookShelf;
      const shelfName = (shelf?.name || '').trim();
      const layerName = (layer?.displayName || layer?.name || '').trim();
      if (shelfName && layerName && !layerName.includes(shelfName)) {
        return `${shelfName} ${layerName}`;
      }
      return layerName || shelfName;
    } catch (_error) {
      return '';
    } finally {
      connection.destroy();
    }
  }

  static async navigationAvailable(url: string): Promise<boolean> {
    if (!/^https?:\/\//i.test(url)) { return false; }
    const connection = http.createHttp();
    try {
      const response = await connection.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 4000,
        readTimeout: 6000
      });
      return response.responseCode === 200;
    } catch (_error) {
      return false;
    } finally {
      connection.destroy();
    }
  }

  private static fieldCode(field: SearchField): string {
    switch (field) {
      case 'author': return 'AUTHOR';
      case 'isbn': return 'ISN_SHOW';
      case 'year': return 'PUBDATE';
      case 'publisher': return 'PUBLISHER';
      case 'subject': return 'SUBJECT';
      default: return 'TITLE';
    }
  }

  private static campusCode(campus: Campus): string {
    switch (campus) {
      case 'main': return 'A01';
      case 'hongfu': return 'A02';
      case 'shahe': return 'A03';
      default: return 'all';
    }
  }

  private static async request(path: string, method: http.RequestMethod, form?: string,
    referer: string = '/search-full-result.html'): Promise<string> {
    const connection = http.createHttp();
    try {
      const response = await connection.request(`${OPAC_BASE_URL}${path}`, {
        method: method,
        header: {
          'Accept': 'application/json, text/html;q=0.9',
          'Referer': `${OPAC_BASE_URL}${referer}`,
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
        },
        extraData: form ?? '',
        connectTimeout: 10000,
        readTimeout: 20000
      });
      if (response.responseCode !== 200) {
        throw new Error(`图书馆接口返回 HTTP ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error('图书馆接口返回格式不正确');
      }
      return response.result;
    } finally {
      connection.destroy();
    }
  }

  private static clean(value?: string): string {
    const plain = (value ?? '').replace(/<[^>]*>/g, '')
      .replace(/&nbsp;|&#160;/gi, ' ')
      .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>').replace(/&quot;/gi, '"')
      .replace(/&#39;|&apos;/gi, "'")
      .replace(/&#(\d+);/g, (_whole: string, decimal: string): string => String.fromCharCode(Number(decimal)));
    return plain.replace(/\s+/g, ' ').trim();
  }

  static async search(query: SearchQuery): Promise<SearchResponse> {
    const keyword = query.q.trim();
    if (!keyword || keyword.length > 200) {
      throw new Error('请输入 1–200 个字符的检索词');
    }
    const body = `keyword=${encodeURIComponent(keyword)}` +
      `&solrType=${OpacService.fieldCode(query.field)}` +
      `&xiaoqu=${OpacService.campusCode(query.campus)}` +
      `&pageNo=${query.page}&pageSize=${query.page_size}` +
      '&classSearch=0&searchPrecision=';
    const raw = await OpacService.request('/search-full-result.json', http.RequestMethod.POST, body);
    const parsed = JSON.parse(raw) as RawSearchResponse;
    if (parsed.result?.code !== 0) {
      throw new Error(parsed.result?.msg ?? '图书馆返回的检索数据不可用');
    }
    const records = parsed.data ?? [];
    const items: BookSummary[] = records.map((item: RawSearchRecord): BookSummary => {
      const id = String(item.recCtrlId ?? '');
      return {
        id: id,
        title: OpacService.clean(item.title),
        authors: OpacService.clean(item.authors),
        publisher: OpacService.clean(item.publisher),
        publication_year: OpacService.clean(item.pubdateDate),
        isbn_issn: OpacService.clean(item.isn),
        call_number: OpacService.clean(item.bookSearchNo),
        holdings_count: item.guancangCount ?? null,
        available_count: item.kejieCount ?? null,
        detail_url: `${OPAC_BASE_URL}/bookInfo_${id}.html`
      };
    });
    console.info(`OPAC search: ${items.length} items, total ${parsed.total ?? 0}`);
    return {
      query: { q: keyword, field: query.field, campus: query.campus, page: query.page,
        page_size: query.page_size },
      total: parsed.total ?? 0,
      total_pages: parsed.totalPage ?? 0,
      items: items
    };
  }

  private static extractMetadata(html: string, label: string): string {
    const paragraphs = html.match(/<p\b[^>]*>[\s\S]*?<\/p>/gi) ?? [];
    for (const paragraph of paragraphs) {
      const text = OpacService.clean(paragraph);
      if (text.startsWith(`${label}：`) || text.startsWith(`${label}:`)) {
        return text.substring(label.length + 1).trim();
      }
    }
    return '';
  }

  private static parseHoldings(html: string): Holding[] {
    const table = html.match(/<table\b[^>]*>[\s\S]*?<tbody\b[^>]*id=["']guancanglist["'][^>]*>[\s\S]*?<\/tbody>[\s\S]*?<\/table>/i);
    if (!table) {
      return [];
    }
    const head = table[0].match(/<thead\b[^>]*>[\s\S]*?<\/thead>/i)?.[0] ?? '';
    const headers = (head.match(/<(?:th|td)\b[^>]*>[\s\S]*?<\/(?:th|td)>/gi) ?? [])
      .map((cell: string): string => OpacService.clean(cell));
    const body = table[0].match(/<tbody\b[^>]*id=["']guancanglist["'][^>]*>([\s\S]*?)<\/tbody>/i)?.[1] ?? '';
    const rows = body.match(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi) ?? [];
    return rows.map((row: string): Holding => {
      const cells = row.match(/<(?:th|td)\b[^>]*>[\s\S]*?<\/(?:th|td)>/gi) ?? [];
      const lookup = (label: string): string => {
        const index = headers.indexOf(label);
        return index < 0 || index >= cells.length ? '' : OpacService.clean(cells[index]);
      };
      const navIndex = headers.indexOf('架位导航');
      const navCell = navIndex < 0 ? '' : (cells[navIndex] ?? '');
      const href = OpacService.clean(navCell.match(/href\s*=\s*["']([^"']+)["']/i)?.[1]);
      const url = href.startsWith('/') ? `${OPAC_BASE_URL}${href}` : href;
      return {
        department: lookup('馆藏部门'),
        barcode: lookup('图书条码'),
        call_number: lookup('索书号'),
        accession_number: lookup('登录号'),
        volume: lookup('卷期'),
        status: lookup('状态'),
        shelf_location: lookup('图书架位') || lookup('架位') || lookup('排架位置') || lookup('书架位置'),
        navigation_url: url,
        navigation_is_private_network: /^https?:\/\/(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/i.test(url)
      };
    });
  }

  static async detail(id: string): Promise<BookDetailResponse> {
    if (!/^[A-Za-z0-9]{1,40}$/.test(id)) {
      throw new Error('无效的书目编号');
    }
    const html = await OpacService.request(`/bookInfo_${id}.html`, http.RequestMethod.GET);
    const title = OpacService.clean(html.match(/<h3\b[^>]*>([\s\S]*?)<\/h3>/i)?.[1]);
    if (!title) {
      throw new Error('详情页未找到书目信息');
    }
    const holdings = OpacService.parseHoldings(html);
    console.info(`OPAC detail: ${id}, ${holdings.length} holdings`);
    return {
      id: id,
      title: title,
      isbn_issn: OpacService.extractMetadata(html, 'ISBN/ISSN'),
      publication: OpacService.extractMetadata(html, '出版'),
      responsibility: OpacService.extractMetadata(html, '责任者'),
      classification: OpacService.extractMetadata(html, '中图分类号'),
      physical_description: OpacService.extractMetadata(html, '载体形态'),
      parallel_title: OpacService.extractMetadata(html, '并列题名'),
      price: OpacService.extractMetadata(html, '价格'),
      holdings: holdings,
      detail_url: `${OPAC_BASE_URL}/bookInfo_${id}.html`
    };
  }
}

