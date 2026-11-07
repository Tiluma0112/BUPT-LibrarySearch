// 北邮图书馆公开 OPAC，无需本地网关。
export const OPAC_BASE_URL: string = 'https://opac.bupt.edu.cn';
export const SHELF_MAP_BASE_URL: string = 'http://10.3.210.83:3040';
export const LIBRARY_LOGIN_URL: string = `${OPAC_BASE_URL}/cas/CasReader.html`;
export const PORTAL_BASE_URL: string = 'https://lib.bupt.edu.cn';
export const PORTAL_MY_LIBRARY_URL: string = `${PORTAL_BASE_URL}/v2/p/ee266c28842b3311f019d840d117b361dc3e`;
export const PORTAL_LOGIN_URL: string = 'https://auth.bupt.edu.cn/authserver/login?service=' +
  encodeURIComponent(`${PORTAL_BASE_URL}/sso/login/3rd/1843?referer=${encodeURIComponent(PORTAL_MY_LIBRARY_URL)}`);

// 开源仓库地址：GitHub 仓库创建后，请把下面的仓库地址改成实际地址
export const GITHUB_REPO_URL: string = 'https://github.com/Tiluma0112/BUPT-LibrarySearch';
