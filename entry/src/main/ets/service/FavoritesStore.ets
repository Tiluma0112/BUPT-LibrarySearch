import { preferences } from '@kit.ArkData';
import { FavoriteBook } from '../model/FavoriteBook';

const STORE_NAME: string = 'my_library';
const FAVORITES_KEY: string = 'favorite_books';

export class FavoritesStore {
  static list(context: Context): FavoriteBook[] {
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const raw = store.getSync(FAVORITES_KEY, '[]') as string;
      return JSON.parse(raw) as FavoriteBook[];
    } catch (_error) {
      return [];
    }
  }

  static contains(context: Context, id: string): boolean {
    return FavoritesStore.list(context).some((book: FavoriteBook): boolean => book.id === id);
  }

  static toggle(context: Context, book: FavoriteBook): boolean {
    const books = FavoritesStore.list(context);
    const index = books.findIndex((item: FavoriteBook): boolean => item.id === book.id);
    if (index >= 0) {
      books.splice(index, 1);
    } else {
      books.unshift(book);
    }
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.putSync(FAVORITES_KEY, JSON.stringify(books));
    store.flushSync();
    return index < 0;
  }
}
