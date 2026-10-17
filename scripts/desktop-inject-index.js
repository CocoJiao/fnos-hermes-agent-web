#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════
// 桌面端 index.html 注入脚本
//
// 官方 apps/desktop `vite build` 产出的 dist/index.html 是纯 Electron 版，
// 本项目作为 Web 版部署需要三处改造：
//   1) viewport 增加 viewport-fit=cover（刘海屏）+ interactive-widget=resizes-content（输入法）
//   2) 注入 window.__HERMES_WEB_CONFIG__（前端走 /proxy/dashboard 代理 + session token）
//   3) 注入 web-shim.js（汉化层 / 移动端适配 / 桥接）
//
// 用法（重建前端后执行，会覆盖 app/desktop-app/index.html）：
//   node scripts/desktop-inject-index.js
// 前置：upstream/apps/desktop/dist/index.html 已由 `vite build` 生成。
// ═══════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'upstream/apps/desktop/dist/index.html');
const DST = path.join(ROOT, 'app/desktop-app/index.html');

if (!fs.existsSync(SRC)) {
  console.error('✗ 未找到上游构建产物:', SRC);
  console.error('  请先执行：cd upstream/apps/desktop && npx vite build');
  process.exit(1);
}

let html = fs.readFileSync(SRC, 'utf8');

const viewportRe = /<meta name="viewport" content="[^"]*"\s*\/?>/;
if (!viewportRe.test(html)) {
  console.error('✗ 未找到 viewport meta');
  process.exit(1);
}
html = html.replace(
  viewportRe,
  '<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover, interactive-widget=resizes-content" />'
);

if (!html.includes('</head>')) {
  console.error('✗ 未找到 </head>');
  process.exit(1);
}

html = html.replace(
  '  </head>',
  `    <script>window.__HERMES_WEB_CONFIG__ = window.__HERMES_WEB_CONFIG__ || { base: "/proxy/dashboard", token: "", profile: null };</script>
    <style id="hermes-webline-overrides">
      button[data-slot="searchable-select-trigger"] { min-width: 240px; }
    </style>
    <script src="./web-shim.js?v=55"></script>
  </head>`
);

fs.writeFileSync(DST, html, 'utf8');
console.log('✓ 已写入', path.relative(ROOT, DST), `(${html.length} 字节)`);
