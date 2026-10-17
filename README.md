# fnos-hermes-agent-web

飞牛 fnOS 上的 Hermes Agent 桌面端 Web 版。基于官方 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) 集成，提供 fnOS 应用中心安装包（FPK）、桌面端 Web UI 汉化、飞牛管理技能（trim-cli）与 GitHub 增量更新。

## 版本号机制

版本号 = **官方版本 + 迭代号**（`<官方版本>.<迭代>`），release tag 格式 `v<版本>`：

- 当前官方版本 `0.22.2` → 本项目 `0.22.2.3`
- 官方升级到 `0.22.3` → 本项目从 `0.22.3.1` 重新开始迭代
- 同一官方版本内每次重新打包，迭代号 +1（`0.22.2.3` → `0.22.2.4`）——
  飞牛应用中心不允许同版本号重装

每次迭代的详细过程（现象 / 根因 / 修复 / 验证 / 遗留）见 **[CHANGELOG.md](./CHANGELOG.md)**。

## 仓库结构

```
fnos-hermes-agent-web/
├── app/                    # 完整应用源码树（与部署端一致，自包含可运行）
│   ├── server/             # Node 后端（monitor.js / custom_routes.js / connectors.js 等）
│   ├── desktop-app/        # 桌面端 Web UI（官方 dist + web-shim 汉化层/移动端适配）
│   ├── ui/                 # 旧版控制台页面
│   ├── hermes-src/         # Hermes Agent 上游源码（vendored，含自定义配置）
│   └── config/             # fnOS 应用配置（bootstrap / privilege）
├── src/                    # 编译前的自定义修改源文件（供对照/重新构建）
│   ├── server/             # monitor.js 等 Node 后端
│   └── desktop-app-*.js    # 桌面端 Web UI 自定义（web-shim 汉化层/移动端适配）
├── scripts/                # 构建与发布脚本
│   ├── sync-upstream.js    # 检测官方最新 Release → 更新 VERSION / .upstream-state
│   ├── merge-upstream.js   # 受控合并 upstream/ → app/hermes-src（白名单 + 未归类告警）
│   ├── desktop-inject-index.js  # 给官方 dist/index.html 注入 viewport / 配置 / web-shim
│   ├── check-bridge-contract.js # 桥接契约检查（防 Proxy 兜底导致白屏）
│   └── build.sh            # 编译打包 FPK（含 install-stamp / 版本注入 / 隐私扫描）
├── CHANGELOG.md            # 迭代记录（每次改动的根因与验证）
├── fpk/                     # FPK 打包骨架（manifest/cmd/config/ICON/wizard/技能）
├── VERSION                 # 当前版本号
└── .github/workflows/      # GitHub Actions 自动同步/编译/发布
```

`app/` 为完整可部署源码树（不含 venv 与运行时数据）；`src/` 为汉化/自定义修改的源文件集合，两者内容一致时以 `app/` 为准。

## 增量更新机制

设计上每次发布包含三类资产：

1. **`fnos-hermes-agent_v0.22.2.3.fpk`** — 完整安装包（全新安装 / 跨大版本）
2. **`incremental-v0.22.2.2-to-v0.22.2.3.tar.gz`** — 增量包（相对上一迭代变更的文件）
3. **`hot-patch.json`** — 更新元数据（base_version / version / 文件清单 / checksum）

monitor 的 `/api/app/hot-patch` 检测到 `hot-patch.json` 时，下载增量 tar 解压到应用目录，
更新版本号后自重启，无需全量重装。

> **当前状态**：该链路尚未走通验证（见 CHANGELOG 附录 C）。目前实际升级路径是
> 飞牛应用中心覆盖安装完整 `.fpk`；增量包依赖上一 Release 存在，而本 fork 暂无 Release。

## 本地构建

```bash
# 0. 拉取官方目标 tag（必须用 Release tag，main 的 pyproject version 恒为 0.0.0）
git clone --depth 1 --branch v0.22.2 https://github.com/NousResearch/hermes-agent.git upstream

# 1. 检测版本 + 预演 / 执行受控合并
node scripts/sync-upstream.js
node scripts/merge-upstream.js            # 预演：看规模与"未归类顶层条目"告警
node scripts/merge-upstream.js --write

# 2. 重建两套前端（依赖安装顺序：root → web → apps/desktop）
cd upstream && npm install --workspaces=false \
  && npm install --workspace web && npm install --workspace apps/desktop
cd apps/desktop && npx vite build && cd ../../web && npx vite build && cd ../..

# 3. 铺产物 + 注入 + 打包
node scripts/desktop-inject-index.js
bash scripts/build.sh                     # 产出 dist/fnos-hermes-agent_v<版本>.fpk
node scripts/check-bridge-contract.js     # 桥接契约检查
```

发布方式：本地构建后用飞牛应用中心「手动安装」上传 `.fpk`。
（`appcenter-cli install` 只能从应用中心拉包，不支持本地文件路径。）

## 上游同步

自动检测官方 hermes-agent 新版本：

- 官方代号变化（如 0.24.4 → 0.24.5）→ 全新同步 + 迭代 V01
- 官方代号不变 → 仅本地增量（迭代 +1）

## 隐私声明

本仓库**不含**任何个人数据：无密码、token、内网 IP、NAS 路径或个人信息。打包前自动执行隐私扫描，确保零残留。部署时通过环境变量注入真实配置（如 `GITHUB_REPO`），源码内仅保留匿名占位值。
