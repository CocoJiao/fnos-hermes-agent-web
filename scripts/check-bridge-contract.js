#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════
// 桥接契约检查：列出官方 desktop 前端用到的 window.hermesDesktop 属性
//
// 背景（2026-10 真实事故）：web-shim 用 Proxy 给 hermesDesktop 做兜底，
// 不存在的属性一律返回"万能函数"。0.22.2 新增读取 localSkin（期望对象/null），
// 拿到函数后执行 (localSkin?.profile ?? "").trim() → TypeError，整页白屏，
// 报错文案是 "(e ?? "").trim is not a function"，极易被误判成前端 bug。
//
// 用法：同步上游后跑一次，把新增属性补进 app/desktop-app/web-shim.js 的 core，
//       并给出正确的空值类型（对象给 null、布尔给 false、数值给 0），
//       不要依赖 Proxy 兜底。
//   node scripts/check-bridge-contract.js [upstream/apps/desktop/src]
// ═══════════════════════════════════════════════════════════════════
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(ROOT, 'upstream/apps/desktop/src');

if (!fs.existsSync(SRC)) {
  console.error('✗ 未找到官方前端源码:', SRC);
  console.error('  先克隆上游：git clone --depth 1 --branch <tag> https://github.com/NousResearch/hermes-agent.git upstream');
  process.exit(1);
}

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx)$/.test(e.name)) out.push(p);
  }
  return out;
}

const props = new Map();
const re = /hermesDesktop\??\.([A-Za-z_$][\w$]*)/g;
const destr = /(?:const|let|var)\s*\{([^}]{1,200})\}\s*=\s*(?:window\.)?hermesDesktop/g;

for (const f of walk(SRC)) {
  const txt = fs.readFileSync(f, 'utf8');
  let m;
  while ((m = re.exec(txt))) if (!props.has(m[1])) props.set(m[1], path.relative(SRC, f));
  while ((m = destr.exec(txt))) {
    for (const part of m[1].split(',')) {
      const name = part.split(':')[0].trim();
      if (/^[A-Za-z_$][\w$]*$/.test(name) && !props.has(name)) props.set(name, path.relative(SRC, f));
    }
  }
}

// shim 里显式提供的键（core / nested 对象属性）
const shim = fs.readFileSync(path.join(ROOT, 'app/desktop-app/web-shim.js'), 'utf8');
const provided = new Set();
for (const m of shim.matchAll(/^\s{4}([A-Za-z_$][\w$]*)\s*:/gm)) provided.add(m[1]);

const all = [...props.keys()].sort();
const missing = all.filter((k) => !provided.has(k));

console.log(`官方使用 ${all.length} 个桥接属性，shim 显式提供 ${provided.size} 个键`);
console.log(`未显式提供（走 Proxy 兜底，返回函数）: ${missing.length}`);
console.log(missing.join('  '));
if (missing.length) {
  console.log('\n⚠ 数据类属性（对象/布尔/数值）走兜底会被当字符串 trim 而崩溃，');
  console.log('  请在 web-shim.js 的 core 里显式给出正确空值。');
}
