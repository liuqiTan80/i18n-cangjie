// zhc 方言词表纯逻辑（无 vscode 依赖，node 可直接单测）
// 数据源 lib/zhc-words.json（由 tools/gen_words.py 从语言包生成，勿手改）。
// 职责：补全候选（前缀联想 + kind 排序）+ 悬停查词（中文/官方名双向）+ 行内词提取。

'use strict';

const WORD_LIST = require('./zhc-words.json').words;

const BY_ZH = new Map();
const BY_EN = new Map();
for (const w of WORD_LIST) {
  // 同 zh 词条理论上无重名（gen_words 已核）；后载保留首条
  if (!BY_ZH.has(w.zh)) BY_ZH.set(w.zh, w);
  if (!BY_EN.has(w.en)) BY_EN.set(w.en, w);
}

// 补全排序权重：函数/类型最常用 → 关键字 → 其余；同权按中文名稳定排序
const KIND_ORDER = { function: 0, type: 1, keyword: 2, literal: 3, module: 4, macro: 5 };

/** 全部词条（生成序）。 */
function allWords() {
  return WORD_LIST;
}

/** 按中文名查词条（悬停；输入态中文词）；查不到返回 undefined。 */
function findByZh(zh) {
  return BY_ZH.get(zh);
}

/** 按官方名查词条（悬停；混编官方代码场景）。 */
function findByEn(en) {
  return BY_EN.get(en);
}

/** 中文前缀联想（补全）：匹配 zh 开头；kind 排序稳定。 */
function matchPrefix(prefix) {
  if (!prefix) return WORD_LIST.slice();
  const out = WORD_LIST.filter((w) => w.zh.startsWith(prefix));
  out.sort((a, b) => {
    const d = KIND_ORDER[a.kind] - KIND_ORDER[b.kind];
    return d !== 0 ? d : a.zh.localeCompare(b.zh, 'zh');
  });
  return out;
}

/** 提取行内 [字符/数字/@] 组成的词（position 所在 token）；无则返回 null。 */
function tokenAtLine(lineText, character) {
  if (character < 0 || character > lineText.length) return null;
  const re = /[\p{L}\p{N}_@]+/gu;
  let m;
  while ((m = re.exec(lineText)) !== null) {
    if (character >= m.index && character <= m.index + m[0].length) {
      return m[0];
    }
    if (m.index + m[0].length > character) break;
  }
  return null;
}

module.exports = { allWords, findByZh, findByEn, matchPrefix, tokenAtLine, KIND_ORDER };
