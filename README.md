# 北邮图书馆 OPAC 客户端

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

> 基于 HarmonyOS NEXT（ArkTS + ArkUI）的北京邮电大学图书馆 OPAC 第三方客户端。支持公开书目检索、馆藏详情与架位地图，以及登录后的个人借阅信息查看。
>
> **本项目为非官方客户端，与北京邮电大学图书馆无隶属或授权关系，仅供学习与个人使用。请遵守图书馆的相关使用规定。**

App 直接请求馆方 OPAC 与门户页面接口，**不需要额外的 Python 网关或自建后端**；统一身份认证通过馆方网页（CAS）完成，App 不提供借阅、预约等写操作。

<!-- 截图占位：可在此处补充界面截图，例如
![检索页](docs/screenshots/search.png)
![书目详情](docs/screenshots/detail.png)
![我的图书馆](docs/screenshots/my-library.png)
-->

## 功能特性

### 公开检索（无需登录）

- 按题名、责任者、ISBN/ISSN、出版年、出版社、主题词检索
- 校区筛选：全部 / 本部 / 宏福 / 沙河
- 每页 10 / 20 / 50 条，支持分页浏览
- 当前页客户端排序（题名、出版年、可借数量）与可借状态筛选
- 下拉刷新、加载/空态/错误重试提示

### 书目详情

- 书目字段：责任者、出版、ISBN/ISSN、中图分类号、载体形态、并列题名、价格
- 馆藏按馆藏部门分组，展示索书号、图书条码、登录号、卷期、状态
- 架位信息：馆方架位服务可访问时内嵌地图，支持全屏缩放预览；不可访问时显示占位图与重试入口

### 我的图书馆（需登录）

- 北邮统一身份认证（CAS 网页登录，**不保存密码**）
- 个人信息卡片：姓名、学工号、头像（本地缓存）
- 当前借阅、借阅历史（按书目合并借阅周期，展示借还时间与续借次数）
- 独立的借阅历史页面：书名/作者/ISBN/条码关键词搜索 + 日期范围筛选
- 本地收藏（保存在设备本地）
- 自动续登有效期设置：1 / 7 / 30 天；冷启动静默续登，失效时提示重新登录

### 体验与外观

- API 26 沉浸光感底部导航（`barFloatingStyle` + 系统沉浸材质），滚动内容可从胶囊菜单下透出
- 左右滑动切换 Tab 时，页签文字与指示线跟随手势进度渐变
- 深色 / 浅色模式适配（两套颜色资源）
- 系统下拉刷新动画

## 技术栈

| 类别 | 说明 |
| --- | --- |
| 平台 | HarmonyOS NEXT，Stage 模型，单 HAP（`entry` 模块） |
| 语言 / UI | ArkTS + ArkUI，声明式开发 |
| SDK | HarmonyOS SDK `26.0.0`（API 26，`targetSdkVersion` 与 `compatibleSdkVersion` 一致） |
| 网络 | `@kit.NetworkKit` HTTP（请求馆方 JSON 接口、抓取并解析 HTML 页面） |
| Web | `@kit.ArkWeb`（完成统一身份认证、读取已登录页面资料、隐藏 WebView 静默续登） |
| 本地存储 | `@kit.ArkData` Preferences + 应用私有文件（头像缓存） |
| 工程工具 | DevEco Studio 26、hvigor、Code Linter、ohpm |

## 环境要求

| 项目 | 要求 |
| --- | --- |
| DevEco Studio | 26.0.0 或更高 |
| HarmonyOS SDK | 26.0.0（API 26） |
| 设备 | `phone`；真机或模拟器 |
| 网络 | 检索/详情可用公网；架位地图依赖校园内网服务；登录需要能访问学校统一身份认证 |

## 构建与运行

1. 用 DevEco Studio 26 打开本仓库根目录。
2. 首次打开时按提示 Sync（自动用 ohpm 安装 `@ohos/hypium`、`@ohos/hamock` 等开发依赖）。
3. 在 **File > Project Structure > Signing Configs** 中为本机配置调试签名（可勾选自动生成）。
4. 选择 `entry` 模块，连接真机或启动模拟器后运行。

> **关于签名**：本仓库**不包含任何签名配置**（证书路径、密码等属于个人环境信息，已移除）。未配置签名时构建只能得到 `entry-default-unsigned.hap`，无法安装到设备。
> 构建产物默认位于 `entry/build/default/outputs/default/`（`*.hap` 不入库）；可直接安装的签名 HAP 请从 **Releases** 获取。
> `AppScope/app.json5` 中的 `bundleName` 目前为 `com.tiluma0112.buptlibrary`，可按需替换成自己的反向域名标识。

## 项目结构

```text
.
├── AppScope/                        # 应用级配置与资源
│   ├── app.json5                    # bundleName、版本、图标、应用名
│   └── resources/base/              # 应用图标等资源
├── entry/                           # 主 HAP 模块
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/        # UIAbility 入口
│   │   │   ├── entrybackupability/  # 备份扩展（模板）
│   │   │   ├── common/              # 常量与格式化（AppConfig、Format）
│   │   │   ├── model/               # 数据类型定义
│   │   │   ├── service/             # 业务与数据访问层
│   │   │   │   ├── OpacService.ets            # 公开检索 / 详情 / 架位
│   │   │   │   ├── LibraryDataService.ets     # 个人借阅数据与历史聚合
│   │   │   │   ├── PortalProfileBridge.ets    # ArkWeb 注入读取个人资料
│   │   │   │   ├── ReaderProfileStore.ets     # 个人资料与头像缓存
│   │   │   │   ├── LoginSettingsStore.ets     # 续登有效期
│   │   │   │   └── FavoritesStore.ets         # 本地收藏
│   │   │   ├── components/          # 通用组件（借阅历史卡片）
│   │   │   └── pages/               # 页面
│   │   │       ├── Index.ets              # 入口：检索页 + 我的 + 路由
│   │   │       ├── BookDetail.ets         # 书目详情与架位地图
│   │   │       ├── MyLibrary.ets          # 我的图书馆
│   │   │       ├── BorrowHistoryPage.ets  # 借阅历史（筛选）
│   │   │       ├── LibraryLogin.ets       # 统一身份认证
│   │   │       └── LibraryPortal.ets      # 馆方门户网页
│   │   ├── resources/               # 字符串、颜色（明/暗）、图标、页面配置
│   │   └── module.json5             # 模块配置（权限、Ability、页面）
│   ├── src/test/                    # 本地单元测试（模板）
│   ├── src/ohosTest/                # 设备测试（模板）
│   ├── build-profile.json5
│   └── oh-package.json5
├── hvigor/hvigor-config.json5
├── build-profile.json5              # 工程构建配置（不含签名配置）
├── code-linter.json5
├── oh-package.json5
├── oh-package-lock.json5
├── LICENSE
└── README.md
```

> `oh_modules/`、`.hvigor/`、`.idea/`、`local.properties`、`entry/build/` 等由工具生成的目录不会入库（见 `.gitignore`），首次打开工程时会自动重建。

## 实现说明

### 数据来源

App 仅访问馆方站点，不经过第三方服务器：

| 功能 | 接口（相对馆方站点） | 方法 | 备注 |
| --- | --- | --- | --- |
| 检索 | `/search-full-result.json` | POST（表单） | `keyword`、`solrType`、`xiaoqu`、`pageNo`、`pageSize` |
| 详情 | `/bookInfo_{id}.html` | GET | 解析 HTML 中的书目字段与馆藏表格 |
| 架位 | `/tunano/ldc/lc/v1/ldc/lc/BookCollection/...` | GET | 由详情页“架位导航”链接解析出 `libraryCode` / `bookSn`；需校园内网 |
| 个人资料 | `/engine2/header/user-info` | GET | 携带门户会话 Cookie |
| 当前借阅 | `/reader-borrowinfo.json` | POST | 需要 OPAC 登录会话 |
| 借阅历史 | `/reader-history.json` | POST | 参数 `name`、`date`、`dateEnd`、`type=all`，按 10 条分页 |

### 认证与续登流程

1. App 打开 OPAC 的 CAS 登录页，用户在学校统一身份认证页面完成登录（密码只进入馆方网页，App 不读取）。
2. 回跳 `/reader-setting.html`，建立 OPAC 会话。
3. 继续通过门户 SSO 建立门户会话，读取 `/engine2/header/user-info`。
4. 若接口资料不完整，通过 ArkWeb 注入脚本从已登录页面读取（`$nuxt` 状态 → DOM 兜底），头像做域名白名单校验。
5. 资料缓存于 Preferences 与应用私有文件；在有效期内冷启动时，用隐藏的 1×1 WebView 自动续登，失效则提示重新登录。

### 本地存储

| 位置 | 键 / 文件 | 内容 |
| --- | --- | --- |
| Preferences `my_library` | `favorite_books` | 本地收藏列表（JSON） |
| Preferences `my_library` | `login_valid_days` / `login_valid_until` / `login_authenticated_at` | 自动续登有效期 |
| Preferences `reader_profile` | `name` / `student_id` / `avatar_url` | 个人信息缓存 |
| 应用私有文件 | `reader_avatar.bin` | 头像缓存 |

退出登录会清空上述内容并调用 `clearAllCookiesSync()` 清除 Web Cookie。

### UI 实现要点

- `Navigation` + `NavPathStack` 管理详情页、登录页、门户页等路由，`Tabs` 承载“检索 / 我的”两个主页面。
- 底部导航使用 API 26 的 `barFloatingStyle`、`barOverlap` 与 `ImmersiveMaterial` 实现沉浸材质；`onGestureSwipe` 驱动页签透明度与指示线进度。
- 页面数据请求使用自增版本号（`requestVersion` / `generation`）防止异步竞态，列表使用 `Refresh` 下拉刷新。

## 隐私说明

- 不采集设备标识、位置、通讯录等任何个人信息，不含统计埋点与第三方 SDK。
- 所有网络请求只发往馆方域名；个人信息仅保存在**设备本地**，不会上传。
- 密码不落盘；Web Cookie 由 ArkWeb 管理，退出登录时清除。
- 若需更严格的隐私姿态，可将 `my_library` / `reader_profile` 从系统备份范围中排除（`backup_config.json`）。

## 已知限制

- 馆方接口均为网页侧接口，无官方文档，页面改版可能导致解析失败，需要随馆方调整。
- 借阅历史单次最多读取 40 页（每页 10 条），超出会提示前往图书馆网页查看。
- 架位地图依赖校园内网服务，外网环境只能显示占位信息。
- 目前未实现“最近查看”与期刊现刊的特殊字段。
- 仅适配 API 26，旧版本 SDK 可能无法直接编译；界面文案目前为中文硬编码。

## 路线图

- [ ] 为页面解析与借阅历史聚合补充单元测试（当前测试目录为模板）
- [ ] 拆分 `Index.ets` 中的检索、路由与静默续登逻辑，抽取认证状态机
- [ ] 统一错误码，替换跨层字符串判断
- [ ] 资源文案集中管理并支持多语言
- [ ] 长列表改用 `LazyForEach`，缓存列表排序结果

## 参与贡献

欢迎通过 Issue 反馈问题、通过 Pull Request 提交改进：

1. 提交前请先在本地完成构建与运行验证。
2. 请勿提交任何签名材料、本机路径、账号信息或个人数据。
3. 代码请遵循 `code-linter.json5` 中的规则（可使用 DevEco Studio 的 Code Linter 检查）。
4. 涉及页面解析的改动，请附上验证方式（页面结构变化、样例页面等）。

## 免责声明

- 本项目为非官方第三方客户端，与北京邮电大学及其图书馆无隶属或授权关系。
- 项目所访问的接口、页面与数据归馆方所有，接口可能随时调整或关闭。
- 本项目仅供学习交流，请勿用于商业用途，请勿高频请求影响馆方服务。
- 使用本项目产生的一切后果由使用者自行承担；请遵守学校与图书馆的相关规定。

## 许可证

本项目采用 [MIT License](LICENSE) 开源 —— 这是最通用、限制最少的开源许可证之一：允许自由使用、修改、分发，包括商业使用，只需保留版权与许可声明，且不提供任何担保。

Copyright (c) 2026 Tiluma0112

## 致谢

- 项目作者 / 维护者：[@Tiluma0112](https://github.com/Tiluma0112)
- 北京邮电大学图书馆 OPAC 与统一身份认证服务
- HarmonyOS / ArkUI / DevEco Studio
- 所有为本项目提供反馈与建议的同学
