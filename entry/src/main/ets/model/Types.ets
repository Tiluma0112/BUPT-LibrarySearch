export type SearchField = 'title' | 'author' | 'isbn' | 'year' | 'publisher' | 'subject';
export type Campus = 'all' | 'main' | 'hongfu' | 'shahe';

export interface SearchQuery {
  q: string;
  field: SearchField;
  campus: Campus;
  page: number;
  page_size: number;
}

export interface BookSummary {
  id: string;
  title: string;
  authors: string;
  publisher: string;
  publication_year: string;
  isbn_issn: string;
  call_number: string;
  holdings_count: number | null;
  available_count: number | null;
  detail_url: string;
}

export interface SearchResponse {
  query: SearchQuery;
  total: number;
  total_pages: number;
  items: BookSummary[];
}

export interface Holding {
  department: string;
  barcode: string;
  call_number: string;
  accession_number: string;
  volume: string;
  status: string;
  shelf_location: string;
  navigation_url: string;
  navigation_is_private_network: boolean;
}

export interface BookDetailResponse {
  id: string;
  title: string;
  isbn_issn?: string;
  publication?: string;
  responsibility?: string;
  classification?: string;
  physical_description?: string;
  parallel_title?: string;
  price?: string;
  holdings: Holding[];
  detail_url: string;
}

export interface ApiErrorResponse {
  error: string;
}
