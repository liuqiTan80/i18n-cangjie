#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify-i18n-docs.py —— 文档多语言同步门禁（无 SDK 依赖，Python ≥3.8）。

机制（与 §19 翻译集中管理同思路，源文件 hash64 指纹驱动）：
  - docs/i18n/<语言>/*.md 为受管译文，首行须携带同步锚点：
      <!-- zhc-i18n 源: <相对仓库根的源路径> 基线: <16位hash64> 时间: YYYY-MM-DD -->
  - 指纹一致 = 同步；源文件已改 = 落后（失败，提示更新译文）；
    源不存在 = 源缺失（失败，防僵尸译文）；
  - 译文正文须保留语言导航（链接回根 README），保证用户可切换；
  - docs/i18n/ 根层的 zh 页面（如本方案 README.md）为正本，不参与跟踪。
  - hash64 算法复用 tools/share_server.py 的 zhc_hash64（zhc cache.cj 同款），
    双端（文档/翻译资源中心）共用同一指纹体系。

用法：python3 scripts/verify-i18n-docs.py
退出码：0 = 全部同步；1 = 有落后/缺失/格式问题。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N_DIR = os.path.join(ROOT, "docs", "i18n")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from share_server import zhc_hash64  # noqa: E402

HEADER_RE = re.compile(
    r"^<!--\s*zhc-i18n\s+源:\s*(?P<src>[^\s]+)\s+基线:\s*(?P<base>[0-9a-f]{16})"
    r"(?:\s+时间:\s*(?P<time>\S+))?\s*-->\s*$")


def tracked_docs():
    """收集受管译文：docs/i18n/<语言>/*.md（根层 zh 正本跳过）。"""
    out = []
    if not os.path.isdir(I18N_DIR):
        return out
    for lang in sorted(os.listdir(I18N_DIR)):
        lang_dir = os.path.join(I18N_DIR, lang)
        if not os.path.isdir(lang_dir) or lang.startswith("."):
            continue
        for name in sorted(os.listdir(lang_dir)):
            if name.endswith(".md"):
                out.append(os.path.join(lang_dir, name))
    return out


def main():
    docs = tracked_docs()
    if not docs:
        print("docs/i18n/ 下无受管译文（<语言>/*.md）")
        return 1
    fails = 0
    for path in docs:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as f:
            head = f.readline().strip()
            body = f.read()
        m = HEADER_RE.match(head)
        if not m:
            fails += 1
            print("【头缺失】%s：首行无 zhc-i18n 同步锚点" % rel)
            continue
        src_rel = m.group("src")
        expected = m.group("base")
        src_abs = os.path.join(ROOT, src_rel)
        if not os.path.exists(src_abs):
            fails += 1
            print("【源缺失】%s：源文件 %s 不存在（僵尸译文？）" % (rel, src_rel))
            continue
        with open(src_abs, "rb") as f:
            actual = zhc_hash64(f.read())
        # 导航检查：正文须保留语言切换能力——回根 README，或指向其他语言页
        if not (re.search(r"\.\./\.\./README\.md\)", body)
                or re.search(r"\.\./(?:en|fr|de|es|ko|ja|ru)/README\.md\)", body)):
            fails += 1
            print("【导航缺失】%s：正文缺少语言导航链接（根 README 或其他语言页）" % rel)
            continue
        if actual == expected:
            print("同步：%s（源 %s @%s）" % (rel, src_rel, expected))
        else:
            fails += 1
            print("【落后】%s：源 %s 已更新（期望基线 %s，实际 %s）——"
                  "请对照更新译文后刷新头部锚点" % (rel, src_rel, expected, actual))
    if fails == 0:
        print("=== verify-i18n-docs：%d 个译文全部同步 ===" % len(docs))
        return 0
    print("=== verify-i18n-docs：%d 项失败（共 %d 个译文） ===" % (fails, len(docs)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
