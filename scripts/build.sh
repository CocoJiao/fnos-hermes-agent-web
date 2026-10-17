#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# fnos-hermes-agent-web 构建脚本
# 产出（放入 dist/）：
#   1. fnos-hermes-agent_v<ver>.fpk          完整安装包（含内置 venv，全新安装用）
#   2. incremental-<prev>-to-<cur>.tar.gz    增量更新包（tar 解压）
#   3. hot-patch.json                        更新元数据
#
# 依赖：
#   - app/                 本地维护树（server/desktop-app/hermes-src/ui/config，含全部修复）
#   - fpk/                 FPK 骨架（manifest/cmd/config/ICON/wizard）
#   - venv-bundle.tar.gz   内置 venv（从已有部署提取，放 fpk/）
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── 版本解析 ────────────────────────────────────────────────────────
CUR_VERSION="$(cat VERSION | tr -d '[:space:]')"
OFFICIAL_VER="$(echo "$CUR_VERSION" | cut -d. -f1-3)"
BUILD_NUM="$(echo "$CUR_VERSION" | awk -F. '{print $NF}')"

# 上一版本（从 git tag 取最近的非当前 tag）
PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
if [ "$PREV_TAG" = "v$CUR_VERSION" ]; then
  # 当前版本已是 tag（可能是手动构建），用 git log 找上一个 tag
  PREV_TAG="$(git tag --sort=-creatordate | grep -v "^v$CUR_VERSION$" | head -1 || echo "")"
fi
PREV_VERSION="${PREV_TAG#v}"
PREV_VERSION="${PREV_VERSION:-}"

echo "═══ 构建 fnos-hermes-agent $CUR_VERSION ═══"
echo "官方版本: $OFFICIAL_VER | Build: $BUILD_NUM | 上一版: ${PREV_VERSION:-无}"

# ── 目录 ────────────────────────────────────────────────────────────
DIST="dist"
BUILD_DIR="build/$CUR_VERSION"
mkdir -p "$DIST" "$BUILD_DIR"

# ── 前置校验（缺核心组件直接中止，禁止产出残次包）──────────────────
[ -d "app/server" ]      || { echo "✗ 缺少 app/server" >&2; exit 1; }
[ -d "app/desktop-app" ] || { echo "✗ 缺少 app/desktop-app" >&2; exit 1; }
[ -d "app/hermes-src" ]  || { echo "✗ 缺少 app/hermes-src（含本地修复，必须存在）" >&2; exit 1; }
[ -f "app/hermes-src/hermes_cli/web_dist/index.html" ] || { echo "✗ 缺少 app/hermes-src/hermes_cli/web_dist（dashboard 无 npm 环境必须随包分发构建产物，缺失会导致网关连不上）" >&2; exit 1; }
# venv-bundle 可选：v0.21.3.1 起的正式包不含内置 venv（安装时用包内 uv 在线 editable 安装，
# install_callback 已实现多源重试）；有内置 venv 时安装更快，无则不影响可用性。
if [ -f "fpk/venv-bundle.tar.gz" ]; then
  echo "✓ 检测到内置 venv（fpk/venv-bundle.tar.gz），安装时将免在线安装"
else
  echo "○ 无内置 venv，安装时走在线 uv 安装（与 v0.21.3.1 正式包一致）"
fi
[ -d "fpk/cmd" ]         || { echo "✗ 缺少 fpk/cmd" >&2; exit 1; }
[ -f "fpk/config/bootstrap/hermes-version.env" ] || { echo "✗ 缺少 fpk/config/bootstrap/hermes-version.env" >&2; exit 1; }
echo "✓ 前置校验通过"

# ── 隐私扫描（强制）─────────────────────────────────────────────────
echo "── 隐私扫描 ──"
PRIV_LEAKS="$(grep -rnE 'password[=:][^ ]{4,}|token[=:][A-Za-z0-9_\-.]{12,}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|/vol[0-9]+/@app(home|data)/|sk-[A-Za-z0-9]{20}' app/ fpk/config/ 2>/dev/null | grep -vE '\.pyc|node_modules|app_version|password[:=](password|true|false)|token[:=](token|true|false)' | head -20 || true)"
if [ -n "$PRIV_LEAKS" ]; then
  echo "✗ 隐私扫描发现泄漏："
  echo "$PRIV_LEAKS"
  exit 1
fi
echo "✓ 隐私扫描通过"

# ── 组装应用目录（完整包内容，统一从 app/ 维护树取）────────────────
echo "── 组装应用目录 ──"
APP_STAGE="$BUILD_DIR/app"
rm -rf "$APP_STAGE"
mkdir -p "$APP_STAGE"

# 1. server（后端 monitor/routes 等）
cp -r app/server "$APP_STAGE/server"

# 2. desktop-app（桌面端 Web：web-shim/index/assets，整目录含 i18n）
cp -r app/desktop-app "$APP_STAGE/desktop-app"

# 3. hermes-src（本地维护树，含全部修复；官方上游更新经 sync-upstream 合并进来）
cp -r app/hermes-src "$APP_STAGE/hermes-src"
echo "✓ hermes-src 已带入（本地维护树）"

# 3.1 install-stamp.json —— 官方 0.22 起版本号只认这个文件
#     （pyproject 固定 0.0.0，且我们分发的是无 .git 的源码树）。
#     缺了它 `hermes --version` 会显示 unknown，前端「关于」也拿不到版本。
#     用官方脚本按当前版本重新生成；无 python 时沿用源码树里的副本。
PYBIN=""
# 注意：Windows 的 Git Bash 里 python3 常指向 Microsoft Store 占位符（能 command -v 到但执行即失败），
# 所以必须用 -c "import sys" 真跑一次才算可用；顺序也优先 python 再 python3。
for _cand in python python3; do
  if command -v "$_cand" >/dev/null 2>&1 && "$_cand" -c "import sys" >/dev/null 2>&1; then
    PYBIN="$_cand"; break
  fi
done
STAMP_SCRIPT="$APP_STAGE/hermes-src/scripts/write_install_stamp.py"
if [ -n "$PYBIN" ] && [ -f "$STAMP_SCRIPT" ]; then
  UPS_SHA="$(sed -n 's/^PREV_SHA="\(.*\)"/\1/p' .upstream-state 2>/dev/null || true)"
  if STAMP_OUT="$("$PYBIN" "$STAMP_SCRIPT" \
      --output "$APP_STAGE/hermes-src/install-stamp.json" \
      --base-version "$OFFICIAL_VER" --distance 0 \
      ${UPS_SHA:+--commit "$UPS_SHA"} \
      --source build --update-mechanism external 2>&1)"; then
    echo "✓ install-stamp.json 已生成（base=$OFFICIAL_VER）"
  else
    echo "⚠ install-stamp.json 生成失败，沿用源码树内的副本：$(echo "$STAMP_OUT" | tail -2 | tr '\n' ' ')"
  fi
else
  echo "○ 无可用 python 或缺少 write_install_stamp.py，沿用源码树内的 install-stamp.json"
fi

# 4. ui（dashboard 前端，可选）
if [ -d "app/ui" ]; then
  cp -r app/ui "$APP_STAGE/ui"
  echo "✓ ui 已带入"
fi

# 5. config（bootstrap/privilege/resource 随 app.tgz——
#    install_callback 检查 APP_DIR/config/bootstrap/hermes-version.env）
if [ -d "app/config" ]; then
  cp -r app/config "$APP_STAGE/config"
  echo "✓ config 已带入 app.tgz"
fi
# 5.0 版本注入：HERMES_VERSION 必须等于 VERSION 前三段。
#     否则 install_callback 里 "已装版本 > 目标版本 → SKIP_INSTALL" 会让升级跳过
#     uv pip install（editable 源码虽即时生效，但新增依赖不会补装 → 运行时 ModuleNotFoundError）。
HV="$APP_STAGE/config/bootstrap/hermes-version.env"
if [ -f "$HV" ]; then
  sed -i "s/^HERMES_VERSION=.*/HERMES_VERSION=${OFFICIAL_VER}/" "$HV"
  echo "✓ HERMES_VERSION → ${OFFICIAL_VER}"
else
  echo "✗ 缺少 config/bootstrap/hermes-version.env，install_callback 会直接失败" >&2
  exit 1
fi
# 骨架里的同名文件同步一份，避免两处漂移
if [ -f "fpk/config/bootstrap/hermes-version.env" ]; then
  sed -i "s/^HERMES_VERSION=.*/HERMES_VERSION=${OFFICIAL_VER}/" fpk/config/bootstrap/hermes-version.env
fi

# 5.1 config/prompts（config.yaml 模板 + skills）——fnOS 只处理外层 config 的
#     bootstrap/privilege/resource，prompts 必须随 app.tgz 解压
if [ -d "fpk/config/prompts" ]; then
  mkdir -p "$APP_STAGE/config/prompts"
  cp -r fpk/config/prompts/. "$APP_STAGE/config/prompts/"
  echo "✓ config/prompts 已带入 app.tgz"
fi

# 6. 版本写入
echo "$CUR_VERSION" > "$APP_STAGE/VERSION"
if [ -f "fpk/manifest" ]; then
  sed -i "s/^version.*=.*/version               = $CUR_VERSION/" fpk/manifest
fi

# ── 组装完整 FPK ────────────────────────────────────────────────────
echo "── 打包完整 FPK ──"
# FPK 结构：manifest + app.tgz + cmd + config + ICON + LICENSE + wizard
# app.tgz = 应用部署目录（server/desktop-app/hermes-src/ui/config + venv-bundle.tar.gz）
  # 生成 app.tgz（含 venv-bundle）
  APP_TGZ_STAGE="$BUILD_DIR/fpk-app"
  rm -rf "$APP_TGZ_STAGE"
  mkdir -p "$APP_TGZ_STAGE"
  cp -r "$APP_STAGE"/* "$APP_TGZ_STAGE/" 2>/dev/null || true
  VENV_SRC="fpk/venv-bundle.tar.gz"
  if [ -f "$VENV_SRC" ]; then
    cp "$VENV_SRC" "$APP_TGZ_STAGE/"
    echo "✓ 内置 venv 已带入（$(du -sh "$VENV_SRC" | cut -f1)）"
  else
    echo "○ 跳过内置 venv（包内不含 venv-bundle.tar.gz）"
  fi
  # 打包 app.tgz
  tar czf "$BUILD_DIR/app.tgz" -C "$APP_TGZ_STAGE" . 2>/dev/null

  # 组装 FPK
  FPK_STAGE="$BUILD_DIR/fpk-out"
  rm -rf "$FPK_STAGE"
  mkdir -p "$FPK_STAGE"
  cp "$BUILD_DIR/app.tgz" "$FPK_STAGE/"
  cp fpk/manifest "$FPK_STAGE/"
  cp -r fpk/cmd "$FPK_STAGE/"
  cp -r fpk/bin "$FPK_STAGE/" 2>/dev/null || true
  cp -r fpk/config "$FPK_STAGE/"
  cp fpk/ICON.PNG fpk/ICON_256.PNG fpk/LICENSE "$FPK_STAGE/" 2>/dev/null || true
  cp -r fpk/wizard "$FPK_STAGE/" 2>/dev/null || true

  # 计算 checksum 并更新 manifest
  APP_MD5="$(md5sum "$FPK_STAGE/app.tgz" | awk '{print $1}')"
  sed -i "s/^checksum.*=.*/checksum              = $APP_MD5/" "$FPK_STAGE/manifest"
  echo "app.tgz checksum: $APP_MD5"

  # 打包 FPK
  tar czf "$DIST/fnos-hermes-agent_v${CUR_VERSION}.fpk" \
    -C "$FPK_STAGE" manifest app.tgz cmd config bin ICON.PNG ICON_256.PNG LICENSE wizard 2>/dev/null || \
  tar czf "$DIST/fnos-hermes-agent_v${CUR_VERSION}.fpk" \
    -C "$FPK_STAGE" manifest app.tgz cmd config ICON.PNG ICON_256.PNG LICENSE
  echo "✓ 完整 FPK: $DIST/fnos-hermes-agent_v${CUR_VERSION}.fpk"

# ── 生成增量更新包 ──────────────────────────────────────────────────
echo "── 生成增量更新包 ──"
if [ -n "$PREV_VERSION" ] && [ "$PREV_TAG" != "v$CUR_VERSION" ]; then
  CHANGED_FILES="$(git diff --name-only "$PREV_TAG" HEAD -- app/ 2>/dev/null || true)"
  if [ -n "$CHANGED_FILES" ]; then
    INC_STAGE="$BUILD_DIR/inc-stage"
    rm -rf "$INC_STAGE"
    mkdir -p "$INC_STAGE"
    for f in $CHANGED_FILES; do
      case "$f" in
        app/server/*)            DEST="$INC_STAGE/server/$(basename "$f")" ;;
        app/desktop-app/*)       DEST="$INC_STAGE/desktop-app/${f#app/desktop-app/}" ;;
        app/hermes-src/*)        DEST="$INC_STAGE/hermes-src/${f#app/hermes-src/}" ;;
        app/config/*)            DEST="$INC_STAGE/config/${f#app/config/}" ;;
        app/ui/*)                DEST="$INC_STAGE/ui/$(basename "$f")" ;;
        app/VERSION)             DEST="$INC_STAGE/VERSION" ;;
        *)                       DEST="$INC_STAGE/$(basename "$f")" ;;
      esac
      mkdir -p "$(dirname "$DEST")"
      cp "$f" "$DEST"
    done
    tar czf "$DIST/incremental-${PREV_VERSION}-to-${CUR_VERSION}.tar.gz" -C "$INC_STAGE" .
    echo "✓ 增量包: incremental-${PREV_VERSION}-to-${CUR_VERSION}.tar.gz"
  else
    echo "⚠ app/ 无变更，跳过增量包"
  fi
else
  echo "⚠ 无上一版本，跳过增量包（首次发布）"
fi

# ── 生成 hot-patch.json ─────────────────────────────────────────────
echo "── 生成 hot-patch.json ──"
if [ -n "$PREV_VERSION" ] && [ -f "$DIST/incremental-${PREV_VERSION}-to-${CUR_VERSION}.tar.gz" ]; then
  ARCHIVE_MD5="$(md5sum "$DIST/incremental-${PREV_VERSION}-to-${CUR_VERSION}.tar.gz" | awk '{print $1}')"
  cat > "$DIST/hot-patch.json" << JSONEOF
{
  "version": "$CUR_VERSION",
  "base_version": "$PREV_VERSION",
  "archive": "incremental-${PREV_VERSION}-to-${CUR_VERSION}.tar.gz",
  "archive_md5": "$ARCHIVE_MD5",
  "files": []
}
JSONEOF
  echo "✓ hot-patch.json 已生成"
else
  echo "⚠ 无增量包，hot-patch.json 跳过"
fi

echo ""
echo "═══ 构建完成 ═══"
ls -la "$DIST/" 2>/dev/null || true
