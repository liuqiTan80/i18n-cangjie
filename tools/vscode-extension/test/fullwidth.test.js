// 全角转换纯函数单测（建议 E4）：node test/fullwidth.test.js（acceptance 段 11 调用）
// 覆盖：基本转换 / 字符串内保留 / 行注释保留 / 块注释保留 / 转义引号 / 计数
'use strict';
const assert = require('assert');
const { stringRanges, convertFullwidthText } = require('../lib/fullwidth');

let n = 0;
function t(name, fn) {
  fn();
  n += 1;
  console.log('  ✅ ' + name);
}

t('基本转换：全角括号/分号 → 半角（引号不在映射表则保留）', () => {
  const [out, count] = convertFullwidthText('打印行（“hi”）；');
  assert.strictEqual(out, '打印行(“hi”);');
  assert.strictEqual(count, 3, '应转换（、）、；三个');
});

t('字符串字面量内全角标点保留', () => {
  const [out, count] = convertFullwidthText('打印行("你好（世界）")；');
  assert.strictEqual(out, '打印行("你好（世界）");');
  assert.strictEqual(count, 1, '只应转换字符串外的分号');
});

t('行注释内全角标点保留', () => {
  const [out, count] = convertFullwidthText('让 甲 = 1；  // 注释（保留）');
  assert.strictEqual(out, '让 甲 = 1;  // 注释（保留）');
  assert.strictEqual(count, 1);
});

t('块注释内全角标点保留', () => {
  const [out, count] = convertFullwidthText('/* 块注释（保留）*/ 让 甲 = 2；');
  assert.strictEqual(out, '/* 块注释（保留）*/ 让 甲 = 2;');
  assert.strictEqual(count, 1);
});

t('转义引号不提前闭合字符串', () => {
  const [out, count] = convertFullwidthText('打印行("含 \\" 转义（保留）")；');
  assert.strictEqual(out, '打印行("含 \\" 转义（保留）");');
  assert.strictEqual(count, 1);
});

t('stringRanges 覆盖字符串与注释区间', () => {
  const text = '让 甲 = "文（字）"; // 注（释）';
  const ranges = stringRanges(text);
  assert.strictEqual(ranges.length, 2);
  assert.strictEqual(text.slice(ranges[0][0], ranges[0][1]), '"文（字）"');
  assert.ok(text.slice(ranges[1][0], ranges[1][1]).startsWith('//'));
});

t('无需转换时计数为 0', () => {
  const [out, count] = convertFullwidthText('main() { println("ok"); }');
  assert.strictEqual(out, 'main() { println("ok"); }');
  assert.strictEqual(count, 0);
});

console.log(`\n全角转换单测通过（${n} 项）`);
