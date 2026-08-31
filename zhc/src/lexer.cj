package zhc

import std.collection.*

/**
 * L0 词法转译器（对应设计 §5.1、§16.1 L0 档）。
 *
 * 阶段 0 实现要点（对应设计 §5.1 实现要求）：
 *   1. token 级替换：自研保守词法器（std.ast 实测项 #2 之前，见 §13）；
 *   2. 整词匹配：仅替换完整标识符 token（`读取全部字符串` 中的 `字符串` 不误改）；
 *   3. 原始标识符透传：`` `让` `` 剥反引号查表后复原为 `` `let` ``；
 *   4. @宏名替换：@ 后标识符只查宏表（§5.1 第 4 条），@ 后遇空白视为无效宏调用并清除标志；
 *   5. 多词关键字：方言侧 `否则如果` 是单个标识符 token，整词查表即可命中
 *      （方言 `否则 如果` 则分两次替换为 `else if`，结果等价，无需前瞻）；
 *   6. 源映射记录：每次实际替换记录 (源偏移, 长度, 原文, 替换文)；
 *      @ 前缀本身不产生映射条目。
 *
 * 字符串/注释/反引号内的内容绝不替换；字符串内的 `${}` 插值段是代码不是文本：
 * 阶段 2 插值态转译（§3.13）——括号栈（`(`/`[`/`{` 配对）确定插值结束的 `}`，
 * 插值段按普通代码规则递归转译；插值态内遇嵌套字符串按普通字符串跳过（保守）。
 *
 * 1.0 适配记录（本机 cjc 1.0.5 实测）：
 *   - String 下标 s[i] 返回 UInt8 字节、size 为字节数、s[a..b] 为字节切片
 *     （中文会被切坏），故本文件全部基于 toRuneArray() 的 Rune 数组操作；
 *   - Rune 字面量是 r'x'（单引号 'x' 已是 String）；
 *   - Rune 无 isLetter/isDigit/isWhitespace，用 isAsciiLetter/isAsciiNumber
 *     加字符比较兜底（XID 全集留待实测项 #4 后收紧）。
 *
 * 偏移单位：阶段 0 使用 Rune 索引（源映射条目 offset/len）；
 * LSP 集成时按 §5.6 折算为 UTF-16 code unit。
 */

public class MapEntry {
    public var offset: Int64
    public var len: Int64
    public var original: String
    public var replacement: String

    public init(offset: Int64, len: Int64, original: String, replacement: String) {
        this.offset = offset
        this.len = len
        this.original = original
        this.replacement = replacement
    }
}

public class TranspileResult {
    public var text: String
    public var map: ArrayList<MapEntry>
    public var total: Int64      // 全部替换计数：词法 + import 路径 + 别名（阶段 2）

    public init(text: String, map: ArrayList<MapEntry>, total: Int64) {
        this.text = text
        this.map = map
        this.total = total
    }
}

/** 方言 → 官方（L0 token 级转译，含 ${} 插值态转译）。 */
public func transpile(src: String, lang: LangPack): TranspileResult {
    let runes = src.toRuneArray()
    let map = ArrayList<MapEntry>()
    let text = transpileCode(runes, 0, runes.size, lang, map)
    return TranspileResult(text, map, map.size)
}

/** 阶段 2 完整管线（§4.1）：② 词法转译（含插值态）→ ③ import 语句态路径替换
 *  → ④ 别名替换（两遍扫描 + 豁免集）；total = 三阶段替换计数之和。
 * 源映射合并（§5.6）：词法条目（源基准）原样，import/别名条目经 backShift
 * 折算到源基准后并入 map（供诊断位置反向还原）。 */
public func transpileFull(src: String, lang: LangPack): TranspileResult {
    let result = transpile(src, lang)
    let importRes = replaceImportPaths(result.text, lang)
    let aliasRes = replaceAliases(importRes.text, lang)
    let merged = mergeMaps(result.map, importRes.map, aliasRes.map)
    return TranspileResult(aliasRes.text, merged, result.map.size + importRes.count + aliasRes.count)
}

/** 代码态转译 [start, end) 区间：关键字/宏/反引号查表，字符串/注释整体保护，
 *  字符串内 `${}` 插值段递归转译（插值态，§3.13）。
 *  递归入口统一，主循环与插值段共用（偏移为 runes 绝对索引，源映射安全）。 */
private func transpileCode(runes: Array<Rune>, start: Int64, end: Int64, lang: LangPack, map: ArrayList<MapEntry>): String {
    var sb = ""
    var i = start
    var atPending = false          // 刚输出过 @，下一个标识符只查宏表

    while (i < end) {
        let ch = runes[i]
        if (ch == r'"') {
            let (piece, next) = scanInterpString(runes, i, end, lang, map)
            sb = "${sb}${piece}"
            i = next
        } else if (ch == r'\'') {
            let (piece, next) = scanQuoted(runes, i, end, r'\'')
            sb = "${sb}${piece}"
            i = next
        } else if (ch == r'/' && i + 1 < end && runes[i + 1] == r'/') {
            let (piece, next) = scanLineComment(runes, i, end)
            sb = "${sb}${piece}"
            i = next
        } else if (ch == r'/' && i + 1 < end && runes[i + 1] == r'*') {
            let (piece, next) = scanBlockComment(runes, i, end)
            sb = "${sb}${piece}"
            i = next
        } else if (ch == r'`') {
            let (piece, mapped, offset, len, next) = scanRawIdent(runes, i, end, lang.keywords)
            sb = "${sb}${piece}"
            if (mapped) {
                map.add(MapEntry(offset, len, String(runes[offset..offset + len]), piece))
            }
            i = next
        } else if (ch == r'@') {
            sb = "${sb}@"
            atPending = true
            i += 1
        } else if (isIdentStart(ch)) {
            var j = i
            while (j < end && isIdentPart(runes[j])) {
                j += 1
            }
            let token = String(runes[i..j])
            let table = if (atPending) { lang.macros } else { lang.keywords }
            let mapped = table.get(token)
            if (mapped != None) {
                sb = "${sb}${mapped.getOrThrow()}"
                map.add(MapEntry(i, j - i, token, mapped.getOrThrow()))
            } else {
                sb = "${sb}${token}"
            }
            atPending = false
            i = j
        } else {
            sb = "${sb}${ch}"
            if (!isSpace(ch)) {
                atPending = false      // @ 后遇非标识符、非空白字符：不再视为宏调用前缀
            }
            i += 1
        }
    }
    return sb
}

/** 扫描 `'...'` 字符/单引号字面量（含反斜杠转义）；未闭合时容错到 end。
 *  public：供 import 语句态（import_path.cj）与别名替换（alias.cj）复用。 */
public func scanQuoted(runes: Array<Rune>, start: Int64, end: Int64, q: Rune): (String, Int64) {
    var j = start + 1
    while (j < end) {
        let c = runes[j]
        if (c == r'\\') {
            j += 2
        } else if (c == q) {
            return (String(runes[start..j + 1]), j + 1)
        } else {
            j += 1
        }
    }
    return (String(runes[start..end]), end)
}

/** 扫描 `"..."` 字面量（阶段 2 插值态，§3.13）：
 *  普通文本原样；遇 `${` 进入插值代码态，括号栈配对找结束 `}`，
 *  插值内容递归调 transpileCode 按代码规则转译（嵌套字符串保守跳过）。 */
private func scanInterpString(runes: Array<Rune>, start: Int64, end: Int64, lang: LangPack, map: ArrayList<MapEntry>): (String, Int64) {
    var sb = ""
    var j = start
    while (j < end) {
        let c = runes[j]
        if (c == r'\\') {
            if (j + 1 < end) {
                sb = "${sb}${runes[j]}${runes[j + 1]}"
                j += 2
            } else {
                sb = "${sb}${runes[j]}"
                j += 1
            }
        } else if (c == r'"') {
            sb = "${sb}${runes[j]}"
            return (sb, j + 1)
        } else if (c == r'$' && j + 1 < end && runes[j + 1] == r'{') {
            // 插值态：扫描到配对的 `}`，内容按代码规则递归转译
            let (endIdx, codeText) = scanInterpCode(runes, j + 2, end, lang, map)
            sb = "${sb}${"${runes[j]}${runes[j + 1]}"}${codeText}${runes[endIdx - 1]}"
            j = endIdx
        } else {
            sb = "${sb}${c}"
            j += 1
        }
    }
    return (sb, end)
}

/** 插值代码态扫描：从 `${` 之后开始，括号栈（`{` 深度 + 字符串/反引号跳过）
 *  确定插值结束的 `}`；返回 (结束位置(配对的 `}` 之后), 插值内容转译结果)。
 *  嵌套字符串按普通字符串跳过（保守，§3.13），注释/反引号同样跳过。 */
private func scanInterpCode(runes: Array<Rune>, start: Int64, end: Int64, lang: LangPack, map: ArrayList<MapEntry>): (Int64, String) {
    var depth = 1
    var j = start
    while (j < end) {
        let c = runes[j]
        if (c == r'"' || c == r'\'') {
            let (_, next) = scanQuoted(runes, j, end, c)
            j = next
        } else if (c == r'`') {
            var k = j + 1
            while (k < end && runes[k] != r'`') {
                k += 1
            }
            j = if (k < end) { k + 1 } else { end }
        } else if (c == r'/' && j + 1 < end && runes[j + 1] == r'/') {
            let (_, next) = scanLineComment(runes, j, end)
            j = next
        } else if (c == r'/' && j + 1 < end && runes[j + 1] == r'*') {
            let (_, next) = scanBlockComment(runes, j, end)
            j = next
        } else if (c == r'{') {
            depth += 1
            j += 1
        } else if (c == r'}') {
            depth -= 1
            j += 1
            if (depth == 0) {
                let codeText = transpileCode(runes, start, j - 1, lang, map)
                return (j, codeText)
            }
        } else {
            j += 1
        }
    }
    // 未闭合插值：容错到 end，仍按代码转译
    let codeText = transpileCode(runes, start, end, lang, map)
    return (end, codeText)
}

/** 扫描 `//` 行注释到行尾或 end（保留换行符）。 */
public func scanLineComment(runes: Array<Rune>, start: Int64, end: Int64): (String, Int64) {
    var j = start + 2
    while (j < end && runes[j] != r'\n') {
        j += 1
    }
    return (String(runes[start..j]), j)
}

/** 扫描块注释（星号斜杠闭合）；未闭合时容错到 end。 */
public func scanBlockComment(runes: Array<Rune>, start: Int64, end: Int64): (String, Int64) {
    var j = start + 2
    while (j + 1 < end) {
        if (runes[j] == r'*' && runes[j + 1] == r'/') {
            return (String(runes[start..j + 2]), j + 2)
        }
        j += 1
    }
    return (String(runes[start..end]), end)
}

/** 扫描反引号原始标识符；内容查表映射（§5.1 第 3 条）。 */
private func scanRawIdent(runes: Array<Rune>, start: Int64, end: Int64, keywords: HashMap<String, String>): (String, Bool, Int64, Int64, Int64) {
    var j = start + 1
    while (j < end && runes[j] != r'`') {
        j += 1
    }
    if (j >= end) {
        return (String(runes[start..end]), false, start, 0, end)
    }
    let inner = String(runes[start + 1..j])
    let mapped = keywords.get(inner)
    if (mapped == None) {
        return (String(runes[start..j + 1]), false, start, 0, j + 1)
    }
    return ("`${mapped.getOrThrow()}`", true, start, j - start + 1, j + 1)
}

/** 标识符起始字符：ASCII 字母、非 ASCII（中文等）或下划线（XID 全集留待实测项 #4 后收紧）。 */
public func isIdentStart(r: Rune): Bool {
    return r.isAsciiLetter() || r >= Rune(128) || r == r'_'
}

/** 标识符后续字符：起始字符外加 ASCII 数字。 */
public func isIdentPart(r: Rune): Bool {
    return r.isAsciiLetter() || r.isAsciiNumber() || r >= Rune(128) || r == r'_'
}

/** 空白字符（@ 后清宏调用标志用）。 */
public func isSpace(r: Rune): Bool {
    return r == r' ' || r == r'\t' || r == r'\n' || r == r'\r'
}
