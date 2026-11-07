import { preferences } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { ReaderProfile } from '../model/PersonalTypes';

const STORE_NAME: string = 'reader_profile';
const AVATAR_FILE: string = 'reader_avatar.bin';

export class ReaderProfileStore {
  static load(context: Context): ReaderProfile {
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      return {
        name: store.getSync('name', '') as string,
        studentId: store.getSync('student_id', '') as string,
        avatarUrl: store.getSync('avatar_url', '') as string,
        avatarLocalUri: ReaderProfileStore.localAvatarUri(context)
      };
    } catch (_error) {
      return { name: '', studentId: '', avatarUrl: '', avatarLocalUri: '' };
    }
  }

  static save(context: Context, profile: ReaderProfile): void {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.putSync('name', profile.name);
    store.putSync('student_id', profile.studentId);
    store.putSync('avatar_url', profile.avatarUrl);
    store.flushSync();
  }

  static localAvatarUri(context: Context): string {
    const path = `${context.filesDir}/${AVATAR_FILE}`;
    try {
      fileIo.accessSync(path);
      return fileUri.getUriFromPath(path);
    } catch (_error) {
      return '';
    }
  }

  static async cacheAvatar(context: Context, url: string): Promise<string> {
    if (!url.startsWith('https://libadmin.bupt.edu.cn/photo/p/')) { return ''; }
    const connection = http.createHttp();
    try {
      const cookie = webview.WebCookieManager.fetchCookieSync('https://libadmin.bupt.edu.cn');
      const headers: Record<string, string> = {};
      if (cookie) { headers['Cookie'] = cookie; }
      const response = await connection.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 6000,
        readTimeout: 10000
      });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer) ||
        response.result.byteLength === 0 || response.result.byteLength > 1024 * 1024) { return ''; }
      const bytes = new Uint8Array(response.result);
      const jpeg = bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF;
      const png = bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
        bytes[2] === 0x4E && bytes[3] === 0x47;
      const gif = bytes.length >= 3 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46;
      const webp = bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
        bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 &&
        bytes[10] === 0x42 && bytes[11] === 0x50;
      if (!jpeg && !png && !gif && !webp) { return ''; }
      const path = `${context.filesDir}/${AVATAR_FILE}`;
      const file = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, response.result);
      } finally {
        fileIo.closeSync(file);
      }
      return fileUri.getUriFromPath(path);
    } catch (_error) {
      return '';
    } finally {
      connection.destroy();
    }
  }

  static clear(context: Context): void {
    const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    store.putSync('name', '');
    store.putSync('student_id', '');
    store.putSync('avatar_url', '');
    store.flushSync();
    try { fileIo.unlinkSync(`${context.filesDir}/${AVATAR_FILE}`); } catch (_error) {}
  }
}
