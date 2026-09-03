// 词表纯逻辑单测：node test/words.test.js（acceptance 段 11 调用）
// 覆盖：词表规模/分类 / 中文前缀联想排序 / 官方名双向查 / 行内词提取 / @ 宏
'use strict';
const assert = require('assert');
const wordsLib = require('../lib/words.js');

let n = 0;
function t(name, fn) {
  fn();
  n += 1;
  console.log('  ✅ ' + name);
}

t('词表已加载且规模合理（zh 包全量：关键字+类型+函数+宏+模块）', () => {
  const all = wordsLib.allWords();
  assert.ok(all.length >= 200, '词条总数应 ≥ 200，实际 ' + all.length);
  const kinds = {};
  for (const w of all) kinds[w.kind] = (kinds[w.kind] || 0) + 1;
  assert.ok(kinds.function >= 150, '函数词条 ≥ 150');
  assert.ok(kinds.type >= 30, '类型词条 ≥ 30');
  assert.ok(kinds.keyword >= 50, '关键字词条 ≥ 50');
  assert.ok(kinds.macro >= 3, '宏词条 ≥ 3（派生/测试/期望）');
});

t('中文前缀联想：输入「打」返回 打印/打印行 且函数优先', () => {
  const r = wordsLib.matchPrefix('打');
  const zhs = r.map((w) => w.zh);
  assert.ok(zhs.includes('打印') && zhs.includes('打印行'), '应含 打印/打印行');
  for (const w of r) assert.ok(w.zh.startsWith('打'), '全部以「打」开头');
  // 函数权 0 排最前
  assert.strictEqual(r[0].kind, 'function');
});

t('空前缀返回全量（Ctrl+Space 场景）', () => {
  assert.strictEqual(wordsLib.matchPrefix('').length, wordsLib.allWords().length);
});

t('官方名双向查：打印行 ↔ println', () => {
  const zh = wordsLib.findByZh('打印行');
  assert.ok(zh, '按中文名可查');
  assert.strictEqual(zh.en, 'println');
  const en = wordsLib.findByEn('println');
  assert.strictEqual(en.zh, '打印行');
  assert.strictEqual(wordsLib.findByZh('不存在词'), undefined);
});

t('类型/字面量/宏分类正确（补全带括号仅函数）', () => {
  assert.strictEqual(wordsLib.findByZh('字符串').kind, 'type');
  assert.strictEqual(wordsLib.findByZh('真').kind, 'literal');
  assert.strictEqual(wordsLib.findByZh('派生').kind, 'macro');
  assert.strictEqual(wordsLib.findByEn('Option').zh, '选项');
});

t('行内词提取：中文词/官方词/@宏/光标在词尾边界', () => {
  assert.strictEqual(wordsLib.tokenAtLine('打印行("hi")', 1), '打印行');
  assert.strictEqual(wordsLib.tokenAtLine('打印行("hi")', 3), '打印行');   // 词尾边界（闭括号前）
  assert.strictEqual(wordsLib.tokenAtLine('  @派生(甲)', 4), '@派生');
  assert.strictEqual(wordsLib.tokenAtLine('let 长度 = 3', 5), '长度');
  assert.strictEqual(wordsLib.tokenAtLine('打印行("hi")', 10), null);      // 标点/空白处无词
  assert.strictEqual(wordsLib.tokenAtLine('', 0), null);
});

console.log(`\n词表单测通过（${n} 项）`);
