#!/usr/bin/env python3
"""提取教程代码块用到的方言标识符（剔除注释/字符串），检查仓库版词表覆盖"""
import pathlib
import re
import tomllib

base = pathlib.Path("/home/tan80/code/zwCangjie")
repo_lang = base / "zhc/lang-packs/zh"
verify = base / ".verify/src"

# 1. 加载仓库版词表
repo_words = set()
for toml_file in ["stdlib.toml", "module_paths.toml", "keywords.toml"]:
    p = repo_lang / toml_file
    if p.exists():
        with open(p, "rb") as f:
            data = tomllib.load(f)
        for section in data.values():
            if isinstance(section, dict):
                repo_words.update(section.keys())

def strip_code(text: str) -> str:
    """去掉注释和字符串字面量（保留代码主体）"""
    lines = []
    for line in text.splitlines():
        line = re.sub(r"//.*$", "", line)          # 行注释
        line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)  # 双引号字符串
        line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)  # 字符字面量
        lines.append(line)
    return "\n".join(lines)

def cjk_tokens(text: str):
    return set(re.findall(r"[\u4e00-\u9fff][\u4e00-\u9fff0-9_]*", text))

used = set()
for f in verify.glob("*.zc"):
    used |= cjk_tokens(strip_code(f.read_text(encoding="utf-8")))

missing = sorted(w for w in used if w not in repo_words)
print(f"代码 token 数（已剔除注释/字符串）: {len(used)}")
print(f"仓库版词表缺失（需补入仓库版）: {len(missing)}")
for w in missing:
    print(f"  {w}")
