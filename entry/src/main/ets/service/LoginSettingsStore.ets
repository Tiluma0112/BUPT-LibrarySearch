import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'my_library';
const DAYS_KEY: string = 'login_valid_days';
const UNTIL_KEY: string = 'login_valid_until';
const AUTH_AT_KEY: string = 'login_authenticated_at';
const DAY_MS: number = 24 * 60 * 60 * 1000;

export class LoginSettingsStore {
  static days(context: Context): number {
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      return store.getSync(DAYS_KEY, 7) as number;
    } catch (_error) {
      return 7;
    }
  }

  static setDays(context: Context, days: number): void {
    if (days !== 1 && days !== 7 && days !== 30) { return; }
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    const oldDays = store.getSync(DAYS_KEY, 7) as number;
    const oldUntil = store.getSync(UNTIL_KEY, 0) as number;
    let authenticatedAt = store.getSync(AUTH_AT_KEY, 0) as number;
    if (!authenticatedAt && oldUntil > 1) {
      authenticatedAt = oldUntil - oldDays * DAY_MS;
    }
    store.putSync(DAYS_KEY, days);
    if (oldUntil > 1 && authenticatedAt > 0) {
      store.putSync(AUTH_AT_KEY, authenticatedAt);
      store.putSync(UNTIL_KEY, authenticatedAt + days * DAY_MS);
    }
    store.flushSync();
  }

  static markAuthenticated(context: Context): void {
    const authenticatedAt = Date.now();
    const until = authenticatedAt + LoginSettingsStore.days(context) * DAY_MS;
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.putSync(AUTH_AT_KEY, authenticatedAt);
    store.putSync(UNTIL_KEY, until);
    store.flushSync();
  }

  static isWithinValidPeriod(context: Context): boolean {
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      return Date.now() < (store.getSync(UNTIL_KEY, 0) as number);
    } catch (_error) {
      return false;
    }
  }

  static isExpired(context: Context): boolean {
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const until = store.getSync(UNTIL_KEY, 0) as number;
      return until > 0 && Date.now() >= until;
    } catch (_error) {
      return false;
    }
  }

  static markExpired(context: Context): void {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.putSync(AUTH_AT_KEY, 0);
    store.putSync(UNTIL_KEY, 1);
    store.flushSync();
  }

  static clear(context: Context): void {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.putSync(AUTH_AT_KEY, 0);
    store.putSync(UNTIL_KEY, 0);
    store.flushSync();
  }
}
