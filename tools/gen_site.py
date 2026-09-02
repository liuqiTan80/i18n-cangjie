#!/usr/bin/env python3
"""离线教学站点生成器（建议 C10）——纯标准库、零依赖。

把教程根目录（默认 docs/中文仓颉程序设计/）的全部 Markdown 编译为
单文件 HTML 站点：侧边目录 + 全文搜索 + cangjie/zhc 代码高亮，
无网络环境用浏览器打开即用；产物（docs/教学站点.html）进 release 离线包。

用法：
  python3 tools/gen_site.py [-o 输出.html] [--title 标题] [教程根]

支持的 Markdown 子集（教程实际使用的结构）：
标题 / 表格（含单元格加粗与行内码）/ 围栏代码块（```lang）/ 引用块 /
有序无序列表（2 空格嵌套）/ 加粗 / 斜体 / 行内代码 / 链接 / 分隔线。
链接改写：站内 .md 链接 → #文件锚点；未收录文档 → 降级为文本（title 保留
来源）；http(s) 外链原样保留（新窗口打开）。

代码高亮词表与语言包单一来源：运行时解析 zhc/lang-packs/zh/ 的
keywords.toml + stdlib.toml（键与值都参与匹配），语言包加词即自动高亮。
"""
import argparse
import html
import json
import re
import sys
from pathlib import Path

FENCE_RE = re.compile(r"^```([a-zA-Z0-9_-]*)\s*$")
HEAD_RE = re.compile(r"^(#{1,6})\s+(.*)$")
LIST_RE = re.compile(r"^(\s*)([-*]|\d+\.)\s+(.*)$")
TABLE_SEP_RE = re.compile(r"^\s*\|?[\s:|-]+\|?\s*$")
LANG_PACK = Path(__file__).resolve().parent.parent / "zhc" / "lang-packs" / "zh"

# ---------------------------------------------------------------- 工具

def esc(s: str) -> str:
    return html.escape(s, quote=False)


def slugify(s: str, fallback: str = "sec") -> str:
    """标题 → 锚点 id（保留中文，去空白与标点，截断防超长）。"""
    t = re.sub(r"[\s\ufeff]+", "-", s.strip())
    t = re.sub(r"[，。、；：（）()【】\[\]《》〈〉「」『』“”\"'!?！？·…—\-–/\\|`*_#^~<>]", "", t)
    t = re.sub(r"-{2,}", "-", t).strip("-")
    return t[:80] if t else fallback


def load_keyword_sets() -> set:
    """语言包键 + 值（官方对应词）→ 高亮词表（单一来源）。"""
    words = set()
    for fn in ("keywords.toml", "stdlib.toml"):
        path = LANG_PACK / fn
        if not path.exists():
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r'^\s*"([^"]+)"\s*=\s*"([^"]*)"\s*$', raw)
            if m:
                words.add(m.group(1))
                if m.group(2):
                    words.add(m.group(2))
    return words


# ---------------------------------------------------------------- 行内解析

class Placeholder:
    """保护片段（行内码/链接）先占位，最后统一还原。"""

    def __init__(self):
        self.parts = []

    def stash(self, rendered: str) -> str:
        self.parts.append(rendered)
        return f"\x00{len(self.parts) - 1}\x00"

    def restore(self, text: str) -> str:
        return re.sub(r"\x00(\d+)\x00", lambda m: self.parts[int(m.group(1))], text)


def parse_inline(text: str, ph: Placeholder, file_ids: set, root: Path) -> str:
    """行内标记：行内码 → 链接 → 粗体 → 斜体。顺序保证互不干扰。"""
    text = esc(text)

    def code_sub(m):
        return ph.stash(f"<code>{m.group(1)}</code>")

    text = re.sub(r"`([^`\n]+)`", code_sub, text)

    def link_sub(m):
        label, url = m.group(1), m.group(2).strip()
        if url.startswith(("http://", "https://", "mailto:")):
            return ph.stash(f'<a href="{esc(url)}" target="_blank" rel="noopener">{label}</a>')
        if url.startswith("#"):
            return ph.stash(f'<a href="{esc(url)}">{label}</a>')
        if url.endswith(".md") or ".md#" in url:
            target = url.split("#", 1)[0].rstrip("/")
            base = (root / target).resolve()
            if base.name in file_ids:
                return ph.stash(f'<a href="#{file_ids[base.name]}">{label}</a>')
            # 未收录文档（如 ../../cangjie-book.md）：降级为文本，title 保留来源
            return ph.stash(f'<span title="未收录文档：{esc(url)}">{label}</span>')
        return ph.stash(f'<a href="{esc(url)}">{label}</a>')

    text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", lambda m: ph.stash(f"[图]{m.group(1)}（{m.group(2)}）"), text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link_sub, text)
    text = re.sub(r"\*\*([^*\n]+)\*\*", lambda m: ph.stash(f"<strong>{m.group(1)}</strong>"), text)
    text = re.sub(r"(?<!\*)\*(?!\*)([^*\n]+)\*(?!\*)", lambda m: ph.stash(f"<em>{m.group(1)}</em>"), text)
    return ph.restore(text)


# ---------------------------------------------------------------- 代码高亮

def highlight_cangjie(code: str, kws: set) -> str:
    """逐字符扫描：字符串/字符/注释/数字/词表命中 → span。"""
    out, word, i, n = [], [], 0, len(code)

    def flush_word():
        if word:
            w = "".join(word)
            word.clear()
            cls = "k" if w in kws else ("n" if re.fullmatch(r"0[xX][0-9a-fA-F]+|\d[\d_]*", w) else "")
            out.append(f'<span class="k">{esc(w)}</span>' if cls == "k"
                       else f'<span class="n">{esc(w)}</span>' if cls == "n" else esc(w))

    while i < n:
        c = code[i]
        if c == "/" and i + 1 < n and code[i + 1] == "/":
            flush_word(); out.append(f'<span class="c">{esc(code[i:].rstrip())}</span>'); break
        if c == "/" and i + 1 < n and code[i + 1] == "*":
            flush_word()
            j = code.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(f'<span class="c">{esc(code[i:j])}</span>'); i = j; continue
        if c in "\"'":
            flush_word()
            q, j = c, i + 1
            while j < n:
                if code[j] == "\\":
                    j += 2; continue
                if code[j] == q:
                    j += 1; break
                j += 1
            out.append(f'<span class="s">{esc(code[i:j])}</span>'); i = j; continue
        if c.isalnum() or "\u4e00" <= c <= "\u9fff" or c == "_":
            word.append(c); i += 1; continue
        flush_word()
        out.append(esc(c)); i += 1
    flush_word()
    return "".join(out)


# ---------------------------------------------------------------- 文件渲染

def render_doc(path: Path, kws: set, file_ids: dict, root: Path) -> tuple:
    """渲染单个 md 文件 → (标题, 正文 html, 小节列表 [(标题, id, 摘要文本)])。"""
    lines = path.read_text(encoding="utf-8").splitlines()
    doc_slug = path.stem
    title = None
    body, blocks, i = [], [], 0

    def flush():
        if blocks:
            body.append(f"<p>{parse_inline(' '.join(blocks), Placeholder(), file_ids, root)}</p>")
            blocks.clear()

    while i < len(lines):
        line = lines[i]
        m = FENCE_RE.match(line)
        if m:
            flush()
            lang, buf = m.group(1), []
            i += 1
            while i < len(lines) and not FENCE_RE.match(lines[i]):
                buf.append(lines[i]); i += 1
            i += 1  # 跳过闭合围栏
            code = "\n".join(buf)
            if lang in ("cangjie", "zhc", "cj", "cjc", "cangjie,zhc"):
                body.append(f'<pre><code class="zhc">{highlight_cangjie(code, kws)}</code></pre>')
            else:
                body.append(f"<pre><code>{esc(code)}</code></pre>")
            continue
        m = HEAD_RE.match(line)
        if m:
            flush()
            level, text = len(m.group(1)), m.group(2).strip()
            if level == 1 and title is None:
                title = text  # 首个 H1 提升为文件标题
                i += 1
                continue
            head_id = f"{doc_slug}-{slugify(text)}"
            body.append(f'<h{level} id="{esc(head_id)}">{parse_inline(text, Placeholder(), file_ids, root)}</h{level}>')
            i += 1
            continue
        if not line.strip():
            flush(); i += 1; continue
        if line.lstrip().startswith("|") and i + 1 < len(lines) \
                and TABLE_SEP_RE.match(lines[i + 1]):
            flush()
            rows = [line]
            i += 1
            while i < len(lines) and lines[i].strip() \
                    and (lines[i].strip().startswith("|") or TABLE_SEP_RE.match(lines[i])):
                rows.append(lines[i]); i += 1
            if len(rows) >= 2 and TABLE_SEP_RE.match(rows[1]):
                cells = [r.strip().strip("|").split("|") for r in rows]
                head = cells[0]
                trs = []
                for r in cells[2:]:
                    trs.append("<tr>" + "".join(
                        f"<td>{parse_inline(c.strip(), Placeholder(), file_ids, root)}</td>" for c in r) + "</tr>")
                body.append("<table><thead><tr>" + "".join(
                    f"<th>{parse_inline(c.strip(), Placeholder(), file_ids, root)}</th>" for c in head) +
                    "</tr></thead><tbody>" + "".join(trs) + "</tbody></table>")
            continue
        if line.startswith(">"):
            flush()
            q = []
            while i < len(lines) and lines[i].startswith(">"):
                q.append(lines[i][1:].lstrip()); i += 1
            body.append(f"<blockquote>{parse_inline(' '.join(q), Placeholder(), file_ids, root)}</blockquote>")
            continue
        if TABLE_SEP_RE.match(line) and "|" in line:
            # 孤立的分隔行（坏表格防御）：跳过
            i += 1
            continue
        lm = LIST_RE.match(line)
        if lm:
            flush()
            items = []
            while i < len(lines):
                lm2 = LIST_RE.match(lines[i])
                if not lm2:
                    break
                # 缩进行 = 子列表项（HTML 允许 ul/ol 内直接嵌 ul/ol，不丢内容）
                items.append((len(lm2.group(1).replace("\t", "  ")) > 0, lm2.group(3)))
                i += 1
            ol = bool(re.match(r"\d+\.", lm.group(2)))
            tag = "ol" if ol else "ul"
            out = []
            for sub, t in items:
                txt = parse_inline(t, Placeholder(), file_ids, root)
                out.append(f"<ul><li>{txt}</li></ul>" if sub else f"<li>{txt}</li>")
            body.append(f"<{tag}>" + "".join(out) + f"</{tag}>")
            continue
        if re.match(r"^(\s*)(---|\*\*\*|___)\s*$", line):
            flush(); body.append("<hr>"); i += 1; continue
        blocks.append(line); i += 1
    flush()

    if title is None:
        title = re.sub(r"^\d+-", "", doc_slug)
    # 小节索引：按 h2/h3 切分正文
    secs = []
    cur = []
    cur_head = None
    for line in body:
        m = re.match(r"<h([23]) id=\"([^\"]+)\">", line)
        if m and cur_head is not None:
            secs.append((cur_head[0], cur_head[1], "".join(cur)))
            cur = []
        if m:
            cur_head = (m.group(2), re.sub(r"<[^>]+>", "", line))
        elif cur_head is not None:
            cur.append(line)
    if cur_head is not None:
        secs.append((cur_head[0], cur_head[1], "".join(cur)))
    return title, "\n".join(body), secs, doc_slug


def collect_files(root: Path):
    """(显示组名, [(slug, 显示名, 文件)])；排序：导读 → 大纲 → 三卷 → 附录 → 配套。"""
    groups = {}
    for p in sorted(root.iterdir()):
        if p.is_file() and p.suffix == ".md":
            key = {"README.md": "00-导读", "00-大纲.md": "01-全书大纲",
                   "答案与提示.md": "90-答案与提示", "验证说明.md": "91-验证说明"}.get(p.name)
            if key:
                groups.setdefault(key, []).append(p)
        elif p.is_dir():
            key = {"第1卷-启蒙与概念": "10-", "第2卷-核心与进阶": "20-",
                   "第3卷-工程与思想": "30-", "附录": "40-"}.get(p.name, "80-") + p.name
            groups.setdefault(key, []).extend(sorted(p.glob("*.md")))
    return [(k.split("-", 1)[1] if k[:2].isdigit() else k, v)
            for k, v in sorted(groups.items())]


def build_index(all_secs):
    """[(file_slug, 文件标题, [(sec_id, sec_head, 文本)])] → JSON 数组。"""
    idx = []
    for fslug, ftitle, secs in all_secs:
        if not secs:
            continue
        for sec_id, sec_head, sec_body in secs:
            text = re.sub(r"<[^>]+>", "", sec_body)
            text = re.sub(r"\s+", " ", text).strip()
            idx.append([fslug, ftitle, sec_id, sec_head, text[:300]])
    return idx


def main() -> int:
    ap = argparse.ArgumentParser(description="离线教学站点生成器（建议 C10）")
    ap.add_argument("root", nargs="?", default=None, help="教程根目录（默认 docs/中文仓颉程序设计）")
    ap.add_argument("-o", "--out", default=None, help="输出 HTML（默认 教程根/../教学站点.html）")
    ap.add_argument("--title", default="中文仓颉程序设计（离线教学站点）")
    args = ap.parse_args()

    repo = Path(__file__).resolve().parent.parent
    root = Path(args.root) if args.root else repo / "docs" / "中文仓颉程序设计"
    if not root.is_dir():
        print(f"教程根不存在：{root}", file=sys.stderr)
        return 1
    out = Path(args.out) if args.out else root.parent / "教学站点.html"

    kws = load_keyword_sets()
    file_ids = {p.stem: p.stem for p in root.rglob("*.md")}

    nav, all_secs, contents = [], [], []
    for group, files in collect_files(root):
        items = []
        for f in files:
            ftitle, fbody, secs, fslug = render_doc(f, kws, file_ids, root)
            items.append((f.stem, ftitle))
            contents.append(f'<section id="{esc(fslug)}"><h1>{esc(ftitle)}</h1>{fbody}</section>')
            all_secs.append((fslug, ftitle, secs))
        nav.append((group, items))

    idx = build_index(all_secs)
    nav_html = []
    for group, items in nav:
        lis = "".join(f'<li><a href="#{esc(i)}">{esc(t)}</a></li>' for i, t in items)
        nav_html.append(f'<details open><summary>{esc(group)}</summary><ul>{lis}</ul></details>')

    index_json = json.dumps(idx, ensure_ascii=False)
    page = PAGE_TEMPLATE.format(
        title=esc(args.title), nav="\n".join(nav_html), main="\n".join(contents),
        index=index_json)
    out.write_text(page, encoding="utf-8")
    n_files = sum(len(v) for _, v in nav)
    n_secs = len(idx)
    print(f"教学站点已生成：{out}（{n_files} 文件 / {n_secs} 小节 / {out.stat().st_size // 1024} KB）")
    return 0


PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
:root {{ --bd:#d8dee4; --fg:#1f2328; --ac:#0969da; --code:#f6f8fa; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; font:15px/1.7 "PingFang SC","Microsoft YaHei",system-ui,sans-serif; color:var(--fg); }}
header {{ position:sticky; top:0; z-index:5; background:#fff; border-bottom:1px solid var(--bd);
         padding:10px 18px; display:flex; align-items:center; gap:14px; }}
header h1 {{ font-size:17px; margin:0; white-space:nowrap; }}
#search {{ flex:1; max-width:520px; padding:7px 12px; border:1px solid var(--bd); border-radius:8px; font-size:14px; }}
#wrap {{ display:flex; }}
nav {{ width:260px; flex:0 0 260px; padding:14px; border-right:1px solid var(--bd); overflow:auto;
       position:sticky; top:47px; height:calc(100vh - 47px); font-size:14px; }}
nav summary {{ cursor:pointer; font-weight:600; margin:6px 0 4px; }}
nav ul {{ list-style:none; margin:0 0 8px; padding-left:8px; }}
nav a {{ color:var(--fg); text-decoration:none; display:block; padding:2px 6px; border-radius:6px; }}
nav a:hover, nav a.active {{ background:#ddf4ff; color:var(--ac); }}
main {{ flex:1; min-width:0; padding:20px 30px 80px; max-width:1000px; }}
section {{ display:none; }}
section.on {{ display:block; }}
h1 {{ font-size:26px; border-bottom:2px solid var(--bd); padding-bottom:8px; margin:8px 0 20px; }}
h2 {{ font-size:21px; margin:26px 0 10px; border-bottom:1px solid #eaeef2; padding-bottom:4px; }}
h3 {{ font-size:17px; margin:20px 0 8px; }}
h4 {{ font-size:15px; margin:16px 0 6px; }}
h2[id], h3[id], h4[id] {{ scroll-margin-top:56px; }}
p {{ margin:8px 0; }}
table {{ border-collapse:collapse; margin:10px 0; display:block; overflow-x:auto; max-width:100%; }}
th, td {{ border:1px solid var(--bd); padding:6px 10px; font-size:14px; text-align:left; }}
th {{ background:#f6f8fa; font-weight:600; }}
tr:nth-child(even) td {{ background:#fbfcfd; }}
pre {{ background:var(--code); border:1px solid var(--bd); border-radius:8px; padding:10px 14px;
      overflow-x:auto; font:13px/1.6 "JetBrains Mono",Consolas,monospace; }}
code {{ font:13px/1.6 "JetBrains Mono",Consolas,monospace; background:#f0f2f5; padding:1px 5px;
       border-radius:4px; }}
pre code {{ background:none; padding:0; }}
pre .k {{ color:#cf222e; font-weight:600; }}
pre .s {{ color:#0a3069; }}
pre .c {{ color:#6e7781; font-style:italic; }}
pre .n {{ color:#0550ae; }}
blockquote {{ margin:10px 0; padding:6px 16px; border-left:4px solid var(--ac);
             background:#f6f8fa; border-radius:0 8px 8px 0; color:#57606a; }}
hr {{ border:none; border-top:2px solid var(--bd); margin:18px 0; }}
#results {{ position:fixed; right:20px; top:56px; width:420px; max-height:70vh; overflow:auto;
            background:#fff; border:1px solid var(--bd); border-radius:10px; box-shadow:0 6px 24px #0003;
            padding:8px; display:none; z-index:9; font-size:14px; }}
#results .hit {{ padding:6px 10px; border-radius:8px; cursor:pointer; }}
#results .hit:hover {{ background:#ddf4ff; }}
#results .hit small {{ color:#57606a; display:block; }}
#toTop {{ position:fixed; right:18px; bottom:18px; display:none; background:var(--ac); color:#fff;
         border:none; border-radius:50%; width:40px; height:40px; font-size:18px; cursor:pointer; }}
@media (max-width:900px) {{ nav {{ display:none; }} }}
</style>
</head>
<body>
<header>
  <h1>{title}</h1>
  <input id="search" type="search" placeholder="搜索章节（输入后按 Enter 跳转第一个结果）">
</header>
<div id="wrap">
<nav id="toc">{nav}</nav>
<main id="main">{main}</main>
</div>
<div id="results"></div>
<button id="toTop" title="回到顶部">↑</button>
<script>
const INDEX = {index};
const $ = id => document.getElementById(id);
const secs = document.querySelectorAll("#main section");
const byId = {{}};
secs.forEach(s => {{ byId[s.id] = s; }});
const navA = document.querySelectorAll("nav a");
let active = null;

function show(id, scroll) {{
  secs.forEach(s => s.classList.toggle("on", s.id === id));
  navA.forEach(a => a.classList.toggle("active", a.getAttribute("href") === "#" + id));
  active = id;
  if (scroll) location.hash = id;
}}
// 初始显示第一组第一个文件
if (location.hash) {{
  const h = decodeURIComponent(location.hash.slice(1));
  if (byId[h]) show(h, false);
}} else if (navA.length) {{
  show(navA[0].getAttribute("href").slice(1), false);
}}
navA.forEach(a => a.addEventListener("click", () => show(a.getAttribute("href").slice(1), true)));
window.addEventListener("hashchange", () => {{
  const h = decodeURIComponent(location.hash.slice(1));
  if (byId[h]) show(h, false);
}});

const q = $("search"), box = $("results");
q.addEventListener("input", () => {{
  const k = q.value.trim().toLowerCase();
  if (!k) {{ box.style.display = "none"; return; }}
  const hits = INDEX.filter(x => (x[1] + " " + x[3] + " " + x[4]).toLowerCase().includes(k)).slice(0, 20);
  box.innerHTML = hits.length
    ? hits.map((x, i) => `<div class="hit" data-i="${{i}}"><b>${{esc(x[3])}}</b><small>${{esc(x[1])}} — ${{esc(x[4].slice(0, 90))}}…</small></div>`).join("")
    : `<div class="hit">无匹配「${{esc(q.value)}}」</div>`;
  box.style.display = "block";
}});
function esc(s) {{ return s.replace(/[&<>"']/g, c => ({{"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}})[c]); }}
box.addEventListener("click", e => {{
  const hit = e.target.closest(".hit");
  if (!hit || hit.dataset.i === undefined) return;
  const x = INDEX[+hit.dataset.i];
  show(x[0], false);                      // x[0] = 文件锚点（INDEX 第一列）
  const el = document.getElementById(x[2]);
  if (el) el.scrollIntoView({{ behavior: "smooth", block: "start" }});
}});
q.addEventListener("keydown", e => {{
  if (e.key === "Enter") {{
    const first = box.querySelector(".hit[data-i]");
    if (first) first.click();
  }}
}});
$("toTop").addEventListener("click", () => window.scrollTo({{ top: 0, behavior: "smooth" }}));
window.addEventListener("scroll", () => {{
  $("toTop").style.display = window.scrollY > 600 ? "block" : "none";
}});
</script>
</body>
</html>
"""


if __name__ == "__main__":
    sys.exit(main())
