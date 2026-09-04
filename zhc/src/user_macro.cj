package zhc

import std.collection.*
import std.fs.*

/**
 * 用户自定义宏（方言模板宏）
 *
 * 宏定义文件「宏.zcm」（或 macros.zcm）放在方言源文件同目录或项目根：
 *
 *     @断言(条件, 消息) {
 *         如果 (非(条件)) {
 *             打印行(消息)
 *         }
 *     }
 *
 * 源文件里调用 @断言(数 > 0, "出错")：实参按「整词」替换进宏体模板，模板仍为
 * 方言代码，再走正常转译链——用户可完全用方言书写可复用代码片段。
 *
 * 规则：
 *  - 宏体里字符串字面量与注释中的同名文本不替换（与方言词转译的保护语义一致）；
 *    参数应出现在代码位置；
 *  - 调用必须带括号（@名(...)），不带括号的 @名 视为官方宏照旧不展开；
 *  - 宏体里可再调用其他用户宏（嵌套展开，上限 8 层防递归死循环）；
 *  - 复合表达式实参自动包括号防优先级错位（单 token 实参原样）；
 *  - 宏名与语言包宏表同名时打印警告，用户宏优先展开。
 *
 * 展开发生在转译之前；展开产物的行数变化会让源文件行号与展开后视图不一致
 * （宏体多行时诊断行号按展开后文本计，v1 取舍）。
 */

// ── 界面消息（ui_translations_en/ru.py 同步；zh 回退中文原句）────────────────
/** 单个用户宏定义：形参名表（原样标识符）+ 宏体模板（原样方言代码）。 */
public class UserMacro {
    public var params: ArrayList<String>
    public var body: String
    public init(params: ArrayList<String>, body: String) {
        this.params = params
        this.body = body
    }
}

/**
 * 展开用户宏：srcPath 文件同目录（或项目根）存在 宏.zcm/macros.zcm 时解析并
 * 展开其中全部调用；无定义文件返回原样 Some(src)；解析/展开错误已打印，返回 None。
 */
public func expandUserMacros(src: String, lang: LangPack, srcPath: String): ?String {
    let dir = dirOf(srcPath)
    var macros = HashMap<String, UserMacro>()
    let macroPathOpt = findUserMacroFile(dir)
    match (macroPathOpt) {
        case None => return Some(src)
        case Some(macroPath) =>
            if (!parseUserMacroFile(readTextFile(macroPath), lang, macroPath, macros)) {
                return None
            }
    }
    // 嵌套展开：每轮整文本替换一轮，8 轮内收敛；仍有替换则报递归深度错
    var cur = src
    var round: Int64 = 0
    while (true) {
        let seen = ArrayList<String>()
        match (expandCallsOnce(cur, macros, srcPath, seen)) {
            case None => return None
            case Some(t) =>
                if (seen.isEmpty()) {
                    return Some(cur)
                }
                round += 1
                if (round >= 8) {
                    // 行号不报：单轮展开为全文替换，无法定位到单一调用行（原实现
                    // 恒报第 1 行有误导性），改为只报文件与宏名
                    println(uiTextF("{0}：{1}", [srcPath,
                        uiTextF("@{0} 展开嵌套超过 8 层（疑似递归调用），已终止", [seen.get(seen.size - 1).getOrThrow()])]))
                    return None
                }
                cur = t
        }
    }
    return None
}

/** 查找宏定义文件：源文件同目录 → 项目根；文件名 宏.zcm 或 macros.zcm。 */
public func findUserMacroFile(dir: String): ?String {
    let names = ["宏.zcm", "macros.zcm"]
    let direct = lookupMacroFile(dir, names)
    match (direct) {
        case Some(p) => return Some(p)
        case None => ()
    }
    let rootOpt = findProjectRoot(dir)
    if (rootOpt == None) {
        return None
    }
    let root = rootOpt.getOrThrow()
    if (root == dir) {
        return None
    }
    return lookupMacroFile(root, names)
}

private func lookupMacroFile(dir: String, names: Array<String>): ?String {
    for (name in names) {
        let p = "${dir}/${name}"
        if (exists(Path(p))) {
            return Some(p)
        }
    }
    return None
}

/** 解析宏定义文件文本到 macros；错误已打印返回 false（定义本身已加入部分保留）。 */
public func parseUserMacroFile(text: String, lang: LangPack, macroPath: String,
                               macros: HashMap<String, UserMacro>): Bool {
    let runes = text.toRuneArray()
    let n = runes.size
    var i: Int64 = 0
    if (i < n && runes[0] == Rune(0xFEFF)) {
        i = 1                       // BOM
    }
    while (i < n) {
        let c = runes[i]
        if (isSpace(c)) {
            i += 1
        } else if (c == r'/' && i + 1 < n && runes[i + 1] == r'/') {
            i = skipLineRunes(runes, i + 2, n)
        } else if (c == r'/' && i + 1 < n && runes[i + 1] == r'*') {
            i = skipBlockRunes(runes, i + 2, n)
        } else if (c == r'@') {
            if (i + 1 >= n || !isIdentStart(runes[i + 1])) {
                return defErr(runes, macroPath, i, uiTextF("@ 后须紧跟宏名（标识符）", []))
            }
            let nameStart = i + 1
            var k = nameStart
            while (k < n && isIdentPart(runes[k])) {
                k += 1
            }
            let name = String(runes[nameStart..k])
            k = skipSpaces(runes, k, n)
            if (k >= n || runes[k] != r'(') {
                return defErr(runes, macroPath, if (k < n) { k } else { k - 1 }, uiTextF("宏头不完整：期望 @宏名(形参, …) { 宏体 }", []))
            }
            k += 1
            // 形参表（可为空）：标识符逗号分隔至配对 ')'
            let params = ArrayList<String>()
            var done = false
            while (!done) {
                k = skipSpaces(runes, k, n)
                if (k >= n) {
                    return defErr(runes, macroPath, k - 1, uiTextF("形参表缺少配对的 )", []))
                }
                if (runes[k] == r')') {
                    k += 1
                    done = true
                    continue
                }
                if (!isIdentStart(runes[k])) {
                    return defErr(runes, macroPath, k, uiTextF("形参 {0} 不是合法标识符", [String(runes[k..k + 1])]))
                }
                let ps = k
                while (k < n && isIdentPart(runes[k])) {
                    k += 1
                }
                params.add(String(runes[ps..k]))
                k = skipSpaces(runes, k, n)
                if (k >= n) {
                    return defErr(runes, macroPath, k - 1, uiTextF("形参表缺少配对的 )", []))
                }
                if (runes[k] == r')') {
                    k += 1
                    done = true
                } else if (runes[k] == r',') {
                    k += 1
                } else {
                    return defErr(runes, macroPath, k, uiTextF("形参 {0} 不是合法标识符", [String(runes[k..k + 1])]))
                }
            }
            // 宏体：'{' 起配对 '}'（体可含字符串/注释中的花括号）
            k = skipSpaces(runes, k, n)
            if (k >= n || runes[k] != r'{') {
                return defErr(runes, macroPath, if (k < n) { k } else { k - 1 }, uiTextF("宏头不完整：期望 @宏名(形参, …) { 宏体 }", []))
            }
            let bodyStart = k + 1
            let bodyEnd = scanBodyEndRunes(runes, bodyStart, n)
            if (bodyEnd < 0) {
                return defErr(runes, macroPath, bodyStart, uiTextF("宏体缺少配对的 }", []))
            }
            if (macros.contains(name)) {
                return defErr(runes, macroPath, nameStart, uiTextF("宏 @{0} 重复定义", [name]))
            }
            if (lang.macros.contains(name)) {
                let official = lang.macros.get(name).getOrThrow()
                println(uiTextF("{0} 第 {1} 行：{2}", [macroPath, lineOf(runes, nameStart).toString(),
                    uiTextF("警告：用户宏 @{0} 与语言包宏表同名（内置转译 @{0} → {1}），用户宏优先展开", [name, official])]))
            }
            macros.add(name, UserMacro(params, String(runes[bodyStart..bodyEnd])))
            i = bodyEnd + 1
        } else {
            return defErr(runes, macroPath, i, uiTextF("无法识别的内容（宏文件只允许注释、空白与 @宏定义）", []))
        }
    }
    return true
}

/** 定义错误：打印「路径 第 N 行：描述」，返回 false。 */
private func defErr(runes: Array<Rune>, path: String, at: Int64, desc: String): Bool {
    println(uiTextF("{0} 第 {1} 行：{2}", [path, lineOf(runes, at).toString(), desc]))
    return false
}

/** 扫描器原语：全部返回「跳过后的游标位置」（字符串/注释原样保留，不做替换）。 */

/** 行注释：跳过到行尾（含换行）。 */
private func skipLineRunes(runes: Array<Rune>, start: Int64, n: Int64): Int64 {
    var j = start
    while (j < n) {
        if (runes[j] == r'\n') {
            return j + 1
        }
        j += 1
    }
    return n
}

/** 块注释：跳过到配对星斜杠；未闭合返回 n（当作注释延伸到文件尾）。 */
private func skipBlockRunes(runes: Array<Rune>, start: Int64, n: Int64): Int64 {
    var j = start
    while (j + 1 < n) {
        if (runes[j] == r'*' && runes[j + 1] == r'/') {
            return j + 2
        }
        j += 1
    }
    return n
}

/** 字符字面量：' 到配对 '（含 \ 转义）。start 位于开引号后。 */
private func skipCharRunes(runes: Array<Rune>, start: Int64, n: Int64): Int64 {
    var j = start
    while (j < n) {
        if (runes[j] == r'\\') {
            j += 2
            if (j > n) {
                return n
            }
        } else if (runes[j] == r'\'') {
            return j + 1
        } else {
            j += 1
        }
    }
    return n
}

/** 字符串字面量：配对 "（含 \ 转义与 ${…} 插值段，插值段内可再嵌套字符串）。 */
private func skipStringRunes(runes: Array<Rune>, start: Int64, n: Int64): Int64 {
    var j = start
    while (j < n) {
        let c = runes[j]
        if (c == r'\\') {
            j += 2
            if (j > n) {
                return n
            }
        } else if (c == r'"') {
            return j + 1
        } else if (c == r'$' && j + 1 < n && runes[j + 1] == r'{') {
            j = skipInterpRunes(runes, j + 2, n)
        } else {
            j += 1
        }
    }
    return n
}

/** 插值代码段：${ 后到配对 }，按代码规则（" 字符串、' 字符、注释可嵌套）。 */
private func skipInterpRunes(runes: Array<Rune>, start: Int64, n: Int64): Int64 {
    var depth: Int64 = 1
    var j = start
    while (j < n) {
        let c = runes[j]
        if (c == r'{') {
            depth += 1
            j += 1
        } else if (c == r'}') {
            depth -= 1
            j += 1
            if (depth == 0) {
                return j
            }
        } else if (c == r'"') {
            j = skipStringRunes(runes, j + 1, n)
        } else if (c == r'\'') {
            j = skipCharRunes(runes, j + 1, n)
        } else if (c == r'/' && j + 1 < n && runes[j + 1] == r'/') {
            j = skipLineRunes(runes, j + 2, n)
        } else if (c == r'/' && j + 1 < n && runes[j + 1] == r'*') {
            j = skipBlockRunes(runes, j + 2, n)
        } else {
            j += 1
        }
    }
    return n
}

/** 宏体结束位置：从体首扫描配对 '}'（字符串/注释/字符字面量不参与配对）；缺配对返回 -1。 */
private func scanBodyEndRunes(runes: Array<Rune>, start: Int64, n: Int64): Int64 {
    var depth: Int64 = 1
    var j = start
    while (j < n) {
        let c = runes[j]
        if (c == r'"') {
            j = skipStringRunes(runes, j + 1, n)
        } else if (c == r'\'') {
            j = skipCharRunes(runes, j + 1, n)
        } else if (c == r'/' && j + 1 < n && runes[j + 1] == r'/') {
            j = skipLineRunes(runes, j + 2, n)
        } else if (c == r'/' && j + 1 < n && runes[j + 1] == r'*') {
            j = skipBlockRunes(runes, j + 2, n)
        } else if (c == r'{') {
            depth += 1
            j += 1
        } else if (c == r'}') {
            depth -= 1
            if (depth == 0) {
                return j
            }
            j += 1
        } else {
            j += 1
        }
    }
    return -1
}

private func skipSpaces(runes: Array<Rune>, start: Int64, n: Int64): Int64 {
    var j = start
    while (j < n && isSpace(runes[j])) {
        j += 1
    }
    return j
}

/** rune 索引所在行号（1 起）。 */
public func lineOf(runes: Array<Rune>, at: Int64): Int64 {
    var line: Int64 = 1
    var i: Int64 = 0
    while (i < at && i < runes.size) {
        if (runes[i] == r'\n') {
            line += 1
        }
        i += 1
    }
    return line
}

/** 段首尾空白削减，返回内层子串。 */
private func trimRunes(runes: Array<Rune>, s: Int64, e: Int64): String {
    var a = s
    var b = e
    while (a < b && isSpace(runes[a])) {
        a += 1
    }
    while (b > a && isSpace(runes[b - 1])) {
        b -= 1
    }
    return String(runes[a..b])
}

/**
 * 调用实参解析：'(' 后按顶层逗号切段（括号嵌套/字符串/字符/注释感知）；
 * 未配对 ')' 返回 None（当普通文本原样保留，不误报）。
 */
public func parseCallArgsRunes(runes: Array<Rune>, parenIdx: Int64, n: Int64): ?(ArrayList<String>, Int64) {
    var depth: Int64 = 1
    var j = parenIdx + 1
    var segStart = j
    let args = ArrayList<String>()
    while (j < n) {
        let c = runes[j]
        if (c == r'"') {
            j = skipStringRunes(runes, j + 1, n)
        } else if (c == r'\'') {
            j = skipCharRunes(runes, j + 1, n)
        } else if (c == r'/' && j + 1 < n && runes[j + 1] == r'/') {
            j = skipLineRunes(runes, j + 2, n)
        } else if (c == r'/' && j + 1 < n && runes[j + 1] == r'*') {
            j = skipBlockRunes(runes, j + 2, n)
        } else if (c == r'(') {
            depth += 1
            j += 1
        } else if (c == r')') {
            depth -= 1
            if (depth == 0) {
                args.add(trimRunes(runes, segStart, j))
                return Some((args, j + 1))
            }
            j += 1
        } else if (c == r',' && depth == 1) {
            args.add(trimRunes(runes, segStart, j))
            j += 1
            segStart = j
        } else {
            j += 1
        }
    }
    return None
}

/**
 * 单轮调用展开：整文本把「命中宏表的 @名(...)」替换为宏体（形参按整词替换，
 * 字符串/注释中的 @调用 与同名文本不处理）；未命中宏表的 @名 原样保留。
 * seen 记录本轮命中的宏名（空 = 无调用，供外层收敛判定）。
 * 实参个数不符等错误已打印，返回 None。
 */
public func expandCallsOnce(text: String, macros: HashMap<String, UserMacro>,
                            srcPath: String, seen: ArrayList<String>): ?String {
    let runes = text.toRuneArray()
    let n = runes.size
    var sb = ""
    var segStart: Int64 = 0
    var i: Int64 = 0
    while (i < n) {
        let c = runes[i]
        if (c == r'"') {
            i = skipStringRunes(runes, i + 1, n)
        } else if (c == r'\'') {
            i = skipCharRunes(runes, i + 1, n)
        } else if (c == r'/' && i + 1 < n && runes[i + 1] == r'/') {
            i = skipLineRunes(runes, i + 2, n)
        } else if (c == r'/' && i + 1 < n && runes[i + 1] == r'*') {
            i = skipBlockRunes(runes, i + 2, n)
        } else if (c == r'@') {
            if (i + 1 < n && isIdentStart(runes[i + 1])) {
                let nameStart = i + 1
                var k = nameStart
                while (k < n && isIdentPart(runes[k])) {
                    k += 1
                }
                let name = String(runes[nameStart..k])
                if (macros.contains(name)) {
                    k = skipSpaces(runes, k, n)
                    if (k < n && runes[k] == r'(') {
                        let argsOpt = parseCallArgsRunes(runes, k, n)
                        match (argsOpt) {
                            case None => i = k    // 括号未闭合：原样保留后续文本
                            case Some((args, after)) =>
                                let m = macros.get(name).getOrThrow()
                                if (args.size != m.params.size) {
                                    println(uiTextF("{0} 第 {1} 行：{2}", [srcPath, lineOf(runes, i).toString(),
                                        uiTextF("调用 @{0} 需 {1} 个实参，实际给了 {2} 个", [name, m.params.size.toString(),
                                            args.size.toString()])]))
                                    return None
                                }
                                // 仅在真正展开时登记：裸写 @名（无括号）与未闭合括号
                                // 不计入 seen，避免外层收敛判定误报「嵌套超 8 层」
                                seen.add(name)
                                sb = "${sb}${String(runes[segStart..i])}"
                                sb = "${sb}${replaceParams(m.body, m.params, args)}"
                                segStart = after
                                i = after
                        }
                        continue
                    }
                    // 名命中但无 '('：视为官方宏用法（如 @Test），原样保留
                }
            }
            i += 1
        } else {
            i += 1
        }
    }
    sb = "${sb}${String(runes[segStart..n])}"
    return Some(sb)
}

/**
 * 实参展开保护：单 token 实参（标识符/数字/字符串与字符字面量）原样替换；
 * 复合表达式包一层括号防优先级错位——`@双倍(1+2)` 展开为 `(1+2) + (1+2)`
 * 而非 `1+2 + 1+2`。仅代码位置的形参替换受此保护（字符串/注释内不替换）。
 */
private func wrapMacroArg(arg: String): String {
    let t = arg.trimAscii()
    if (t.isEmpty()) {
        return t
    }
    let rs = t.toRuneArray()
    // 字符串/字符字面量整体（首尾配对引号）原样
    if (rs.size >= 2 && ((rs[0] == r'"' && rs[rs.size - 1] == r'"')
        || (rs[0] == r'\'' && rs[rs.size - 1] == r'\''))) {
        return t
    }
    // 标识符原样
    if (isIdentStart(rs[0])) {
        var allIdent = true
        for (r in rs) {
            if (!isIdentPart(r)) {
                allIdent = false
                break
            }
        }
        if (allIdent) {
            return t
        }
        return "(${t})"
    }
    // 数字（含负号与小数点）原样
    var start: Int64 = 0
    if (rs[0] == r'-') {
        start = 1
    }
    if (start < rs.size) {
        var allNum = true
        var idx = start
        while (idx < rs.size) {
            let r = rs[idx]
            if (!(r >= r'0' && r <= r'9') && r != r'.') {
                allNum = false
                break
            }
            idx += 1
        }
        if (allNum) {
            return t
        }
    }
    return "(${t})"
}

/** 宏体形参替换：整词（标识符边界）匹配；字符串/注释/字符字面量内不替换。 */
public func replaceParams(body: String, params: ArrayList<String>,
                          args: ArrayList<String>): String {    let runes = body.toRuneArray()
    let n = runes.size
    var sb = ""
    var segStart: Int64 = 0
    var i: Int64 = 0
    while (i < n) {
        let c = runes[i]
        if (c == r'"') {
            i = skipStringRunes(runes, i + 1, n)
        } else if (c == r'\'') {
            i = skipCharRunes(runes, i + 1, n)
        } else if (c == r'/' && i + 1 < n && runes[i + 1] == r'/') {
            i = skipLineRunes(runes, i + 2, n)
        } else if (c == r'/' && i + 1 < n && runes[i + 1] == r'*') {
            i = skipBlockRunes(runes, i + 2, n)
        } else if (isIdentStart(c)) {
            let nameStart = i
            var k = i
            while (k < n && isIdentPart(runes[k])) {
                k += 1
            }
            let name = String(runes[nameStart..k])
            var pi: Int64 = 0
            var hit = false
            while (pi < params.size) {
                if (params.get(pi).getOrThrow() == name) {
                    hit = true
                    break
                }
                pi += 1
            }
            if (hit) {
                sb = "${sb}${String(runes[segStart..nameStart])}"
                sb = "${sb}${wrapMacroArg(args.get(pi).getOrThrow())}"
                segStart = k
            }
            i = k
        } else {
            i += 1
        }
    }
    sb = "${sb}${String(runes[segStart..n])}"
    return sb
}
