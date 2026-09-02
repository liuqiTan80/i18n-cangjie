#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zhc 错误信息字典生成器。

从语言包 errors.toml 生成 docs/errors-dictionary.md（供学习者反查）：
  - ["诊断码"] 节 → 按官方错误码排序的完整条目（模板/提示/修复示例）
  - ["消息翻译"] 节 → 消息兜底表（精确/前缀/~ 后缀三级匹配说明）
重复执行可更新，与语言包永不漂移。

用法：python3 tools/gen_error_dict.py [errors.toml 路径] [输出路径]
默认：zhc/lang-packs/zh/errors.toml → docs/errors-dictionary.md
"""
import os
import re
import sys

def parse_toml(path):
    """节名 -> 条目名 -> {字段: 值}（errors.toml 是 [节].[条目] 双级节）。
    附带识别精翻条目：节标题前一行是 `# 人工精翻` 注释（gen_full_errors.py 写入）。"""
    sections = {}
    curated = set()
    cur_section = None
    cur_entry = None
    prev_comment = False
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("#"):
                prev_comment = line == "# 人工精翻"
                continue
            if line.startswith("["):
                m = re.match(r'^\["([^"]+)"\]$', line)
                if m:
                    cur_section = m.group(1)
                    sections.setdefault(cur_section, {})
                    cur_entry = None
                    prev_comment = False
                    continue
                m2 = re.match(r'^\["([^"]+)"\."([^"]+)"\]$', line)
                if m2:
                    cur_section = m2.group(1)
                    cur_entry = m2.group(2)
                    sections.setdefault(cur_section, {})
                    sections[cur_section].setdefault(cur_entry, {})
                    if prev_comment:
                        curated.add(cur_entry)
                    prev_comment = False
                continue
            m3 = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"', line)
            if m3 and cur_entry is not None:
                key = m3.group(1)
                val = m3.group(2).replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')
                sections[cur_section][cur_entry][key] = val
    return sections, curated

def md_escape(text):
    return text.replace("|", "\\|").replace("\n", "<br>")

def build_doc(errors_path):
    sections, curated = parse_toml(errors_path)
    codes = sections.get("诊断码", {})
    msgs = sections.get("消息翻译", {})
    n_curated = len([k for k in codes if k in curated])

    lines = []
    lines.append("# zhc 错误信息字典附录")
    lines.append("")
    lines.append("> 本附录由 `tools/gen_error_dict.py` 从语言包 `errors.toml` 自动生成，"
                 "与教学诊断行为严格一致。")
    lines.append("")
    lines.append("## 使用说明")
    lines.append("")
    lines.append("zhc 把官方编译器（cjc）的错误翻译为中文教学诊断，两级匹配：")
    lines.append("")
    lines.append("1. **诊断码表**（第一优先级）：cjc JSON 诊断的 `DiagKind` 字段"
                 "（1.0.5 实测稳定），如 `sema_mismatched_types`；")
    lines.append("2. **消息翻译表**（兜底）：官方消息原文按 精确 → 最长前缀 → `~` 后缀"
                 "三级匹配；未收录消息原样回退（不崩溃、不瞎译）。")
    lines.append("")
    lines.append("反查方法：看到诊断中的稳定错误码（或官方错误文本），在本附录定位条目，"
                 "阅读教学提示与修复示例。")
    lines.append("")
    lines.append(f"> **翻译质量标注**：本表 {len(codes)} 条中，**{n_curated} 条人工精翻**"
                 "（高频教学场景，措辞与修复示例逐条校对，条目注明「人工精翻」）；"
                 f"其余 {len(codes) - n_curated} 条为 `tools/gen_full_errors.py` "
                 "**自动生成**（模板化措辞，个别可能生硬——修订翻译表后重新生成即可，"
                 "方法见[语言包开发](语言包开发.md)）。")
    lines.append("")

    lines.append(f"## 一、诊断码表（{len(codes)} 条）")
    lines.append("")
    for code in sorted(codes.keys()):
        entry = codes[code]
        template = entry.get("消息模板", "")
        tip = entry.get("教学提示", "")
        fix = entry.get("修复示例", "")
        badge = "人工精翻" if code in curated else "自动生成"
        lines.append(f"### `{code}`")
        lines.append("")
        lines.append(f"- **翻译**：{badge}")
        lines.append(f"- **中文消息**：{template}")
        if tip:
            lines.append(f"- **教学提示**：{tip}")
        if fix:
            lines.append("- **修复示例**（方言，可直接粘贴）：")
            lines.append("")
            lines.append("```cangjie")
            for fl in fix.split("\n"):
                lines.append(fl)
            lines.append("```")
        lines.append("")
        lines.append("---")
        lines.append("")

    lines.append(f"## 二、消息翻译表（{len(msgs)} 条，兜底）")
    lines.append("")
    lines.append("| 官方消息（键） | 匹配方式 | 中文模板 | 教学提示 |")
    lines.append("|---|---|---|---|")
    for msg_key in sorted(msgs.keys()):
        entry = msgs[msg_key]
        method = "~ 后缀" if msg_key.startswith("~") else "精确/最长前缀"
        display = msg_key if len(msg_key) <= 40 else msg_key[:37] + "..."
        lines.append(f"| `{md_escape(display)}` | {method} | "
                     f"{md_escape(entry.get('消息模板', ''))} | "
                     f"{md_escape(entry.get('教学提示', ''))} |")
    lines.append("")
    lines.append("## 三、回退策略")
    lines.append("")
    lines.append("- 未收录的错误码/消息：**原样输出官方文本**，不翻译、不崩溃；")
    lines.append("- 模板占位符 `{q0}`/`{q1}`：从完整消息提取引号对（`'...'`）捕获，"
                 "避免前缀截断把闭引号当开引号；")
    lines.append("- 模板无占位符时动态拼接残段，保证信息不丢失；")
    lines.append("- 类型名本地化（`Int64` → `整数`、`Enum-Option<Int64>` → "
                 "`枚举-选项<整数>`）在翻译后应用。")
    lines.append("")
    return "\n".join(lines)

def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    errors_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        repo, "zhc", "lang-packs", "zh", "errors.toml")
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(repo, "docs", "errors-dictionary.md")
    doc = build_doc(errors_path)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(doc)
    print(f"错误字典生成：{out_path}（诊断码 + 消息翻译 + 回退策略）")

if __name__ == "__main__":
    main()
