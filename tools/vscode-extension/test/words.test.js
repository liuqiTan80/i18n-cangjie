// 词表纯逻辑单测：node test/words.test.js（acceptance 段 11 调用）
// 覆盖：词表规模/分类 / 方言词前缀联想排序 / 官方名双向查 / 行内词提取 / @ 宏 / 多语言词表（P-9）
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

t('多语言（P-9）：ru 词表按 code 独立加载，方言词/官方名双向映射', () => {
  const all = wordsLib.allWords('ru');
  assert.ok(all.length >= 60, 'ru 词表 ≥ 60（演示档关键字+基础标识符），实际 ' + all.length);
  const w = wordsLib.findByZh('печать', 'ru');       // печать → println
  assert.ok(w, '按俄语方言词可查 печать');
  assert.strictEqual(w.en, 'println');
  assert.strictEqual(w.kind, 'function');
  assert.strictEqual(wordsLib.findByZh('функция', 'ru').kind, 'keyword');
  assert.strictEqual(wordsLib.findByEn('println', 'ru').zh, 'печать');   // 官方名反向查
  assert.strictEqual(wordsLib.findByZh('не_существует_词', 'ru'), undefined);
  // 未知 code 应安全回退 zh 词表（不抛异常）
  assert.ok(wordsLib.allWords('xx').length >= 200);
});

t('多语言（P-9）：en 方言恒等映射 + ja 假名词条，zh 默认词表不受影响', () => {
  // en 方言词 == 官方名（恒等关键字/标识符映射）
  const enMain = wordsLib.findByZh('main', 'en');
  assert.ok(enMain && enMain.en === 'main' && enMain.kind === 'keyword');
  assert.ok(wordsLib.findByZh('println', 'en').kind === 'function');
  assert.ok(wordsLib.allWords('en').length >= 200, 'en 全量档词表 ≥ 200');
  // ja 演示档：假名词条（メイン→main 关键字）与 @宏（テスト）
  const jaMain = wordsLib.findByZh('メイン', 'ja');
  assert.ok(jaMain && jaMain.en === 'main');
  const jaPrefix = wordsLib.matchPrefix('メ', 'ja');
  assert.ok(jaPrefix.every((x) => x.zh.startsWith('メ')));
  const jaMacro = wordsLib.findByZh('テスト', 'ja');
  assert.ok(jaMacro && jaMacro.kind === 'macro' && jaMacro.en === 'Test');
  // zh 默认路径（无尾参）仍为中文词表
  assert.strictEqual(wordsLib.findByZh('打印行').en, 'println');
  assert.strictEqual(wordsLib.findByZh('путin', 'ru'), undefined);
});

console.log(`\n词表单测通过（${n} 项）`);
