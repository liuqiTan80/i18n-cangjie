// 全角转换纯函数单测（建议 E4）：node test/fullwidth.test.js（acceptance 段 11 调用）
// 覆盖：基本转换 / 中文引号映射 / 字符串内保留 / 行注释保留 / 块注释保留 /
//      转义引号 / 计数 / 插入点判定（inStringInsert：字符串内输入不转换）
'use strict';
const assert = require('assert');
const { stringRanges, isInString, inStringInsert, convertFullwidthText } = require('../lib/fullwidth');

let n = 0;
function t(name, fn) {
  fn();
  n += 1;
  console.log('  ✅ ' + name);
}

t('基本转换：全角括号/分号/中文引号 → 半角', () => {
  const [out, count] = convertFullwidthText('打印行（“hi”）；');
  assert.strictEqual(out, '打印行("hi");');
  assert.strictEqual(count, 5, '应转换（、）、“、”、；共 5 个');
});

t('全角直引号（U+FF02/U+FF07）与全角空格 → 半角', () => {
  // 输入法「直引号」形态：U+FF02 与 U+FF07
  const [out, count] = convertFullwidthText('打印行（\uFF02hi\uFF02）；');
  assert.strictEqual(out, '打印行("hi");');
  assert.strictEqual(count, 5);
  const [out2, count2] = convertFullwidthText('让 甲\u3000= 1；');
  assert.strictEqual(out2, '让 甲 = 1;');
  assert.strictEqual(count2, 2, '全角空格与全角分号都应转换');
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

t('inStringInsert：字符串中段/未闭合行尾输入 → 保留（不转换）', () => {
  // 光标在 "你好（世 字符串中段：前缀含未闭合引号
  assert.strictEqual(inStringInsert('打印行("你好（世', 9), true);
  // 光标在行尾继续输入（未闭合字符串尾部）：仍在字符串内
  assert.strictEqual(inStringInsert('打印行("你好（世界）', 11), true);
  // 光标在闭合引号之后（第 8 字符）：代码区，可转换
  assert.strictEqual(inStringInsert('打印行("hi")', 8), false);
  // 行注释内输入：保留
  assert.strictEqual(inStringInsert('  // 注释（保留', 10), true);
  // 普通代码区：可转换
  assert.strictEqual(inStringInsert('让 甲 = 1', 6), false);
});

t('inStringInsert：闭合字符串/注释到行尾 → 行尾是代码区，可转换', () => {
  // 闭引号是行最后一个字符，光标在行尾：已闭合，应可转换（修复：双引号后敲逗号不转）
  assert.strictEqual(inStringInsert('让 甲 = "x"', 9), false);
  // 块注释闭合到行尾（/* ... */ 后即行尾）：可转换
  assert.strictEqual(inStringInsert('/* 注释 */', 8), false);
  // 未闭合字符串到行尾：仍在内容区（继续输入是字符串内容）
  assert.strictEqual(inStringInsert('让 甲 = "x', 8), true);
  // 行注释内容以引号结尾：仍属注释，保留
  assert.strictEqual(inStringInsert('  // 他说"', 8), true);
});

t('无需转换时计数为 0', () => {
  const [out, count] = convertFullwidthText('main() { println("ok"); }');
  assert.strictEqual(out, 'main() { println("ok"); }');
  assert.strictEqual(count, 0);
});

console.log(`\n全角转换单测通过（${n} 项）`);
