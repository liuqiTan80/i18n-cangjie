// 全角标点转换纯函数（无 vscode 依赖，node 可直接单测——建议 E4）
// 职责：字符串字面量 + 行/块注释外，把全角 （） ， ； ： 换成半角 ASCII。
// 词法状态机与 extension.js 中编辑器逻辑解耦，便于 node assert 回归。

const FULLWIDTH_MAP = {
  '（': '(', '）': ')',
  '，': ',', '；': ';', '：': ':',
};

/** 统计文本中受保护的位置集合（字符串字面量 + 行/块注释，双引号配对 + 转义）。 */
function stringRanges(text) {
  const ranges = [];
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '\\') { i += 2; continue; }
    if (ch === '/') {
      if (text[i + 1] === '/') {
        const start = i;
        const nl = text.indexOf('\n', i);
        i = nl === -1 ? text.length : nl + 1;
        ranges.push([start, i]);
        continue;
      }
      if (text[i + 1] === '*') {
        const start = i;
        const end = text.indexOf('*/', i + 2);
        i = end === -1 ? text.length : end + 2;
        ranges.push([start, i]);
        continue;
      }
    }
    if (ch === '"') {
      const start = i;
      i += 1;
      while (i < text.length) {
        if (text[i] === '\\') { i += 2; continue; }
        if (text[i] === '"') { i += 1; break; }
        i += 1;
      }
      ranges.push([start, i]);
      continue;
    }
    i += 1;
  }
  return ranges;
}

function isInString(ranges, pos) {
  for (const [s, e] of ranges) {
    if (pos >= s && pos < e) return true;
  }
  return false;
}

/** 转换整篇文本的全角标点（字符串/注释外）；返回 (新文本, 替换计数)。 */
function convertFullwidthText(text) {
  const ranges = stringRanges(text);
  let count = 0;
  const out = [];
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (FULLWIDTH_MAP[ch] && !isInString(ranges, i)) {
      out.push(FULLWIDTH_MAP[ch]);
      count += 1;
    } else {
      out.push(ch);
    }
  }
  return [out.join(''), count];
}

module.exports = { FULLWIDTH_MAP, stringRanges, isInString, convertFullwidthText };
