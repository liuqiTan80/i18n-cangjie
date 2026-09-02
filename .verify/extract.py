#!/usr/bin/env python3
# 抽取 docs/中文仓颉程序设计/ 全部 cangjie 代码块，分类并保存为 .zc 文件
# 环境变量：VERIFY_ROOT = 工作目录（产物 src/ 的父目录，默认脚本所在目录）
import os
import re
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent / "docs" / "中文仓颉程序设计"
OUT = pathlib.Path(os.environ.get("VERIFY_ROOT", HERE)) / "src"

OUT.mkdir(parents=True, exist_ok=True)

BLOCK_RE = re.compile(r"```cangjie\n(.*?)```", re.S)

blocks = []
for f in sorted(ROOT.rglob("*.md")):
    text = f.read_text(encoding="utf-8")
    for i, m in enumerate(BLOCK_RE.finditer(text)):
        code = m.group(1).strip("\n")
        rel = f.relative_to(ROOT)
        blocks.append((rel, i, code))

print(f"共找到 {len(blocks)} 个 cangjie 代码块")

complete = 0      # 含主函数() 完整程序
official = 0      # 官方对照（直接运行）
topdecl = 0       # 顶层声明，无主函数
fragment = 0      # 片段，需要包装
macro = 0         # 宏包/语法示意（跳过）

for idx, (rel, i, code) in enumerate(blocks):
    if "macro package" in code or "@派生" in code:
        kind = "macro"
        macro += 1
        body = None
    elif "// 官方仓颉" in code or "main()" in code and "主函数()" not in code:
        kind = "official"
        official += 1
        body = code
    elif "主函数()" in code:
        kind = "complete"
        complete += 1
        body = code
    elif re.search(r"^(函数|结构体|类|接口|枚举|导入|常量|可变|扩展|类型|抽象|开放)\b", code, re.M):
        kind = "topdecl"
        topdecl += 1
        body = code + "\n\n主函数() {\n}\n"
    else:
        kind = "fragment"
        fragment += 1
        body = "主函数() {\n" + code + "\n}\n"

    name = f"{idx:03d}-{kind}-{rel.stem}-{i}.zc"
    if body is not None:
        (OUT / name).write_text(body, encoding="utf-8")
    else:
        (OUT / name).write_text(code + "\n", encoding="utf-8")
    print(f"{name:60s} <- {rel} 块#{i}")

print(f"\n统计: complete={complete} official={official} topdecl={topdecl} fragment={fragment} macro={macro}")
