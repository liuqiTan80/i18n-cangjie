package zhc

import std.collection.*
import std.fs.*

// ==================== zhc fmt（方言排版格式化器 v1，教程 08.x）====================
// zhc fmt <文件.zc> [--check]：把方言源码排版为统一风格（教学作业格式一致）：
//   ① 缩进 = 花括号深度 × 4 空格（行首 tab/混合缩进重写；空行输出空行）；
//   ② 行尾空白删除（行内扫描不输出多余空白）；
//   ③ 括号内侧空格清理：( x ) → (x)、[ x ] → [x]；
//   ④ 逗号/分号/冒号后补 1 空格（f(a, b)、a: 类型）；行尾符号不加；
//   ⑤ 二元运算符两侧补 1 空格（= == != += && || + - * / % => …），
//      一元 +/- 贴附不拆（-5、(-x)）；
//   ⑥ `<` `>` `<=` `>=` 透传（泛型 列表<字符串> 与比较两侧空格都不强改）；
//   ⑦ 块注释/行注释/字符串/字符字面量内容一律不动（与 lint/扩展同一词法保护）。
// 不处理：折行（超长行仍由 lint 报告）、函数间空行数量（lint 已压缩重复空行）。
// --check：只报告不改写（有差异退出码 1，供 CI/预提交钩子）。

/** 排版统计：发生变化的行数。 */
public class FmtCount {
    public var lines: Int64
    public init() {
        lines = 0
    }
}

/** cmdLint 同款壳：zhc fmt <文件> [--check]（参数任意顺序）。 */
public func cmdFmt(args: Array<String>): Int64 {
    var path = ""
    var checkOnly = false
    for (i in 1..args.size) {
        if (args[i] == "--check") {
            checkOnly = true
        } else if (path.isEmpty()) {
            path = args[i]
        }
    }
    if (path.isEmpty()) {
        println(uiText("用法：zhc fmt <文件.zc> [--check]"))
        println(uiText("      --check 只检查不写回（有差异退出码 1）"))
        return 1
    }
    if (!exists(Path(path))) {
        // 文件不存在时无内容语言信号：按入口 UI（ZHCLANG/默认 zh）提示
        println(uiTextF("文件不存在：{0}", [path]))
        return 1
    }
    let lang = resolveLangPack(resolveLangForFile(path))
    let srcRaw = readTextFile(path)
    // 控制词（后接条件的词，其后的 ( 前补 1 空格）：官方值 if/while/for/match 与 else-前缀
    let kwSp = ArrayList<String>()
    for ((k, v) in lang.keywords) {
        if (v == "if" || v == "while" || v == "for" || v == "match" || v.startsWith("else ")) {
            kwSp.add(k)
        }
    }
    let cnt = FmtCount()
    let src = fmtSource(srcRaw, kwSp.toArray(), cnt)
    if (src == srcRaw) {
        println(uiTextF("排版检查：无变化（{0}）", [path]))
        return 0
    }
    if (checkOnly) {
        println(uiTextF("排版检查：{0} 行需要格式化（{1}）", [cnt.lines.toString(), path]))
        return 1
    }
    File.writeTo(path, src.toArray())
    println(uiTextF("已格式化 {0} 行（{1}）", [cnt.lines.toString(), path]))
    return 0
}

// ---- Rune 常量 ----
let R_SPACE: Rune = Rune(32)
let R_TAB: Rune = Rune(9)
let R_EXCLAM: Rune = Rune(33)
let R_APOS: Rune = Rune(39)
let R_LP: Rune = Rune(40)
let R_RP: Rune = Rune(41)
let R_STAR: Rune = Rune(42)
let R_PLUS: Rune = Rune(43)
let R_COMMA: Rune = Rune(44)
let R_MINUS: Rune = Rune(45)
let R_DOT: Rune = Rune(46)
let R_SLASH: Rune = Rune(47)
let R_DIGIT0: Rune = Rune(48)
let R_DIGIT9: Rune = Rune(57)
let R_COLON: Rune = Rune(58)
let R_SEMI: Rune = Rune(59)
let R_LT: Rune = Rune(60)
let R_EQ: Rune = Rune(61)
let R_GT: Rune = Rune(62)
let R_AMP: Rune = Rune(38)
let R_PIPE: Rune = Rune(124)
let R_PCT: Rune = Rune(37)
let R_QUOTE: Rune = Rune(34)
let R_LB: Rune = Rune(91)
let R_RB: Rune = Rune(93)
let R_LC: Rune = Rune(123)
let R_RC: Rune = Rune(125)
let R_BACKSLASH: Rune = Rune(92)

// ---- 待插空格类型 ----
let FMT_SP_NONE: Int64 = 0
let FMT_SP_SOFT: Int64 = 1   // 代码区空白产生：可被 ) ] . 与 ( [ 前抑制
let FMT_SP_MUST: Int64 = 2   // 标点/二元运算符产生：仅 ) ] . 前抑制

/**
 * 排版主入口：逐行处理（块注释跨行时整行原样）。
 * depth 跨行累计（字符串/注释内 { } 不计）；变化行计入 cnt.lines。
 */
public func fmtSource(src: String, kwSpace: Array<String>, cnt: FmtCount): String {
    let lines = src.split("\n")
    let out = ArrayList<String>()
    var depth: Int64 = 0
    var inBlock = false
    for (line in lines) {
        let runes = line.toRuneArray()
        if (inBlock) {
            // 上一行遗留的未闭合块注释：整行原样，直到 */ 出现（空行同样输出空行）
            if (isBlankLine(runes)) {
                out.add("")
            } else {
                out.add(line)
                inBlock = !containsClose(runes)
            }
            continue
        }
        if (isBlankLine(runes)) {
            // 空行：输出空行
            out.add("")
            continue
        }
        // 行首探测：首个非空白字符若是 }，缩进退一级（仅影响本行显示）
        var lead: Int64 = 0
        while (lead < runes.size && (runes[lead] == R_SPACE || runes[lead] == R_TAB)) {
            lead += 1
        }
        var lineDepth = depth
        if (lead < runes.size && runes[lead] == R_RC && lineDepth > 0) {
            lineDepth -= 1
        }
        let (bodyText, bodyDelta, bodyOpen) = fmtLine(runes, kwSpace)
        depth += bodyDelta
        inBlock = bodyOpen
        var prefix = ""
        var si: Int64 = 0
        while (si < lineDepth * 4) {
            prefix = "${prefix} "
            si += 1
        }
        // 变化行计数：对比重建完整行与原行（含缩进与行尾空白）
        let rebuilt = prefix + bodyText
        if (rebuilt != line) {
            cnt.lines += 1
        }
        out.add(rebuilt)
    }
    var result = ""
    var first = true
    for (l in out) {
        result = if (first) { l } else { "${result}\n${l}" }
        first = false
    }
    return result
}

/** 行是否仅空白。 */
func isBlankLine(runes: Array<Rune>): Bool {
    for (r in runes) {
        if (r != R_SPACE && r != R_TAB) {
            return false
        }
    }
    return true
}

/** 行内是否含块注释闭合 */
func containsClose(runes: Array<Rune>): Bool {
    var i: Int64 = 0
    while (i + 1 < runes.size) {
        if (runes[i] == R_STAR && runes[i + 1] == R_SLASH) {
            return true
        }
        i += 1
    }
    return false
}

/** 上一有效字符是否左括号组（决定 SOFT 是否被抑制）。 */
func isOpenRune(c: Rune): Bool {
    return c == R_LP || c == R_LB || c == R_LC
}

/**
 * 单行格式化（不含行首缩进）：返回 (行文本, 本行引起的 depth 增量)。
 * 块注释若在本行未闭合，剩余内容原样拷完（跨行由 fmtSource 接管）。
 */
public func fmtLine(runes: Array<Rune>, kwSpace: Array<String>): (String, Int64, Bool) {
    let buf = ArrayList<Rune>()
    var sp: Int64 = FMT_SP_NONE
    var delta: Int64 = 0
    var i: Int64 = 0
    let n = runes.size
    var lastSig: Rune = Rune(0)   // 最近输出字符（Rune(0) = 行首哨兵）
    var lastKw = ""               // 最近完整词（关键字判定）
    var lastWasOp = false         // 最近输出是否二元运算符（一元判定）
    var blockLeftOpen = false     // 行尾是否遗留未闭合块注释（跨行由 fmtSource 接管）

    func push(r: Rune) {
        buf.add(r)
        lastSig = r
    }
    // 按 sp 决定是否补 1 空格并复位（右括号/点前由各自分支清 sp，这里兜底）
    func flushSpace() {
        if (sp == FMT_SP_NONE || buf.size == 0) {
            sp = FMT_SP_NONE
            return
        }
        if (sp == FMT_SP_SOFT && isOpenRune(lastSig)) {
            sp = FMT_SP_NONE
            return
        }
        if (lastSig != R_SPACE) {
            push(R_SPACE)
        }
        sp = FMT_SP_NONE
    }
    // 开括号 ( [ 前的空格：SOFT 一律丢（f (x) → f(x)），MUST 保留（x = (a)）
    func flushSpaceOpen() {
        if (sp == FMT_SP_MUST && buf.size > 0 && !isOpenRune(lastSig) && lastSig != R_RP &&
            lastSig != R_RB && lastSig != R_DOT && lastSig != R_SPACE) {
            push(R_SPACE)
        }
        sp = FMT_SP_NONE
    }
    // 控制词（如果/当/对于/匹配…）紧贴 ( 时补空格：如果 (x)
    func maybeKwSpace() {
        if (buf.size > 0 && !lastKw.isEmpty() && kwSpace.contains(lastKw)) {
            if (lastSig != R_SPACE) {
                push(R_SPACE)
            }
        }
    }
    // 二元运算符：前补 1 空格（行首不可能是二元；紧贴时补，flush 已补则不重复）
    func pushBinary() {
        if (buf.size > 0 && lastSig != R_SPACE) {
            if (lastSig != R_LP && lastSig != R_LB && lastSig != R_LC && lastSig != R_DOT) {
                push(R_SPACE)
            }
        }
        lastKw = ""
    }

    while (i < n) {
        let r = runes[i]
        // ---- 块注释 ----
        if (r == R_SLASH && i + 1 < n && runes[i + 1] == R_STAR) {
            flushSpace()
            push(R_SLASH)
            push(R_STAR)
            i += 2
            var closed = false
            while (i < n) {
                if (i + 1 < n && runes[i] == R_STAR && runes[i + 1] == R_SLASH) {
                    push(R_STAR)
                    push(R_SLASH)
                    i += 2
                    closed = true
                    break
                }
                push(runes[i])
                i += 1
            }
            // 未闭合：剩余已拷完，跨行由 fmtSource 处理（本行结束）
            if (!closed) {
                blockLeftOpen = true
                break
            }
            lastKw = ""
            continue
        }
        // ---- 行注释：保留（前有内容则确保 1 空格），拷余行 ----
        if (r == R_SLASH && i + 1 < n && runes[i + 1] == R_SLASH) {
            if (sp != FMT_SP_NONE && buf.size > 0 && lastSig != R_SPACE) {
                push(R_SPACE)
            }
            sp = FMT_SP_NONE
            while (i < n) {
                push(runes[i])
                i += 1
            }
            break
        }
        // ---- 字符串 / 字符字面量：整体拷贝 ----
        if (r == R_QUOTE || r == R_APOS) {
            flushSpace()
            let q = r
            push(q)
            i += 1
            while (i < n) {
                let c = runes[i]
                if (c == R_BACKSLASH && i + 1 < n) {
                    push(c)
                    push(runes[i + 1])
                    i += 2
                    continue
                }
                push(c)
                i += 1
                if (c == q) {
                    break
                }
            }
            lastKw = ""
            continue
        }
        // ---- 空白：置 SOFT（( [ 后与行首不置；行首缩进由外部负责）----
        if (r == R_SPACE || r == R_TAB) {
            if (sp == FMT_SP_NONE && buf.size > 0 && !isOpenRune(lastSig) && lastSig != R_DOT) {
                sp = FMT_SP_SOFT
            }
            i += 1
            continue
        }
        // ---- 词 / 数字：拷贝 ----
        if (isIdentStart(r) || (r >= R_DIGIT0 && r <= R_DIGIT9)) {
            flushSpace()
            var w = ""
            while (i < n) {
                let c = runes[i]
                if (isIdentPart(c) || (w.isEmpty() && isIdentStart(c))) {
                    w = "${w}${c}"
                    i += 1
                } else {
                    break
                }
            }
            let ws = w.toRuneArray()
            var wi: Int64 = 0
            while (wi < ws.size) {
                push(ws[wi])
                wi += 1
            }
            lastKw = w
            lastWasOp = false
            continue
        }
        // ---- 右括号组 ----
        if (r == R_RP || r == R_RB) {
            sp = FMT_SP_NONE
            push(r)
            lastKw = ""
            lastWasOp = false
            i += 1
            continue
        }
        // ---- 逗号 / 分号 / 冒号：前贴，后 MUST ----
        if (r == R_COMMA || r == R_SEMI || r == R_COLON) {
            sp = FMT_SP_NONE
            push(r)
            lastKw = ""
            lastWasOp = false
            sp = FMT_SP_MUST
            i += 1
            continue
        }
        // ---- 点 / 范围 .. / ..=：贴附透传 ----
        if (r == R_DOT) {
            sp = FMT_SP_NONE
            push(R_DOT)
            i += 1
            if (i < n && runes[i] == R_DOT) {
                push(R_DOT)
                i += 1
                if (i < n && runes[i] == R_EQ) {
                    push(R_EQ)
                    i += 1
                }
            }
            lastKw = ""
            lastWasOp = false
            continue
        }
        // ---- 左括号组：( 前控制词补空格；[ 直接贴（SOFT 丢、MUST 保留）----
        if (r == R_LP || r == R_LB) {
            flushSpaceOpen()
            if (r == R_LP) {
                maybeKwSpace()
            }
            push(r)
            lastKw = ""
            lastWasOp = false
            i += 1
            continue
        }
        // ---- 大括号 ----
        if (r == R_LC) {
            sp = FMT_SP_NONE
            if (buf.size > 0 && !isOpenRune(lastSig) && lastSig != R_SPACE) {
                push(R_SPACE)
            }
            push(r)
            delta += 1
            lastKw = ""
            lastWasOp = false
            i += 1
            continue
        }
        if (r == R_RC) {
            sp = FMT_SP_NONE
            push(r)
            delta -= 1
            lastKw = ""
            lastWasOp = false
            sp = FMT_SP_MUST   // } 后同行内容（} 否则 {）补 1 空格
            i += 1
            continue
        }
        // ---- 双字符运算符 ----
        if (i + 1 < n) {
            let n2 = runes[i + 1]
            if (r == R_EQ && n2 == R_EQ) {   // ==
                flushSpace()
                pushBinary()
                push(R_EQ)
                push(R_EQ)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_EXCLAM && n2 == R_EQ) {   // !=
                flushSpace()
                pushBinary()
                push(R_EXCLAM)
                push(R_EQ)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_PLUS && n2 == R_EQ) {   // +=
                flushSpace()
                pushBinary()
                push(R_PLUS)
                push(R_EQ)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_MINUS && n2 == R_EQ) {   // -=
                flushSpace()
                pushBinary()
                push(R_MINUS)
                push(R_EQ)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_STAR && n2 == R_EQ) {   // *=
                flushSpace()
                pushBinary()
                push(R_STAR)
                push(R_EQ)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_SLASH && n2 == R_EQ) {   // /=
                flushSpace()
                pushBinary()
                push(R_SLASH)
                push(R_EQ)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_AMP && n2 == R_AMP) {   // &&
                flushSpace()
                pushBinary()
                push(R_AMP)
                push(R_AMP)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_PIPE && n2 == R_PIPE) {   // ||
                flushSpace()
                pushBinary()
                push(R_PIPE)
                push(R_PIPE)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            if (r == R_EQ && n2 == R_GT) {   // => 箭头：两侧 1 空格，内部不拆
                flushSpace()
                pushBinary()
                push(R_EQ)
                push(R_GT)
                i += 2
                sp = FMT_SP_MUST
                continue
            }
            // <= >=：透传（保留已有空白；不强加）
            if ((r == R_LT || r == R_GT) && n2 == R_EQ) {
                flushSpace()
                push(r)
                push(n2)
                i += 2
                lastKw = ""
                lastWasOp = false
                continue
            }
        }
        // ---- 单字符运算符 ----
        if (r == R_EQ || r == R_STAR || r == R_PCT || r == R_SLASH) {
            // = * % /：二元（/ 的注释形态已在上方分支处理）
            flushSpace()
            pushBinary()
            push(r)
            sp = FMT_SP_MUST
            lastKw = ""
            lastWasOp = true
            i += 1
            continue
        }
        if (r == R_PLUS || r == R_MINUS || r == R_EXCLAM) {
            // 一元判定：行首 / 左括号 / 标点 / 前一字符是运算符
            let unary = buf.size == 0 || lastWasOp ||
                (lastSig == R_LP || lastSig == R_LB || lastSig == R_LC ||
                 lastSig == R_COMMA || lastSig == R_SEMI || lastSig == R_COLON ||
                 lastSig == R_EQ || lastSig == R_GT || lastSig == R_LT)
            if (unary) {
                // 一元 +/-：丢弃 SOFT，但保留二元 op/标点后的 MUST（a - -1、f(a, -1)）
                if (sp == FMT_SP_MUST && buf.size > 0 && lastSig != R_SPACE) {
                    push(R_SPACE)
                }
                sp = FMT_SP_NONE
                push(r)
                lastKw = ""
                lastWasOp = false
            } else {
                flushSpace()
                pushBinary()
                push(r)
                sp = FMT_SP_MUST
                lastKw = ""
                lastWasOp = true
            }
            i += 1
            continue
        }
        // ---- < >：泛型/比较透传（不主动加空格；已有 SOFT 交给后续词）----
        if (r == R_LT || r == R_GT) {
            push(r)
            lastKw = ""
            lastWasOp = false
            i += 1
            continue
        }
        // ---- 其余（@ $ ? 与未知符号）：原样，不产生空格逻辑 ----
        push(r)
        lastKw = ""
        lastWasOp = false
        i += 1
    }
    // 拼行（行尾待插空格自然丢弃 → 尾随空白删除）
    var text = ""
    for (rr in buf) {
        text = "${text}${rr}"
    }
    return (text, delta, blockLeftOpen)
}
