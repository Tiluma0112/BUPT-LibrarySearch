import { webview } from '@kit.ArkWeb';
import { ReaderProfile } from '../model/PersonalTypes';

// 从馆方已登录网页读取页面当前展示的资料；不读取或保存 Cookie、密码、令牌。
export class PortalProfileBridge {
  private static readonly script: string = `(function() {
    var user = window.$nuxt && window.$nuxt.$store && window.$nuxt.$store.state.userInfo;

    // ---- 学工号：明确排除 uid，避免拿到内部 ID ----
    var id = user && (user.uname || user.studentId || user.studentNo || user.userNo) || '';
    var pageText = document.body ? (document.body.innerText || '') : '';
    if (!id) {
      var idMatch = /(?:学工号|学号|工号)\\s*[：:]?\\s*([0-9]{6,20})/.exec(pageText);
      if (idMatch) { id = idMatch[1]; }
    }
    // ---- 姓名：优先 $nuxt，DOM 兜底找“姓名”标签附近的文本 ----
    var name = user && (user.realname || user.realName || user.name) || '';
    if (!name) {
      var nameMatch = /(?:^|\\n)\\s*姓名\\s*[：:]?\\s*([^\\n\\s：:]{2,12})/.exec(pageText);
      if (nameMatch) { name = nameMatch[1]; }
    }
    if (!name) {
      var all = document.querySelectorAll('*');
      for (var k = 0; k < all.length; k++) {
        var el = all[k];
        if (el.children.length > 3) { continue; }
        var txt = (el.textContent || '').trim();
        if (txt.indexOf('姓名') === 0 && txt.length < 30) {
          var sibling = el.nextElementSibling;
          if (sibling) {
            var sibTxt = (sibling.textContent || '').trim();
            if (sibTxt.length > 0 && sibTxt.length < 30) { name = sibTxt; break; }
          }
          var parent = el.parentElement;
          if (parent) {
            var pTxt = (parent.textContent || '').replace(txt, '').trim();
            if (pTxt.length > 0 && pTxt.length < 30) { name = pTxt; break; }
          }
        }
      }
    }

    // ---- 头像：页面 img 优先（最可靠），其次 $nuxt.portrait，最后拼 URL ----
    var avatar = '';
    // 1. 页面实际加载的头像 img
    var imgs = document.querySelectorAll('img');
    for (var m = 0; m < imgs.length; m++) {
      var src = imgs[m].src || '';
      var dataSrc = imgs[m].getAttribute('data-src') || '';
      var srcset = imgs[m].getAttribute('srcset') || '';
      if (src.indexOf('https://libadmin.bupt.edu.cn/photo/p/') === 0) {
        avatar = src; break;
      }
      if (dataSrc.indexOf('https://libadmin.bupt.edu.cn/photo/p/') === 0) {
        avatar = dataSrc; break;
      }
      if (srcset.indexOf('https://libadmin.bupt.edu.cn/photo/p/') >= 0) {
        var parts = srcset.split(',');
        for (var p = 0; p < parts.length; p++) {
          var candidate = parts[p].trim().split(' ')[0];
          if (candidate.indexOf('https://libadmin.bupt.edu.cn/photo/p/') === 0) {
            avatar = candidate; break;
          }
        }
        if (avatar) { break; }
      }
    }
    // 2. $nuxt.portrait
    if (!avatar && user && user.portrait) {
      avatar = user.portrait;
    }
    // 3. 最后才用 uid 或学工号拼（兜底，不优先）
    if (!avatar) {
      var avatarKey = (user && user.uid) ? String(user.uid) : id;
      if (avatarKey) {
        avatar = 'https://libadmin.bupt.edu.cn/photo/p/' + avatarKey + '_94';
      }
    }

    return JSON.stringify({name: String(name), studentId: String(id), avatarUrl: String(avatar)});
  })()`;

  static async read(controller: webview.WebviewController): Promise<ReaderProfile | null> {
    for (let attempt = 0; attempt < 8; attempt++) {
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, attempt === 0 ? 1000 : 1500));
      try {
        const result = await controller.runJavaScript(PortalProfileBridge.script);
        const once: ReaderProfile | string = JSON.parse(result) as ReaderProfile | string;
        const profile: ReaderProfile = typeof once === 'string' ?
          JSON.parse(once) as ReaderProfile : once;
        if (!profile.name || !profile.studentId) { continue; }
        if (!profile.avatarUrl.startsWith('https://libadmin.bupt.edu.cn/photo/p/')) {
          profile.avatarUrl = '';
        }
        profile.avatarLocalUri = '';
        return profile;
      } catch (_error) {}
    }
    return null;
  }
}
