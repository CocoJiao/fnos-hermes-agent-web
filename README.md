# fnos-hermes-agent-web

把 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)（开源 AI Agent）打包成**飞牛 fnOS 应用中心可直接安装的 FPK**，并提供 Web 化的桌面端界面、中文汉化与飞牛管理技能。

- 当前版本：`0.22.2.3`（对应官方 `v0.22.2`）
- 安装包：`dist/fnos-hermes-agent_v0.22.2.3.fpk`（约 83 MB）
- 每次迭代的详细过程（现象 / 根因 / 修复 / 验证）见 **[CHANGELOG.md](./CHANGELOG.md)**

---

## 目录

- [这是什么](#这是什么)
- [功能一览](#功能一览)
- [与官方版本的差异](#与官方版本的差异)
- [系统要求](#系统要求)
- [安装](#安装)
- [访问入口与端口](#访问入口与端口)
- [首次配置](#首次配置)
- [升级 / 回滚 / 卸载](#升级--回滚--卸载)
- [版本号规则](#版本号规则)
- [仓库结构](#仓库结构)
- [部署后的目录结构](#部署后的目录结构)
- [运行架构](#运行架构)
- [开发与构建](#开发与构建)
- [上游同步机制](#上游同步机制)
- [排障（FAQ）](#排障faq)
- [已知限制](#已知限制)
- [隐私与安全](#隐私与安全)
- [免责声明](#免责声明)

---

## 这是什么

分三层理解：

| 层 | 说明 |
|---|---|
| **上游 Hermes Agent** | Nous Research 的开源 AI Agent。多模型、多消息平台网关、持久记忆、技能系统、MCP 扩展、定时任务，自带桌面端（Electron）与 Web dashboard |
| **本项目** | 把它做成 fnOS 应用包：`install_callback` 负责部署源码与依赖、`monitor.js` 负责进程管理与 Web 入口、`web-shim.js` 负责把 Electron 桥接替换成浏览器实现、`fpk/` 是应用中心骨架 |
| **关系** | `app/hermes-src/` 是**上游源码的 vendored 副本**（可运行、已打定制补丁）；上游更新通过受控合并叠加，不是简单覆盖 |

**代码层面**的改动集中在少数几个文件，核心 Python 业务代码尽量保持原样，以便跟进官方更新；但**形态层面**（安装、界面、进程、依赖、数据目录）差异不小，完整清单见[与官方版本的差异](#与官方版本的差异)，同步流程见[上游同步机制](#上游同步机制)。

## 功能一览

- **多模型对话**：OpenAI / Anthropic / Kimi / MiniMax / Gemini / 火山引擎 / 自建兼容端点等
- **消息平台网关**：微信 ClawBot、QQ Bot、飞书、WhatsApp、Telegram 等（在「消息平台」页配置）
- **定时任务**：自然语言描述的 cron，界面可视化「定时任务」页
- **持久记忆与技能**：跨会话记忆、技能自动进化；内置 16 个技能目录（devops / github / research / creative / media / productivity…）
- **飞牛管理技能**：`trim-cli`（随包内置，位于 `fpk/config/prompts/skills/trim-cli`）
- **MCP 扩展**：连接 GitHub 等外部工具
- **两套界面**：桌面端 Web UI（主界面）+ 官方 dashboard（模型 / 网关 / 插件等设置面板）
- **自检与修复**：`POST /api/app/repair` 一键重启网关与 dashboard
- **版本与更新**：应用内可查当前构建版本与上游 commit；官方更新检查需配置 `GITHUB_REPO` 环境变量，未配置时接口返回 409（属正常提示）

## 与官方版本的差异

一句话：**上游的 Python 运行时核心基本原样保留，差异全在外面的"壳"**——发行方式、界面接入、进程模型、依赖供给、数据位置，外加一批面向中文/飞牛场景的增量功能。

先看总览：

| 维度 | 官方 Hermes Agent | 本项目（fnOS 版） |
|---|---|---|
| 发行形态 | 桌面端 monorepo：Electron App + CLI/TUI + Web dashboard | fnOS 应用包（FPK），浏览器使用，无桌面窗口 |
| 安装方式 | 自行 clone 仓库 / 跑 `setup-hermes.sh` / 自己管 Python 与 uv | 应用中心一键安装，自动装 `nodejs_v24`，包内自带 uv |
| 使用入口 | 桌面 App、`hermes` TUI、dashboard 各自启动 | 统一 HTTP 入口 `8650`，dashboard 由 `/proxy/dashboard` 内嵌 |
| 进程模型 | 用户前台启动，关终端即退出 | `monitor.js` 常驻守护 gateway / dashboard / embed-server |
| 数据目录 | `~/.hermes` | `@apphome/hermes-agent/data`（`HERMES_HOME` 指过去） |
| Python | 自备（`[all]` 依赖实际要求 3.14） | uv 托管 CPython 3.14，装到 `@apphome/uv-python` |
| 版本号 | 三段，如 `0.22.2` | 四段，如 `0.22.2.3`（第四段是构建号） |
| 升级 | `git pull` / 重新安装 | 应用中心覆盖安装，或应用内自动更新 |
| 语言 | 英文为主（含 `locales`） | 中文汉化层 + 中文厂商预设 |
| 发布方 | Nous Research 官方 | 第三方移植包（manifest `source = thirdparty`） |

### 1. 发行与安装

- **官方是桌面端 monorepo**：`apps/desktop`（Electron）、`web`（dashboard）、`native`、`website`、`docs`、`tests`、`evals` 等。本项目只 vendor **运行时核心**，桌面端只取**前端构建产物**（见[上游同步机制](#上游同步机制)）。
- **依赖自动装**：`manifest` 里 `install_dep_apps = nodejs_v24`，安装时由应用中心把 Node 24 装到 `/var/apps/nodejs_v24`；找不到时 `install_callback` 会兜底下载 Node v22 LTS。官方要自己准备 Node（主要用于构建前端）。
- **Python 不用你管**：包内自带 `uv`（`fpk/bin/uv`，约 47 MB），首次安装由 uv 下载 CPython 3.14 并建 venv；官方要求自己装 Python 3.14 + uv。若检测到内置 `venv-bundle.tar.gz`，解压即用、跳过在线安装。
- **安装向导 / 卸载向导**：`fpk/wizard/install` 只做说明；`fpk/wizard/uninstall` 让你选「保留数据」或「完全删除」（官方无向导概念）。
- **权限模型跟着 fnOS 走**：`fpk/config/privilege` 声明 `run-as: package`、用户 `hermes-agent`；安装后把应用目录/数据目录/日志目录统一 `chown` 到实际用户，避免 root 与 `hermes-agent` 混跑出 EACCES。
- **额外授权**：安装时写一条 sudoers，允许 `hermes-agent` 免密执行 `cp` / `chown` / `psql -d appcenter`——用于应用内更新覆盖文件、修权限、同步应用中心版本号。官方完全没有这一层。

### 2. 界面与访问

- **官方桌面端是 Electron**：渲染进程跑在 `file://`，通过 IPC 调 `window.hermesDesktop.*`（选文件、剪贴板、连接信息等）。本项目把它**Web 化**：`app/desktop-app/` = 官方 `apps/desktop` 的 renderer 构建产物 + 本项目 `index.html` / `web-shim.js`。
- **`web-shim.js` 是浏览器版桥接层**：用 Proxy 实现官方前端期待的全部 `hermesDesktop` 能力，并提供**242 条中英映射的汉化层**（MutationObserver + 500 ms 兜底）、移动端适配（iOS 输入框 16 px 防聚焦缩放、`safe-area-inset` 刘海屏）。
- **`index.html` 由脚本生成**：`scripts/desktop-inject-index.js` 注入三点——`viewport-fit=cover` + `interactive-widget=resizes-content`、`window.__HERMES_WEB_CONFIG__`（走代理 + session token）、`web-shim.js` 引用。
- **dashboard 被反向代理**：官方 dashboard 是本地开发面板（默认 `9119`），本项目由 `monitor.js` 代理到 `/proxy/dashboard/*` → `127.0.0.1:9219`，注入 session token，并把 WebSocket 的 `Host` / `Origin` 改写成 loopback（否则 dashboard 的 loopback 守卫会对局域网访问返回 403）。
- **端口主动迁走**：官方网关 `8642`、dashboard `9119`；本项目改为 **`8742` / `9219`**，规避同机 hermes-studio 之类应用对 `8642` 的抢占（跨用户进程本包杀不掉）。
- **绑定策略**：`8650` 绑 `0.0.0.0`（局域网可访问）；`9219` 只绑 `127.0.0.1`，`8742` 仅用于本机 monitor ↔ gateway 通信；另有一个 unix socket + `BASE_PATH=/app/hermes-agent` 供应用中心门户走。
- **两套界面并存**：桌面端 Web UI（主界面，走 8650）+ 官方 dashboard（模型/网关/插件设置）。官方需要自己分别打开，本项目收进同一入口。

### 3. 进程与运行

- **`monitor.js` 是唯一的常驻 Node 进程**（由 `fpk/cmd/main` 以 `hermes-agent` 用户拉起），负责启动/守护两个 Python 子进程：`hermes gateway`（8742，Agent 运行时）与 `hermes dashboard`（9219，官方面板），另有本地嵌入服务 `memory-core/embed-server.mjs`（8410，OpenAI 兼容 `/v1/embeddings`）。
- **官方没有守护层**：进程随终端退出，崩了要自己重启。本项目有健康检查（8742 用 `/proc` 的 LISTEN 判据，比 HTTP 探活可靠）、崩溃重启、`--replace` 兜底接管、PID 文件与 socket 校验。
- **启动前的自愈**：`main start` 会把 `@appdata` / `@apphome` 的属主拉回应用目录属主，清掉残留 socket；socket 被外部清理（如应用中心重置安装目录）后还能自动重建。
- **安装前的清场**：`install_init` 会先 `pkill` 残留的 monitor/gateway/dashboard、等进程真正退出、删 socket、检查 8650/8742/9219 端口占用（只杀 hermes 相关进程，避免误杀）、清掉 `@appdata` 里的旧 `app_version` 覆盖文件。
- **全新安装 vs 升级安装**：探测有没有 `config.yaml`；没有就清掉 `@appdata` 残留的 `extensions.json` / `providers-state.yaml` / `provider-models.json` / `.env.providers`（否则新装会看到上一环境的假 provider 和旧会话分组），会话历史与日志保留。
- **反向同步应用中心**：启动和更新后会 `UPDATE app SET status/version`（postgres `appcenter.app`），让应用中心显示的版本号与实际构建一致。官方没有这一层。

### 4. 依赖与运行时

- **Python 版本是个坑**：官方 `pyproject.toml` 写 `requires-python = ">=3.11,<3.15"`，但 0.22+ 的 `[all]` 依赖大量带 `python_version >= '3.14'` 标记——3.11 下这些包**一个都不会装**。飞牛系统自带 `python3` 是 **3.11.2**，所以本项目必须自带 3.14：`uv venv --python 3.14`，解释器落在 `@apphome/uv-python`，venv 落在 `data/venv`。
- **强制校验**：建完 venv 还会回读 `sys.version_info`，uv 若悄悄回退到系统 3.11 会直接报错中止，不让你装出一个"能装不能用"的环境。
- **跨文件系统**：`UV_LINK_MODE=copy`（`@appcenter` 与 `@apphome` 常不同挂载点，hardlink 会失败），uv 缓存也放进 `DATA_DIR`。
- **国内网络适配**：PyPI 走阿里云镜像；uv / CPython / Node 三处下载都有多源重试与兜底。官方默认直连。
- **uv 软链进 venv**：运行时 `PATH` 只有 `venv/bin`，所以把 uv 软链到 `venv/bin/uv`，让 Agent 在会话里也能用 uv。官方无此需要。

### 5. 数据与配置

- **`HERMES_HOME` 被重定向**：官方默认 `~/.hermes`；本项目 `HOME` 与 `HERMES_HOME` 都指向 `@apphome/hermes-agent/data`，于是 `config.yaml`、`sessions/`、`memories/`、`skills/`、`plugins/`、`state.db` 全在飞牛的数据卷里，卸载时可选保留。
- **版本戳机制（官方没有）**：官方 0.22 起 `pyproject.toml` 的 version 固定为 `0.0.0`，版本号改由 `install-stamp.json` 提供；本项目分发的是无 `.git` 的源码树，所以构建时生成 `install-stamp.json`，安装时再写 `fpk/config/bootstrap/hermes-version.env`（`HERMES_VERSION=0.22.2`）。缺了它 `hermes --version` 会显示 `unknown`。
- **配置模板**：`fpk/config/prompts/config.yaml` 是官方配置结构的快照（`agent` / `terminal` / `browser` / `web` 等段），provider 段留空，实际由界面写入。
- **provider 预设在本项目**：`src/server/provider-config.js` 内置一批国内外厂商的 base_url 与模型清单（OpenAI / DeepSeek / Anthropic / Gemini / Kimi / 智谱 / MiniMax / SiliconFlow / OpenRouter / xAI / 通义千问 / 腾讯 TokenHub / 小米 MiMo / LM Studio …），并支持 `custom-*` 自定义端点的环境变量映射（`CUSTOM_<ID>_API_KEY`）。官方是在 `config.yaml` 里手写 provider。

### 6. 版本与升级

- **四段版本号**：`0.22.2`（官方）+ `.3`（本项目构建号）。原因很实际：飞牛应用中心**同版本号不允许重装**，内容一改就必须递增构建号。
- **升级路径**：应用中心覆盖安装（数据保留）；或应用内 `/api/app/auto-update` —— 下载新 FPK 后自行解包覆盖 + hot-patch（因为 `appcenter-cli install-fpk` 对已安装应用只回 "is installed"，不执行升级）。
- **升级时的依赖策略**：`upgrade_callback` 比对版本，决定是否重装依赖；跨 Python 版本会自动重建 venv。
- **增量更新接口**：`/api/app/update/*` 这条链路尚未走通验证，当前实际可用路径仍是应用中心覆盖安装（见[已知限制](#已知限制)）。

### 7. 功能增量（官方没有的部分）

| 能力 | 位置 | 说明 |
|---|---|---|
| 应用管理 API | `monitor.js` 的 `/api/app/*` | `changelog` / `repair` / `auto-update` / `update/check·token·dispatch·run·fpk` / `hot-patch` |
| 一键修复 | `POST /api/app/repair` | 重启 gateway 与 dashboard，界面白屏/网关掉线时的第一反应 |
| 渠道扫码接入 | `custom_routes.js` | 微信 / Telegram / WhatsApp 的二维码登录与状态轮询（官方靠手填配置） |
| 群聊 Rooms | `custom_routes.js` | 多 Agent 协作房间，成员回复走 Hermes 会话流 |
| 技能市场 | `custom_routes.js` | 本地技能、远程技能、`skillhub.cn` 搜索与一键安装 |
| 连接器 | `connectors.js` | 腾讯新闻、百度地图等中文生态 MCP 连接器，填 Key 即用 |
| 专家 / 市场数据 | `experts-data.js` / `market-data.js` | 预置角色与目录数据 |
| 飞牛 NAS 技能 | `fpk/config/prompts/skills/trim-cli` | `trim-cli` 二进制（linux-x64 / arm64），管理存储、Docker、相册等 |
| 内网穿透 | `monitor.js` | 可选 Cloudflare Tunnel，自动下载 `cloudflared`（GitHub 加速镜像优先） |
| WhatsApp 桥接 | `app/server/whatsapp-bridge/` | 随包内置的 Node 桥接进程 |
| 中文 TTS 音色 | `monitor.js` | 晓晓 / 晓伊 / 云希 / 云健 / 云夏等 Edge 音色 |
| 汉化 + 移动端适配 | `src/desktop-app-web-shim.js` | 242 条映射、iOS 防缩放、刘海屏安全区 |
| 应用中心集成 | `fpk/**` | 生命周期脚本、向导、版本号回写、状态同步 |

### 8. 明确不跟随的部分

- **不同步官方非运行时目录**：`apps/native`、`web`、`website`、`docs`、`tests`、`evals`、`assets`、`.github`（见 `scripts/merge-upstream.js` 的 `EXCLUDE_TOP`）。官方桌面壳、官网、测试与评测集不会进包。
- **不做 Electron 原生能力**：系统托盘、全局快捷键、原生文件对话框、原生自动更新，均以 Web 能力近似替代，行为不完全等价。
- **不改官方 Python 业务逻辑**：`PORT_OVERRIDES` 目前是空集合——0.20.x 时代的三处手工补丁在 0.21 起已被官方内建且更强，继续保留反而会让新 `chat_ws` 调不到 `_start_backend_heartbeat_refresher`，WS 握手即崩。
- **不跟随官方 TUI 使用习惯**：主界面是 Web；`hermes` CLI 仍在（`@apphome/hermes-agent/data/venv/bin/hermes`），`fpk/config/resource` 也声明了 `usr-local-linker`（`bin/hermes`）以便命令行直接调用。
- **不做多用户/多租户**：整个应用是单实例，所有能访问 8650 的人共享同一份数据与同一套 provider Key。

### 9. 这些差异的代价

移植层与上游存在**隐式契约**，官方一改就可能断：

1. 官方前端新增 `hermesDesktop.*` 属性而我们没登记 → **整页白屏**（用 `scripts/check-bridge-contract.js` 兜）。
2. 官方新增运行时顶层包而白名单没收录 → 网关启动即 `ModuleNotFoundError`（合并脚本会打"未归类顶层条目"告警）。
3. 官方改依赖的 `python_version` 标记 → 解释器版本要求变化，venv 要重建。
4. 官方更新不会自动到达，必须人工同步并发版，存在天然滞后。
5. 任何 Web 化都会损失一点原生体验；任何"自动更新/自动修复"都多了一层可能出错的自研代码。

## 系统要求

| 项 | 要求 |
|---|---|
| 系统 | 飞牛 fnOS（底层 Debian 12 bookworm），x86_64 或 aarch64 |
| 依赖应用 | **Node.js v24**（`nodejs_v24`，应用中心会自动拉取） |
| 磁盘 | 应用本体约 195 MB + venv 约 710 MB + Python 3.14 约 116 MB ≈ **1.1 GB**（会话、缓存、模型文件另计） |
| 内存 | 实测 8 GB 设备可正常运行；4 GB 建议先跑轻量任务观察 |
| 网络 | **首次安装与升级必须联网**：需下载 CPython 3.14（约 35 MB）、Node.js（若未装）、以及 PyPI 依赖 |
| 浏览器 | Chrome / Edge / Safari 近期版本（桌面端 Web UI 用现代前端构建） |

## 安装

1. 取得 `fnos-hermes-agent_v<版本>.fpk`
2. 登录飞牛 → **应用中心** → **手动安装** → 选择该 `.fpk`
3. 安装向导里点下一步即可（仅一句说明）
4. 等待完成

**首次安装耗时约 10–20 分钟**，主要时间花在：

- 下载并安装 uv（PyPI 镜像，失败自动回落 GitHub）
- 用 uv 下载 **CPython 3.14**（约 35 MB）
- `uv pip install -e hermes-src[all]`（依赖较多，三源重试：官方 → 阿里云 → 清华）

安装期间**不要刷新页面或重复点击**。进度与错误全部写入日志：

```
${TRIM_PKGVAR}/info.log        # 即 /vol<N>/@appdata/hermes-agent/info.log
```

安装失败时，脚本会把最后几行日志弹到界面上；对照 [排障](#排障faq) 处理。

## 访问入口与端口

| 端口 | 用途 | 监听 | 说明 |
|---|---|---|---|
| **8650** | 主入口（Web UI + 应用 API） | `0.0.0.0` | 浏览器访问 `http://<NAS-IP>:8650/`，自动跳转到 `/app/hermes-agent/desktop-app/` |
| **9219** | 官方 dashboard（设置面板） | `127.0.0.1` | 由 8650 反向代理，路径前缀 `/proxy/dashboard/` |
| **8742** | Gateway WebSocket | 本机 | 前端与 Agent 的实时通道，一般无需外部访问 |
| unix socket | monitor 与包管理器通信 | — | 应用自管理用 |

也能在 SSH 里直接用命令行（`/usr/local/bin/hermes` 已链接到应用内入口）：

```bash
hermes --version     # 版本 / 上游 commit / Python 版本 / 安装方式
hermes               # TUI（需要交互终端）
```

> 8650 对局域网开放，未额外做访问控制。**不要把 8650 直接暴露到公网**，需要外网访问请走 VPN 或反向代理加认证。

## 首次配置

1. 打开主界面 → **设置 → 模型（Model）**，添加 provider 与 API Key；或在「自定义端点」里填兼容 OpenAI 的服务
2. 需要消息平台时，在「消息平台」页绑定对应渠道
3. 配置保存在数据目录的 `config.yaml`（路径见下节），改错可从 `config.yaml.bak-*` 回滚

## 升级 / 回滚 / 卸载

### 升级

**用新版 `.fpk` 覆盖安装**（应用中心 → 手动安装），**不要先卸载**：

- 升级只替换应用目录、重建/复用 venv，`config.yaml`、会话、技能、记忆都在数据目录里，**不会丢**
- 飞牛应用中心**不允许同版本号重装**，所以每次重新打包必须递增迭代号（`0.22.2.3` → `0.22.2.4`）
- 若升级跨越 Python 要求（例如从 0.21.x 升到 0.22.x），升级脚本会检测旧 venv 的解释器版本并**自动重建**为 3.14，无需手工干预

### 回滚

重新上传旧版本的 `.fpk` 覆盖安装即可（只回滚应用，不回滚配置）。建议保留上一版安装包。

### 卸载

应用中心卸载时会弹向导询问数据清理方式：

- **保留数据**（默认）：会话、记忆、技能、配置全部保留，下次安装可继续用
- **完全删除**：连同数据目录一起清除

## 版本号规则

版本号 = **官方版本 + 迭代号**（`<官方版本>.<迭代>`），release tag 为 `v<版本>`：

- 官方 `v0.22.2` → 本项目 `0.22.2.3`
- 官方升到 `v0.22.3` → 本项目从 `0.22.3.1` 重新开始
- 同一官方版本内每次重新打包，迭代号 +1

`VERSION` 文件是唯一真源；`build.sh` 会据此派生 `manifest.version`、
`config/bootstrap/hermes-version.env` 的 `HERMES_VERSION`，并写入 `install-stamp.json`。

## 仓库结构

```
fnos-hermes-agent-web/
├── app/                          # 完整可部署源码树（与部署端一致）
│   ├── server/                   # Node 后端
│   │   ├── monitor.js            # 进程主管：启动/守护 gateway 与 dashboard、HTTP 入口、应用 API
│   │   ├── custom_routes.js      # 自定义面板路由（personas / channels / skills / app-update）
│   │   ├── connectors.js         # 外部连接器
│   │   ├── market-data.js / experts-data.js / provider-config.js
│   │   ├── pty_bridge.py / preview_conv.py
│   │   ├── _vendor/  hermes-web-patch/  whatsapp-bridge/
│   ├── desktop-app/              # 桌面端 Web UI（官方 dist + 本项目 web-shim）
│   │   ├── index.html            # 注入 viewport / __HERMES_WEB_CONFIG__ / web-shim
│   │   ├── web-shim.js           # Electron 桥接的浏览器实现 + 中文汉化层
│   │   └── assets/  ds-assets/  emojibase/  hermes-frames/
│   ├── hermes-src/               # 上游 Hermes Agent 源码（vendored，可运行）
│   ├── ui/                       # 旧版控制台页面（desktop_uidir 指向此处）
│   ├── config/                   # bootstrap（版本注入）/ privilege / resource
│   └── package.json
├── src/                          # 上述自定义文件的原始副本（对照用；与 app/ 冲突时以 app/ 为准）
├── fpk/                          # 应用中心骨架
│   ├── manifest                  # 应用清单（含 install_dep_apps=nodejs_v24）
│   ├── cmd/                      # 生命周期脚本（见下表）
│   ├── config/                   # resource / privilege / prompts（含 trim-cli 技能）
│   ├── wizard/                   # 安装 / 卸载向导
│   ├── bin/                      # 随包二进制（uv）
│   └── ICON*.PNG  LICENSE
├── scripts/                      # 构建与同步脚本
│   ├── sync-upstream.js          # 检测官方最新 Release → 更新 VERSION / .upstream-state
│   ├── merge-upstream.js         # 受控合并 upstream/ → app/hermes-src
│   ├── desktop-inject-index.js   # 给官方 dist/index.html 注入 viewport / 配置 / web-shim
│   ├── check-bridge-contract.js  # 桥接契约检查（防 Proxy 兜底导致白屏）
│   └── build.sh                  # 打包 FPK（版本注入 / install-stamp / 隐私扫描 / checksum）
├── .github/workflows/            # 自动同步工作流（当前未适配本 fork，见"已知限制"）
├── CHANGELOG.md                  # 迭代记录
├── VERSION                       # 当前版本号（唯一真源）
└── .upstream-state               # 上次同步的官方版本与 commit
```

`fpk/cmd/` 生命周期脚本：

| 脚本 | 触发时机 | 主要职责 |
|---|---|---|
| `install_init` / `install_callback` | 安装 | 部署源码、建 venv（CPython 3.14）、装依赖、写 sudoers、初始化配置与技能 |
| `upgrade_init` / `upgrade_callback` | 升级 | 停旧进程、清理 temp/socket、版本比对决定是否重装依赖、detect & 重建旧 venv |
| `config_init` / `config_callback` | 配置变更 | 同步配置 |
| `uninstall_init` / `uninstall_callback` | 卸载 | 停进程；按向导选择保留或删除数据 |
| `main` | 启动/停止 | 拉起 `monitor.js` |

## 部署后的目录结构

`/vol<N>` 取决于安装时选择的存储空间：

```
/vol<N>/@appcenter/hermes-agent/        # 应用目录（TRIM_APPDEST）
├── hermes-src/                         # 上游源码（editable 安装目标）
│   ├── install-stamp.json              # 版本戳：0.22+ 的版本号来源
│   └── hermes_cli/web_dist/            # dashboard 前端产物
├── desktop-app/                        # 桌面端 Web UI
├── server/                             # monitor.js 等
├── config/                             # bootstrap / prompts（技能）/ privilege
├── bin/  cmd/  wizard/  manifest

/vol<N>/@apphome/hermes-agent/          # 数据根（TRIM_PKGHOME）
├── data/                               # DATA_DIR，HOME 也指向这里
│   ├── config.yaml                     # 运行配置（含模型、渠道）
│   ├── sessions/  memories/  skills/  plugins/  logs/  cache/
│   ├── state.db  projects.db           # 会话索引与项目库（SQLite）
│   ├── venv/                           # Python 虚拟环境（CPython 3.14）
│   └── bin/uv                          # 持久化的 uv 二进制
└── uv-python/                          # uv 托管的解释器（cpython-3.14.x）

/vol<N>/@appdata/hermes-agent/          # 日志（TRIM_PKGVAR）
├── info.log                            # 安装/升级日志
├── gateway.log  dashboard.log          # 子进程日志
└── *.pid  dashboard.token
```

## 运行架构

```
浏览器 ──HTTP──> monitor.js (8650) ──┬── /app/hermes-agent/desktop-app/  桌面端 Web UI（静态）
                                     ├── /proxy/dashboard/*            反向代理 → dashboard (127.0.0.1:9219)
                                     ├── /api/app/*                    应用管理 API（版本/修复/更新）
                                     └── unix socket                   包管理器通信
                                              │
                                              ├── gateway 子进程 (ws 8742)  Agent 运行时：模型、工具、会话
                                              └── dashboard 子进程 (9219)   官方设置面板 + RPC
```

几个关键设计：

- **monitor.js 是唯一的常驻 Node 进程**，负责启动/守护两个 Python 子进程（gateway、dashboard），并提供统一 HTTP 入口（免去用户自己开两个端口）
- **桌面端是"Web 化的 Electron 应用"**：官方前端会调用 `window.hermesDesktop.*`（原生能力）。`web-shim.js` 用 Proxy 提供纯浏览器实现（文件选择、剪贴板、连接信息等），并注入汉化字典
- **`custom_routes.js` 与上游解耦**：自定义面板（personas / channels / skills / app-update）出错只影响对应面板，不会拖垮上游的 chat / status 核心路由
- **`install-stamp.json`**：官方 0.22 起 `pyproject` 的 version 固定为 `0.0.0`，版本号只认这个文件；我们分发的是无 `.git` 源码树，缺了它 `hermes --version` 会显示 `unknown`

## 开发与构建

### 环境

- Node.js **22+**（上游 `engines: ^22.22.0`），npm
- Python **3.12+**（仅用于生成 `install-stamp.json`；无则沿用仓库内副本）
- Windows 需要 Git Bash（`build.sh` 用 `sed`/`md5sum`/`tar`），Linux/macOS 直接用 bash
- 磁盘：`upstream/node_modules` 约 1.5 GB

### 步骤

```bash
# 0. 拉取官方目标 tag（必须用 Release tag；main 分支的 pyproject version 恒为 0.0.0）
git clone --depth 1 --branch v0.22.2 https://github.com/NousResearch/hermes-agent.git upstream

# 1. 检测版本 + 预演 / 执行受控合并
node scripts/sync-upstream.js
node scripts/merge-upstream.js            # 预演：看变更规模与"未归类顶层条目"告警
node scripts/merge-upstream.js --write

# 2. 重建两套前端（依赖安装顺序很重要：root → web → apps/desktop）
cd upstream && npm install --workspaces=false \
  && npm install --workspace web && npm install --workspace apps/desktop
cd apps/desktop && npx vite build                         # 桌面端 renderer
cd ../../web     && npx vite build                        # dashboard → ../hermes_cli/web_dist
cd ../..

# 3. 铺产物 + 注入 + 打包
node scripts/desktop-inject-index.js      # viewport / __HERMES_WEB_CONFIG__ / web-shim 注入
bash scripts/build.sh                     # → dist/fnos-hermes-agent_v<版本>.fpk
node scripts/check-bridge-contract.js     # 桥接契约检查（强烈建议）
```

### 产物

- `dist/fnos-hermes-agent_v<版本>.fpk` — 完整安装包（当前发布只有这一种资产）
- `build/<版本>/` — 中间目录（可删）

### 铺设前端产物的两个坑

1. **必须真正清空目标目录**（`assets/`、`ds-assets/`、`emojibase/`、`hermes-frames/`）。
   旧文件没删干净时 `Copy-Item` 会形成新旧混合（曾出现 assets 从 1044 个变成 1873 个文件）
2. **`web-shim.js` 是本项目自维护文件**，清空 `desktop-app/` 前先备份再放回
3. `renderer-manifest.json` 是 Electron 主进程用的，Web 版不需要，不打包

## 上游同步机制

### 版本检测

`scripts/sync-upstream.js` 用 **GitHub Releases API**（按发布时间倒序，过滤 prerelease/draft）定位最新正式版。

> 不要用 `/tags` 判断最新：它按 tag **名字母序**返回，`v0.22.2` 会排在 `v2026.9.24` 之后，
> 取 `per_page=1` 会误判"已是最新"——v0.21.5.1 就是这么误发布的。

### 受控合并

`scripts/merge-upstream.js` 不是整目录覆盖，而是按白名单选择性同步：

- **白名单（`INCLUDE_TOP`）**：`hermes_cli` / `tui_gateway` / `agent` / `gateway` / `providers` / `skills` / `tools` / `plugins` / `cron` / `acp_adapter` / `locales` / `pm` / `hermes_platform` / `plugin-catalog` / `scripts` / 根级 `.py` …
- **黑名单（`EXCLUDE_TOP`）**：`apps`（桌面端源码，只取构建产物）/ `web` / `website` / `docs` / `tests` / `evals` / `assets` / `native` / `.github` / `ui-tui` …
- **未归类目录会告警**：既不在白也不在黑名单的顶层目录会被打印出来，防止官方新增运行时包时被静默漏拷（`pm` / `hermes_platform` / `plugin-catalog` 就是这么发现的）
- **移植修改默认保留**：`PORT_OVERRIDES` 记录我们对上游文件做的必要改动，合并时不会被官方覆盖

### 本项目自己维护的文件（不随上游更新）

| 文件 | 作用 |
|---|---|
| `app/desktop-app/web-shim.js` | Electron 桥接的浏览器实现 + 汉化字典 |
| `app/desktop-app/index.html` | 注入视图配置与 shim 引用（由脚本生成） |
| `app/server/monitor.js`、`custom_routes.js`、`connectors.js` | fnOS 侧的进程管理与自定义面板 |
| `app/config/*`、`fpk/**` | 应用包骨架、生命周期脚本、向导、技能 |
| `scripts/**` | 构建与同步脚本 |

### 同步后的检查清单

1. `node scripts/check-bridge-contract.js` — 官方新增的 `hermesDesktop.*` 属性是否都登记了（**新增"数据属性"未登记会白屏**）
2. 扫一遍 import：上游有、本项目缺、但代码在 import 的顶层包 → 必崩
3. 新增依赖是否带 `python_version >= '3.14'` 之类标记 → 影响解释器版本要求
4. 前端是否重建（只更新后端不更新前端，容易出新版 API 与旧版 UI 不匹配）
5. 真机跑一次：安装 → 打开主界面 → 进设置页 → `hermes --version`

## 排障（FAQ）

### 打开界面显示 "Something broke in the interface"

先看 Details 里的报错文案。

- **`(e ?? "").trim is not a function`**：`web-shim.js` 的 Proxy 兜底把某个**数据属性**返回成了函数，
  前端对它做字符串操作。修复方式：在 `web-shim.js` 的 `core` 里显式给出正确空值（对象给 `null`），
  并跑 `node scripts/check-bridge-contract.js` 找其他同类隐患。0.22.2 的 `localSkin` 就是这个原因。
- **其他报错**：浏览器 F12 看 Console 第一条红色错误，结合 `gateway.log` / `dashboard.log` 一起看。

### 网关起不来：`ModuleNotFoundError: No module named 'ruamel'`

解释器版本不对。官方 0.22+ 要求 **Python 3.14**，而飞牛系统 `python3` 是 3.11.2
（46 个依赖带 `>=3.14` 标记，3.11 下一个都不装）。检查：

```bash
hermes --version          # 看 Python: 是否为 3.14.x
```

不是 3.14 就重装 v0.22.2.2 及以后的包（会自动重建 venv）。手工排查：

```bash
ls /vol<N>/@apphome/hermes-agent/uv-python/     # 应有 cpython-3.14.*
/vol<N>/@apphome/hermes-agent/data/venv/bin/python3 -V
```

### 网关起不来：`NameError: name 'Path' is not defined` / `_flush_sessions_before_exit`

同上是 3.11 的表现（PEP 649 惰性注解求值在 3.14 才默认启用），不是代码缺文件。升级解释器即可。

### 升级完了但功能没变化

多半是依赖没重装。检查包内 `config/bootstrap/hermes-version.env` 的 `HERMES_VERSION`
是否等于当前官方版本（低于已装版本时，`install_callback` 会跳过 `uv pip install`）。
v0.21.3.1 正式包里这个值是 `0.21.1`，属于已修复的历史缺陷。

### 应用中心提示不能安装 / 同版本不可重装

飞牛不允许同版本号覆盖，必须用**迭代号更大**的包（如 `0.22.2.3` → `0.22.2.4`）。

### 端口被占用

`8650 / 8742 / 9219` 任一被占用都会启动失败。查占用：

```bash
ss -lntp | grep -E '8650|8742|9219'
```

停掉冲突进程，或用 `POST /api/app/repair` 重启应用内服务。

### 一键重启网关与 dashboard

```bash
curl -X POST http://<NAS-IP>:8650/api/app/repair
```

### 强制重建 venv

```bash
sudo systemctl stop 应用 || true          # 或在应用中心停止应用
rm -rf /vol<N>/@apphome/hermes-agent/data/venv
# 再启动应用，install_callback/upgrade_callback 会自动重建
```

### 日志在哪

| 日志 | 路径 |
|---|---|
| 安装/升级 | `${TRIM_PKGVAR}/info.log` |
| 网关 | `${TRIM_PKGVAR}/gateway.log` |
| dashboard | `${TRIM_PKGVAR}/dashboard.log` |

## 已知限制

1. **CI 自动发布未适配本 fork**：`.github/workflows/sync-upstream.yml` 里的 remote 与 Release API 仍指向原作者仓库，且依赖从上一 Release 提取 `venv-bundle.tar.gz`（本 fork 无 Release）。当前发布方式是本地构建 + 应用中心手动上传
2. **增量更新链路未验证**：`monitor` 的 `/api/app/hot-patch` 与 `incremental-*.tar.gz` 设计存在，但需要上一 Release 存在，实际未走通；升级请用完整 FPK
3. **汉化覆盖不全**：汉化字典基于 0.21.x 界面文案，官方改动过的字符串可能不再命中，表现为个别位置仍是英文（不影响功能）
4. **旧版控制台 `app/ui/`** 保留但非主要入口，其中 `_check*.js`、`fix*.mjs` 是历史调试文件
5. **首次安装强依赖外网**：CPython 3.14 与依赖都需从公网下载，纯内网环境需自备代理或内置 venv

## 隐私与安全

- 本仓库**不含**任何个人数据：无密码、token、内网 IP、NAS 路径或个人信息
- `bash scripts/build.sh` 内置隐私扫描，命中即中止打包
- 部署时的真实配置（如 `GITHUB_REPO` 等）通过环境变量注入，源码内仅保留匿名占位
- 应用以独立用户 `hermes-agent` 运行（`privilege` 中 `run-as: package`），安装时写入最小化 sudoers 以支持自管理
- 8650 端口对局域网开放且未加额外认证，**请勿直接暴露公网**

## 免责声明

本应用仅为服务集成与打包工具，不对 Hermes Agent 软件本身的安全性、稳定性作任何担保。
使用过程中产生的风险由使用者自行承担。上游问题请反馈至
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)。

## 相关链接

- 上游：[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)
- 本仓库原作者：[veenyi/fnos-hermes-agent-web](https://github.com/veenyi/fnos-hermes-agent-web)
- 变更记录：[CHANGELOG.md](./CHANGELOG.md)
