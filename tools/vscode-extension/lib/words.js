// zhc 方言词表纯逻辑（无 vscode 依赖，node 可直接单测）
// 数据源：lib/zhc-words.json（zh）+ lib/words-<code>.json（其余语言），
// 均由 tools/gen_words.py 从语言包生成，勿手改。
// 词条字段约定（与生成器一致）：zh = 该语言包的方言词（中文包即中文词），
// en = 官方 Cangjie 名；kind/cat 同 zhc 词表语义。
// 职责：补全候选（前缀联想 + kind 排序）+ 悬停查词（方言词/官方名双向）+ 行内词提取。
// P-2/P-9 多语言：所有查表函数带可选尾参 code（默认 'zh'），扩展按文档语言取表。

'use strict';

const ZH_WORDS = require('./zhc-words.json').words;

// code -> { list, byZh, byEn }（懒加载缓存；zh 常驻）
const TABLES = new Map();

function table(code) {
  if (!code || code === 'zh') code = 'zh';
  const hit = TABLES.get(code);
  if (hit) return hit;
  let list = ZH_WORDS;
  if (code !== 'zh') {
    try {
      list = require('./words-' + code + '.json').words;
    } catch (e) {
      // 语言包已扩展但词表未生成：静默回退 zh 词表（补全/悬停不中断）
    }
  }
  const byZh = new Map();
  const byEn = new Map();
  for (const w of list) {
    // 同方言词理论上无重名（gen_words 已核）；后载保留首条
    if (!byZh.has(w.zh)) byZh.set(w.zh, w);
    if (!byEn.has(w.en)) byEn.set(w.en, w);
  }
  const t = { list, byZh, byEn };
  TABLES.set(code, t);
  return t;
}

// 补全排序权重：函数/类型最常用 → 关键字 → 其余；同权按方言词稳定排序
const KIND_ORDER = { function: 0, type: 1, keyword: 2, literal: 3, module: 4, macro: 5 };

/** 指定语言全部词条（生成序）；无参/zh = 历史行为。 */
function allWords(code) {
  return table(code).list;
}

/** 按方言词查词条（悬停；输入态方言词）；查不到返回 undefined。 */
function findByZh(zh, code) {
  return table(code).byZh.get(zh);
}

/** 按官方名查词条（悬停；混编官方代码场景；官方名跨语言共享，查表按包覆盖范围）。 */
function findByEn(en, code) {
  return table(code).byEn.get(en);
}

/** 方言词前缀联想（补全）：匹配 zh 开头；kind 排序稳定。 */
function matchPrefix(prefix, code) {
  const list = table(code).list;
  if (!prefix) return list.slice();
  const out = list.filter((w) => w.zh.startsWith(prefix));
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
