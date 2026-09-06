#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""标识符字符类区间表生成器（P-7：分词器对齐 cjc 的 XID 语义）。

cjc 1.0.5 实测接受集 = UAX #31 XID 规则：
  - 首字符：字母类（L）/ Nl / Other_ID_Start（中文、假名、谚文、西里尔、
    阿拉伯、天城文、拉丁扩展、々・ー 等全部通过）；
  - 续字符：追加 Mn（组合音标，实测 café+U+0301 词中通过）/ Mc / Nd / Pc
    / Other_ID_Continue（U+00B7 等）；
  - 拒绝：Zs（全角空格）、So（emoji）、Pd（—）、No（²）、Po（・ U+30FB）开头。

数据 = Unicode 15.0 ID_Start / ID_Continue（UAX #31 的 XID 前身，多出少数
NFKC 归一化例外字符，对语言包词表影响可忽略；键字符有 verify-lang-packs
门禁兜底）。ASCII 字母/数字/下划线由 zhc 源码显式处理，表只收 >= U+0080。

用法：python3 tools/gen_xid.py > zhc/src/xid.cj
"""
import sys
import unicodedata

OTHER_ID_START = {0x1885, 0x1886, 0x2118, 0x212E, 0x309B, 0x309C}
OTHER_ID_CONT = {0x00B7, 0x0387} | set(range(0x1369, 0x1372)) | {0x19DA}


def id_start(cp):
    if cp in OTHER_ID_START:
        return True
    cat = unicodedata.category(chr(cp))
    return cat[0] == "L" or cat == "Nl"


def id_continue(cp):
    if id_start(cp):
        return True
    if cp in OTHER_ID_CONT:
        return True
    cat = unicodedata.category(chr(cp))
    return cat in ("Mn", "Mc", "Nd", "Pc")


def ranges(pred):
    out = []
    cp = 0x80
    while cp <= 0x10FFFF:
        if pred(cp):
            s = cp
            while cp + 1 <= 0x10FFFF and pred(cp + 1):
                cp += 1
            out.append((s, cp))
        cp += 1
    return out


def emit(name, rs):
    flat = []
    for s, e in rs:
        flat.append(s)
        flat.append(e)
    print("let %s: Array<Int64> = [" % name)
    for i in range(0, len(flat), 8):
        chunk = flat[i:i + 8]
        print("    %s," % ", ".join("0x%X" % v for v in chunk))
    print("]")


def main():
    rs_start = ranges(id_start)
    rs_cont = ranges(id_continue)
    print("package zhc")
    print("")
    print("// 标识符字符类区间表（生成物）：python3 tools/gen_xid.py > zhc/src/xid.cj")
    print("// （勿手改；数据 Unicode 15.0 ID_Start / ID_Continue，>= U+0080，升序扁平")
    print("//  [s0,e0,s1,e1,...]；ASCII 字母/数字/下划线由调用方显式处理）")
    print("// cjc 1.0.5 实测接受集 = UAX #31 XID 语义（实测矩阵见 tools/gen_xid.py 头注）：")
    print("//   首字符拒绝全角空格/emoji/—/²/・，续字符接受组合音标（Mn）。")
    print("")
    emit("XID_START_RANGES", rs_start)
    print("")
    emit("XID_CONT_RANGES", rs_cont)
    print("")
    print("/** 区间表二分查找：表为升序扁平 [s0,e0,s1,e1,...] 的 Int64 区间。 */")
    print("private func inRanges(t: Array<Int64>, v: Rune): Bool {")
    print("    if (t.size == 0) {")
    print("        return false")
    print("    }")
    print("    var lo: Int64 = 0")
    print("    var hi: Int64 = t.size / 2 - 1")
    print("    while (lo <= hi) {")
    print("        let mid = (lo + hi) / 2")
    print("        let s = Rune(t[mid * 2])")
    print("        let e = Rune(t[mid * 2 + 1])")
    print("        if (v < s) {")
    print("            hi = mid - 1")
    print("        } else if (v > e) {")
    print("            lo = mid + 1")
    print("        } else {")
    print("            return true")
    print("        }")
    print("    }")
    print("    return false")
    print("}")
    print("")
    print("/** XID_Start（含 ASCII 字母/下划线之外的 Unicode 首字符）。 */")
    print("public func isXidStart(r: Rune): Bool {")
    print("    return inRanges(XID_START_RANGES, r)")
    print("}")
    print("")
    print("/** XID_Continue（首字符集 + 数字 + 组合音标等续字符）。 */")
    print("public func isXidPart(r: Rune): Bool {")
    print("    return inRanges(XID_CONT_RANGES, r)")
    print("}")


if __name__ == "__main__":
    main()
