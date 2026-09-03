// zhc 对照视图纯逻辑（③ 方言↔官方源码对照，教学演示）
//
// 输入：`zhc compare <文件.zc>` 的 stdout JSON（无 vscode 依赖，node 单测覆盖）：
//   { file, dialect, official, pairs: [[s, sl, d, dl], ...] }
//   —— pairs 坐标为 UTF-16 code unit 绝对偏移（与 JS String 下标同单位），
//      s/sl = dialect 中方言词区间 [s, s+sl)；d/dl = official 中官方词区间。
//      SourceMap 折算保证条目按源偏移升序且不跨行（转译逐 token 保行）。
//
// 渲染策略：逐行对照（行数一致时第 i 行 ↔ 第 i 行），词对在两侧行内标记，
// 同一词对两侧同色；行数不一致时（理论上不发生，容错）按行号 min 对齐并提示。

// 词对高亮底色（浅色系，黑字可读；行内 hover 有 tooltip 看 zh ↔ en）
const HL_COLORS = [
  'rgba(255, 193, 7, .35)',    // 琥珀
  'rgba(76, 175, 80, .30)',    // 绿
  'rgba(33, 150, 243, .28)',   // 蓝
  'rgba(236, 64, 122, .25)',   // 粉
  'rgba(156, 39, 176, .22)',   // 紫
  'rgba(0, 188, 212, .30)',    // 青
];

// 文本转义（HTML 正文段；hl 词的 title 属性额外转义引号在调用处做）
function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/** UTF-16 行起始表（文本按 \n 分行；行文本不含换行符）。 */
function lineStarts(text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) {
    if (text.charCodeAt(i) === 10) starts.push(i + 1);
  }
  return starts;
}

/** 绝对偏移 → 行号（0 起）与行内列（0 起，UTF-16）。 */
function locate(starts, abs) {
  let lo = 0, hi = starts.length - 1, row = 0;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (starts[mid] <= abs) { row = mid; lo = mid + 1; } else { hi = mid - 1; }
  }
  return { row, col: abs - starts[row] };
}

/** 词 → 稳定色索引（同一方言词全局同色，对照扫读更易追踪）。 */
function colorOf(word) {
  let h = 0;
  for (let i = 0; i < word.length; i++) h = (h * 31 + word.charCodeAt(i)) >>> 0;
  return h % HL_COLORS.length;
}

/**
 * 把对照 JSON 转成逐行渲染模型：
 *   rows[i] = { d: 方言行文本, o: 官方行文本, dm: [标记], om: [标记] }
 *   标记 = { c: 列, l: 长, k: 色索引, zh, en }
 * 词对跨行或越界（数据异常）时跳过并计入 dropped；note 非空时 UI 提示。
 */
function buildRows(data) {
  const srcStarts = lineStarts(data.dialect);
  const dstStarts = lineStarts(data.official);
  const dLines = data.dialect.split('\n');
  const oLines = data.official.split('\n');
  // split 尾空段处理：文本以 \n 结尾时最后元素是空行，行表也含该行起始——
  // 两侧一致时无需特判；不一致时按行表长度裁剪。
  while (dLines.length > srcStarts.length) dLines.pop();
  while (oLines.length > dstStarts.length) oLines.pop();
  const n = Math.max(srcStarts.length, dstStarts.length);
  const rows = [];
  for (let i = 0; i < n; i++) {
    rows.push({ d: i < dLines.length ? dLines[i] : '', o: i < oLines.length ? oLines[i] : '', dm: [], om: [] });
  }
  let dropped = 0;
  for (const p of (data.pairs || [])) {
    const [s, sl, d, dl] = p;
    const sm = locate(srcStarts, s);
    const dm = locate(dstStarts, d);
    if (sm.row >= rows.length || dm.row >= rows.length) { dropped++; continue; }
    if (s + sl > data.dialect.length || d + dl > data.official.length) { dropped++; continue; }
    const zh = data.dialect.substr(s, sl);
    const en = data.official.substr(d, dl);
    const k = colorOf(zh);
    rows[sm.row].dm.push({ c: sm.col, l: sl, k, zh, en });
    rows[dm.row].om.push({ c: dm.col, l: dl, k, zh, en });
  }
  const note = rows.length > 0 && srcStarts.length !== dstStarts.length
    ? '两侧行数不一致（方言 ' + srcStarts.length + ' 行 ↔ 官方 ' + dstStarts.length + ' 行），按行号就近对齐'
    : (dropped > 0 ? dropped + ' 个词对坐标越界已跳过' : '');
  return { rows, note, pairs: (data.pairs || []).length };
}

/** 行文本按行内标记切段 → HTML 片段（标记重叠时后标记包前标记，渲染仍可读）。 */
function segs(text, marks, side) {
  const sorted = marks.slice().sort((a, b) => a.c - b.c);
  let out = '';
  let pos = 0;
  for (const m of sorted) {
    if (m.c < pos) continue;              // 异常重叠：跳过（防御）
    if (m.c > pos) out += escapeHtml(text.slice(pos, m.c));
    const w = text.slice(m.c, m.c + m.l);
    const tip = side === 'd' ? '替换为 ' + m.en : '由 ' + m.zh + ' 转译';
    out += '<span class="hl k' + m.k + '" title="' + escapeHtml(m.zh + ' → ' + m.en) + '（' + tip + '）">' + escapeHtml(w) + '</span>';
    pos = m.c + m.l;
  }
  if (pos < text.length) out += escapeHtml(text.slice(pos));
  return out || '&nbsp;';
}

/** 整页 HTML（无脚本 CSP；等宽双栏 + 行 hover + 词级底色）。 */
function compareHtml(data, title) {
  const { rows, note, pairs } = buildRows(data);
  const bar = '<div class="bar">'
    + '<span class="t">' + escapeHtml(title) + '</span>'
    + '<span class="side zh">方言 .zc</span>'
    + '<span class="side cj">官方 .cj</span>'
    + '<span class="cnt">' + rows.length + ' 行 · ' + pairs + ' 处替换</span></div>';
  const body = rows.map((r, i) =>
    '<div class="row"><span class="ln">' + (i + 1) + '</span>'
    + '<span class="cx d">' + segs(r.d, r.dm, 'd') + '</span>'
    + '<span class="cx o">' + segs(r.o, r.om, 'o') + '</span></div>'
  ).join('');
  const css = '.hl{border-radius:3px;padding:0 2px;box-decoration-break:clone;-webkit-box-decoration-break:clone}'
    + '.k0{background:' + HL_COLORS[0] + '}.k1{background:' + HL_COLORS[1] + '}'
    + '.k2{background:' + HL_COLORS[2] + '}.k3{background:' + HL_COLORS[3] + '}'
    + '.k4{background:' + HL_COLORS[4] + '}.k5{background:' + HL_COLORS[5] + '}';
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
    + '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'">'
    + '<title>' + escapeHtml(title) + ' —— 方言 ↔ 官方对照</title>'
    + '<style>body{font-family:Consolas,"Courier New",monospace;font-size:13px;margin:0;color:#202124}'
    + '.bar{position:sticky;top:0;background:#f8f9fa;border-bottom:1px solid #dadce0;padding:6px 10px;display:flex;gap:10px;align-items:baseline;z-index:2}'
    + '.bar .t{font-weight:600}.side{font-size:11px;color:#fff;border-radius:8px;padding:0 7px}.side.zh{background:#5c6bc0}'
    + '.side.cj{background:#00897b}.cnt{margin-left:auto;color:#80868b;font-size:12px}'
    + '.row{display:grid;grid-template-columns:3.2em 1fr 1fr;border-bottom:1px solid #f1f3f4}'
    + '.row:hover{background:#e8f0fe}.row .ln{color:#9aa0a6;text-align:right;padding:0 8px 0 4px;user-select:none}'
    + '.row .cx{padding:1px 8px;white-space:pre-wrap;word-break:break-all;line-height:1.55}'
    + '.row .cx.d{border-right:1px solid #e8eaed}.row .cx.o{background:#fbfeff}'
    + '.note{padding:6px 12px;color:#b06000;background:#fff8e1;font-size:12px}' + css
    + '</style></head><body>' + bar
    + (note ? '<div class="note">' + escapeHtml(note) + '</div>' : '')
    + body + '</body></html>';
}

module.exports = { HL_COLORS, escapeHtml, lineStarts, locate, colorOf, buildRows, segs, compareHtml };
