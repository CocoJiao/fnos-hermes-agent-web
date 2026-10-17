# 迭代记录

记录每次迭代的完整过程：**改了什么、为什么改、怎么定位、怎么验证、遗留什么**。
新版本在上。每条记录都应能被后来者独立复现，不依赖当时的会话上下文。

版本号规则：`<官方版本>.<迭代号>`，例如官方 `v0.22.2` → 本项目 `0.22.2.3`；
同版本号不可在飞牛应用中心重装，因此只要重新打包就必须 +1 迭代号。

---

## v0.22.2.3 — 2026-10-17 — 修复 0.22.2 整页白屏

### 背景

v0.22.2.2 在飞牛上装好后，网关与 dashboard 均已正常启动（见 v0.22.2.2 记录），
但浏览器打开桌面端仍然显示错误页：

```
Something broke in the interface
The view hit an unexpected error. Your chats and settings are safe.
Details: (e ?? "").trim is not a function
```

v0.22.2.2 的结论曾把这条错误判为"后端崩溃的次生现象"，该判断是**错的**——
后端修好后它依然稳定复现，属于独立的真实缺陷。

### 定位过程

1. 用 CDP（Chrome DevTools Protocol）打开页面抓事件，得到两条线索：
   - `TypeError: (e ?? "").trim is not a function`
   - `/proxy/dashboard/api/app/update/check` 返回 **409**（`GITHUB_REPO` 未配置的正常提示，与崩溃无关，属干扰项）
2. 注入 `console.error` 钩子拿到错误对象堆栈，精确定位到：

   ```
   TypeError: (e ?? "").trim is not a function
       at w  (assets/profile-DsyCYHlW.js:1:9303)
       at an (assets/context-BRCtUBSa.js:1:22122)
   ```
3. 还原压缩代码，崩溃函数是 profile 名归一化：

   ```js
   function w(e){ return (e ?? ``).trim() || `default` }   // 没有 String() 包裹
   ```
4. 用 `Object.prototype.trim` 兜底探针（把对象 trim 记录下来再转字符串）：
   - 加上兜底后**页面立刻完全正常**，证明就是"对象/函数被当字符串"
   - 打印出被 trim 的对象：`ctor: "Function"`、`tag: "[object Function]"`、`keys: ["toString"]`
   - 调用栈指向 `context-BRCtUBSa.js:1:12857`，该行是：

     ```js
     He = (Ve?.name ?? ``).trim() || null,
     Ue = He ? (Be?.profile ?? ``).trim() || `default` : null,
     // Be = window.hermesDesktop?.localSkin ?? null
     ```
5. 运行时读取 `typeof window.hermesDesktop.localSkin` → **`function`**（本应是对象或 null）。

### 根因

`app/desktop-app/web-shim.js` 用 **Proxy** 模拟 Electron 主进程注入的
`window.hermesDesktop`：

```js
var proxied = new Proxy(core, {
  get: function (obj, prop) {
    if (prop in obj) return obj[prop];
    if (prop in nested) return nested[prop];
    if (/^on[A-Z]/.test(prop)) return function () { return function () {}; };
    return makeFallback();          // ← 未登记属性一律返回"万能函数"
  },
});
```

官方 0.22.2 新增读取 `hermesDesktop.localSkin`（Electron 主进程写入
`{ skin, profile }` 对象），web 模式下没有对应登记 → 拿到兜底函数 →
`.profile.trim()` 不存在 → `ThemeProvider` 抛错 → 根 error boundary 接住 →
整页白屏。

**这类问题的通用特征**：官方新增一个"数据属性"（对象/字符串/布尔/数值），
而 shim 的兜底只会返回函数，前端一旦对它做字符串或对象操作就崩。

### 修复

| 文件 | 改动 |
|---|---|
| `app/desktop-app/web-shim.js` | core 里显式声明 `localSkin: null`，并注释说明原因 |
| `app/desktop-app/index.html` | `web-shim.js?v=54` → **`v=55`**，强制丢弃浏览器里的旧 shim 缓存 |
| `scripts/desktop-inject-index.js` | 注入模板同步为 `v=55`（重建前端后不会退回 v54） |
| `scripts/check-bridge-contract.js` | **新增**：扫描官方前端源码，列出所有 `window.hermesDesktop.*` 属性访问，与 shim 显式键做差集，提示哪些还在走兜底 |

### 为什么其余缺失属性不一起补

扫出 131 个属性，shim 显式提供 107 个键，仍有 75 个走兜底。逐个核对源码后**故意保留**：

- `glassSupported` / `translucencySupported`：源码是
  `typeof window.hermesDesktop?.glassSupported === 'boolean' ? ... : UA 判断` → 走兜底只降级不回崩
- `localModelsEnabled`：源码是 `=== true` 判断 → 函数不匹配即 false，安全
- `profile`：`store/profile.ts:283` 有一处**无 optional chaining** 的
  `await window.hermesDesktop.profile.set(name)`，设成 `null` 会直接 TypeError；
  保持兜底函数反而能安全吞掉
- 大量 `onXxx` 事件订阅、`setXxx` 命令：兜底返回函数正是期望行为

### 验证

- 用 CDP **禁用缓存**加载 `http://<nas>:8650/app/hermes-agent/desktop-app/`，
  页面正常渲染：会话 / 机器人 / 新建会话 / 技能与工具 / 消息平台 / 产物 / 定时任务，
  左侧会话列表正常列出，无 error boundary
- 修复前后对照：同一套 CDP 探针，修复前 `document.body.innerText` 只有错误页文案，
  修复后是完整界面
- 包内容校验：`app.tgz` 内 `web-shim.js` 含 `localSkin`，`index.html` 为 `v=55`

### 影响面与遗留

- 影响：仅桌面端 Web UI 首屏；dashboard（9219）不受影响
- 遗留：汉化字典（`web-shim.js` 的 `DICT`）基于 0.21.x 的 UI 文案，0.22.2 改动过的
  文案可能不再命中，属"少翻译几句"，不会崩
- 遗留：`localStorage` 里大量 `hermes.desktop.*` 键（Electron 版遗留）目前不影响运行；
  已验证清空 storage 后行为一致

---

## v0.22.2.2 — 2026-10-17 — venv 改用 CPython 3.14

### 背景

v0.22.2.1 装到飞牛后网关起不来，日志：

```
ModuleNotFoundError: No module named 'ruamel'
tui_gateway/methods_onboarding.py:71: NameError: name 'Path' is not defined
tui_gateway/server.py:395: NameError: name '_flush_sessions_before_exit' is not defined
```

### 根因（两层，缺一不可）

1. **依赖层面**：官方 `pyproject.toml` 里 46 个核心依赖（openai / httpx / pydantic /
   fastapi / uvicorn / websockets / ruamel.yaml / croniter / jinja2 …）都带
   `; python_version >= '3.14'` 标记。飞牛系统 `python3` 是 **3.11.2**，
   这些依赖**一个都不会安装**，`pip show hermes-agent` 的 `Requires:` 甚至是空的。
2. **语言层面**：即使强行补装依赖，0.22.x 代码依赖 **PEP 649 惰性注解求值**
   （Python 3.14 默认启用）。3.11 下 `def f() -> tuple[Path, ...]` 会在**定义时**求值，
   遇到未导入的名字立刻 `NameError` —— 这就是上面两个 NameError 的来源，
   不是合并漏文件（已核对与上游 tag 逐字节一致）。

用 `ast.parse(feature_version=(3,11))` 扫了 2496 个 py 文件，语法层面 0 错误，
说明不是"3.12 语法"问题，纯粹是注解求值时机 + 依赖标记。

### 修复

`fpk/cmd/install_callback` 与 `fpk/cmd/upgrade_callback`：

```sh
HERMES_PY_SPEC="3.14"
export UV_PYTHON_INSTALL_DIR="${DATA_DIR}/uv-python"   # uv 托管的解释器放数据盘
export UV_LINK_MODE="copy"                              # 跨文件系统避免 hardlink 失败
"$UV" venv --python "${HERMES_PY_SPEC}" "${VENV_DIR}"   # 首次自动下载约 35MB
```

- 创建后**校验 `python >= 3.14`**，不满足直接 `toast_err` 退出，
  不再产出"能装但不能用"的环境
- `upgrade_callback` 额外检测**已有 venv** 的解释器版本：低于 3.14 就重建
  （0.21.x 老用户升级必须触发，否则升级完网关照样起不来）

### 验证（飞牛真机）

```
Hermes Agent v0.22.2 (2026.9.24) · upstream d923a5eb
Python: 3.14.7
OpenAI SDK: 2.24.0
HERMES_DASHBOARD_READY port=9219
```

`/api/app/repair` 后 gateway + dashboard 双双正常启动，无 Traceback。

### 代价与风险

- 首装需要联网下载 CPython 3.14（实测 34.3MiB / 40 秒，从 python-build-standalone 拉取）
- 下载失败则安装失败（**这是有意的**：宁可装不上，也不要装出一个跑不起来的环境）
- 解释器放在 `${DATA_DIR}/uv-python`，升级/重装应用不丢，不必反复下载

---

## v0.22.2.1 — 2026-10-17 — 同步上游 v0.22.2（首次）

### 内容

- `scripts/sync-upstream.js`：版本检测从 `/tags` 改为 `/releases`
  （`/tags` 按 tag **名字母序**返回，`v0.22.2` 排在 `v2026.9.24` 之后，
  取 `per_page=1` 会误判"已是最新"——这正是 v0.21.5.1 误发布的原因）；
  版本优先取 tag 名，其次 pyproject，最后 `hermes_cli.__version__`
- `scripts/merge-upstream.js`：
  - 白名单补 `pm` / `hermes_platform` / `plugin-catalog` —— 0.22 新增的运行时包。
    `pm` 被引用 182 处（`hermes_cli/version_info.py` 依赖 `pm.paths`），
    漏了就是网关启动即 `ModuleNotFoundError`
  - 新增"未归类顶层条目"告警：白名单/黑名单都没覆盖的顶层目录会打印出来，
    防止官方以后再加目录时被静默漏拷
  - 版本记录改为 tag → pyproject → `__version__` 三级
- `scripts/build.sh`：新增 `install-stamp.json` 生成。官方 0.22 起
  `pyproject` 的 version 固定为 `0.0.0`，版本只认这个文件；我们分发的是无 `.git`
  的源码树，缺了它 `hermes --version` 显示 `unknown`
- 前端重建：`apps/desktop`（vite，15655 模块）+ `web`（dashboard，输出到
  `hermes_cli/web_dist`）
- 资源集变化：官方移除 `intro-nous-girl.png` / `nous-badge.png` / `nous-girl.jpg`，
  改 `nous-girl.png` / `nous-girl-dark.png` —— 整个目录清空重铺，避免新旧混杂

### 合并规模

更新 1685 个文件、新增 1205 个、跳过桌面端 13631 个。
另跑了 import 完整性检查（扫 428 个顶层 import），唯一缺失的 `apps` 是桌面端打包脚本
引用，运行时不需要，属预期排除。

### 打包脚本的两处修正

- `venv-bundle.tar.gz` 改为**可选**：v0.21.3.1 正式包里根本没有这个文件
  （安装时用包内 uv 在线装），原先的强制校验会让本地构建直接失败
- `HERMES_VERSION` 由 `VERSION` 前三段自动派生，并同时纠正
  `app/config` 与 `fpk/config` 两份 `hermes-version.env`。
  原先 `app/config` 里写死 `0.21.1`，会被 `install_callback` 判定
  "已装版本 > 目标版本" → **跳过 uv pip install**，新依赖永远装不上。
  （原作者发布的 v0.21.3.1 正式包就是这个值，等于每次升级都跳过依赖安装）

---

## v0.21.5.1 — 2026-10-17 — 中间版本（已作废，请勿使用）

- 同步到 `v2026.9.24`（官方 0.21.5），两套前端重建，包已生成并打 tag
- **作废原因**：当时用 `/tags?per_page=1` 判断"最新"，拿到的是按字母序排第一的
  `v2026.9.24`，而真实发布线已经走到 `v0.22.2`，整条 0.22 线被漏掉
- 该 tag 保留在 git 历史中仅作追溯，**发布/安装请用 v0.22.2.3 及以后**

---

## v0.21.3.1 — 基线（原作者版本）

本次迭代的起点。已知问题（本次逐条修掉）：

1. `app/config/bootstrap/hermes-version.env` 写死 `HERMES_VERSION=0.21.1`
2. `build.sh` 强制要求不存在的 `fpk/venv-bundle.tar.gz`
3. `scripts/sync-upstream.js` 从 `pyproject.toml` 读版本（官方已固定 `0.0.0`）
4. 合并白名单不含 0.22 新增的运行时包
5. venv 用系统 `python3`（3.11.2），与 0.22+ 要求不符

---

## 附录 A：同步上游的标准流程

```bash
# 0) 确认官方最新正式版（必须用 releases，不要用 tags）
gh api 'repos/NousResearch/hermes-agent/releases?per_page=5' --jq '.[].tag_name'

# 1) 克隆目标 tag（不要用 main：main 的 pyproject version 恒为 0.0.0）
rm -rf upstream
git clone --depth 1 --branch <tag> https://github.com/NousResearch/hermes-agent.git upstream

# 2) 更新版本号 + 预演合并（看规模与"未归类顶层条目"告警）
node scripts/sync-upstream.js
node scripts/merge-upstream.js

# 3) 实际合并
node scripts/merge-upstream.js --write

# 4) 检查 import 完整性（上游有、我们缺、但代码在 import 的包）
node <临时脚本>   # 逻辑见 v0.22.2.1 记录；漏同步会直接 ModuleNotFoundError

# 5) 重建两套前端（依赖要先装：root → web → apps/desktop，web 提供 lucide-react 的提升依赖）
cd upstream && npm install --workspaces=false && npm install --workspace web && npm install --workspace apps/desktop
cd apps/desktop && npx vite build          # 桌面端 renderer
cd ../../web   && npx vite build           # dashboard → ../hermes_cli/web_dist

# 6) 铺产物 + 注入 + 打包
node scripts/desktop-inject-index.js       # viewport / WEB_CONFIG / web-shim 注入
bash scripts/build.sh

# 7) 检查桥接契约（0.22 白屏事故的防复发检查）
node scripts/check-bridge-contract.js
```

### 前端产物铺设的坑

- 复制前必须**真正清空**目标目录（`assets/`、`ds-assets/`、`emojibase/`、`hermes-frames/`）。
  若旧文件没删干净，`Copy-Item` 会形成新旧混合（曾出现 assets 从 1044 变 1873 个文件）
- 桌面端的 `web-shim.js` 是**本项目自维护**文件，清空目录前要先备份再放回
- `renderer-manifest.json` 是 Electron 主进程用的，Web 版不需要，不打包

---

## 附录 B：官方 0.22.x 的环境事实（写给后来者）

| 项 | 事实 | 影响 |
|---|---|---|
| Python 要求 | 实际 **3.14**（`requires-python` 写 `>=3.11,<3.15` 但依赖全带 3.14 标记） | 必须用 uv 托管解释器 |
| 版本号来源 | `pyproject` 恒为 `0.0.0`，真实版本在 `install-stamp.json` / tag | 打包必须生成 stamp |
| 发布线 | 语义化 tag（`v0.22.2`），旧的 `v2026.9.x` 是历史命名 | 别用 tags API 判断最新 |
| 运行时新包 | `pm` / `hermes_platform` / `plugin-catalog` | 合并白名单必须含 |
| 桌面端桥接 | 新增 `localSkin` 等**数据属性** | shim 必须显式登记，否则 Proxy 兜底返回函数 → 白屏 |

---

## 附录 C：已知遗留（尚未处理）

1. **CI workflow 跑不通**：`.github/workflows/sync-upstream.yml` 里 git remote 与
   Release API 仍指向原作者 `veenyi`，且要求从上一 Release 提取
   `venv-bundle.tar.gz`（本 fork 没有任何 Release）。目前发布走本地构建 + 应用中心手动上传。
2. **汉化覆盖不全**：`web-shim.js` 的 `DICT` 基于 0.21.x 文案，0.22.2 改动过的字符串
   可能不再命中，表现为个别位置仍是英文。
3. **增量更新机制未验证**：README 描述的 `hot-patch.json` 增量更新链路本次未走通验证，
   实际升级用的是应用中心覆盖安装。
4. **`up-monitor-repo.b64`（801KB）** 用途不明，暂未清理，先记录在此。
