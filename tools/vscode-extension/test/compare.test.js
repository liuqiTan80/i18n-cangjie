// 对照视图纯逻辑单测：node test/compare.test.js（acceptance 静态检查段调用）
// 覆盖：行起始表/绝对偏移归行 / 词对双侧标记与文本取词 / 色稳定 /
//       行数不一致容错 / 越界词对跳过 / HTML 转义与双栏结构
'use strict';
const assert = require('assert');
const L = require('../lib/compare.js');

let n = 0;
function t(name, fn) {
  fn();
  n += 1;
  console.log('  ✅ ' + name);
}

// 小样例：两行方言（中文 + ASCII 混合）↔ 官方（词变长，行数一致）
// 行0「主函数() {」→ 行0「main() {」（主函数 0..3 → main 0..4）
// 行1「    打印行(3)」→「    println(3)」（行1 起始 9；打印行 12..15 → println 13..20）
const SAMPLE = {
  dialect: '主函数() {\n    打印行(3)\n}',
  official: 'main() {\n    println(3)\n}',
  pairs: [[0, 3, 0, 4], [12, 3, 13, 7]],
};

t('行起始表：中文按 UTF-16 每码元 1 单元计', () => {
  assert.deepStrictEqual(L.lineStarts('主函数() {\n    打印行(3)\n}'), [0, 8, 19]); // 行1 长 10
  assert.deepStrictEqual(L.lineStarts(''), [0]);
  assert.deepStrictEqual(L.lineStarts('a\n\nb\n'), [0, 2, 3, 5]); // 尾部 \n 也产生行
});

t('绝对偏移 → 行号与行内列', () => {
  const st = L.lineStarts(SAMPLE.dialect);
  assert.deepStrictEqual(L.locate(st, 0), { row: 0, col: 0 });
  assert.deepStrictEqual(L.locate(st, 12), { row: 1, col: 4 }); // 行1 起始 8 + 4 空格
  assert.deepStrictEqual(L.locate(st, 20), { row: 2, col: 1 }); // 行2 '}' 后（越界钳制）
});

t('词对双侧归行：方言词/官方词区间取词一致', () => {
  const m = L.buildRows(SAMPLE);
  assert.strictEqual(m.pairs, 2);
  assert.strictEqual(m.rows.length, 3);
  assert.strictEqual(m.note, '');
  assert.deepStrictEqual(m.rows[0].d, '主函数() {');
  assert.deepStrictEqual(m.rows[0].o, 'main() {');
  assert.strictEqual(m.rows[0].dm.length, 1);
  assert.strictEqual(m.rows[0].dm[0].zh, '主函数');
  assert.strictEqual(m.rows[0].dm[0].en, 'main');
  assert.deepStrictEqual(m.rows[0].dm[0], { c: 0, l: 3, zh: '主函数', en: 'main', k: m.rows[0].dm[0].k });
  const om = m.rows[1].om[0];
  assert.deepStrictEqual([om.c, om.l, om.zh, om.en], [4, 7, '打印行', 'println']);
  // 同一词对两侧同色
  assert.strictEqual(m.rows[0].dm[0].k, m.rows[0].om[0].k);
  assert.strictEqual(m.rows[1].dm[0].k, m.rows[1].om[0].k);
});

t('色稳定：同一词恒同色，不同词可异色', () => {
  assert.strictEqual(L.colorOf('让'), L.colorOf('让'));
  assert.strictEqual(L.colorOf('让'), L.colorOf('让')); // 幂等
  assert.ok(L.colorOf('让') >= 0 && L.colorOf('让') < L.HL_COLORS.length);
  const set = new Set(['让', '可变', '如果', '返回'].map(L.colorOf));
  assert.ok(set.size >= 2, '常见词应覆盖 ≥2 种色');
});

t('行数不一致容错：短侧空行补齐 + note 提示', () => {
  const m = L.buildRows({ dialect: 'a\nb', official: 'x\ny\nz', pairs: [] });
  assert.strictEqual(m.rows.length, 3);
  assert.strictEqual(m.rows[2].d, '');
  assert.strictEqual(m.rows[2].o, 'z');
  assert.ok(m.note.includes('行数不一致'));
});

t('越界/非法词对跳过计数', () => {
  const m = L.buildRows({ dialect: 'a\nb', official: 'x\ny', pairs: [[0, 1, 99, 3]] });
  assert.strictEqual(m.rows[0].dm.length, 0);
  assert.ok(m.note.includes('跳过'));
});

t('HTML：转义安全 + 双栏结构 + hl 词底色与 title', () => {
  const m = L.buildRows(SAMPLE);
  const html = L.compareHtml(SAMPLE, 'demo.zc');
  assert.ok(html.startsWith('<!DOCTYPE html>'));
  assert.ok(html.includes('demo.zc'));
  assert.ok(html.includes('方言 .zc') && html.includes('官方 .cj'));
  assert.ok(html.includes('2 处替换'));
  assert.ok(html.includes('class="hl k') && html.includes('主函数'));
  assert.ok(html.includes('→ main'));        // 悬停注释带 zh → en
  assert.ok(!html.includes('<script'));
});

t('HTML 转义：< > & 引号不破坏结构', () => {
  const evil = { dialect: '<让 & "x">', official: '<let & "x">', pairs: [[0, 1, 1, 3]] };
  const html = L.compareHtml(evil, 'a<b>.zc');
  assert.ok(!html.includes('<让'));            // 原文 < 已转义（后随高亮 span）
  assert.ok(html.includes('&lt;<span'));       // 转义 + 高亮拼接
  assert.ok(html.includes('&quot;'));          // 引号转义（title 属性安全）
  assert.ok(!html.includes('<b>.zc'));         // 标题中的 < 也已转义
});

t('segs：无标记行空行输出 &nbsp; 保行高', () => {
  const s = L.segs('', [], 'd');
  assert.strictEqual(s, '&nbsp;');
});

console.log('compare 纯逻辑单测：' + n + ' 项全过');
