// 全角标点转换纯函数（无 vscode 依赖，node 可直接单测——建议 E4）
// 职责：字符串字面量 + 行/块注释外，把全角符号换成半角 ASCII。
// 映射集：括号/逗号/分号/冒号/引号（弯引号“”‘’与直引号"' 全角形态
// U+FF02/U+FF07 一并处理）+ 全角空格 U+3000——代码区输入中文引号直接变半角
// 定界符；字符串/注释内由词法状态机保证保留原文。
// 词法状态机与 extension.js 中编辑器逻辑解耦，便于 node assert 回归。

const FULLWIDTH_MAP = {
  '（': '(', '）': ')',
  '，': ',', '；': ';', '：': ':',
  '“': '"', '”': '"',
  '‘': "'", '’': "'",
  '\uFF02': '"', '\uFF07': "'",   // 全角直引号 " '（输入法直引号形态）
  '\u3000': ' ',                     // 全角空格（代码区常见误入，转普通空格）
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

/** 插入点是否位于字符串/注释内容区（供“输入时自动转换”用，区别于逐字符转换）：
 *  - 光标在引号/注释区间内（含未闭合字符串的末尾——行尾继续输入仍是内容）
 *  - 光标紧贴闭合引号之后（pos == e 且字符串已闭合）视为代码区，可转换 */
function inStringInsert(text, pos) {
  const ranges = stringRanges(text);
  for (const [s, e] of ranges) {
    if (pos >= s && pos < e) return true;
    if (pos === e && e === text.length) return true;   // 未闭合字符串/注释到行尾
  }
  return false;
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

module.exports = { FULLWIDTH_MAP, stringRanges, isInString, inStringInsert, convertFullwidthText };
