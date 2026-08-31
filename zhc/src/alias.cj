package zhc

import std.collection.*

/**
 * 别名替换（对应设计 §5.3 alias.cj）——最易出错模块。
 *
 * 两遍扫描（输入为词法转译 + import 路径替换后的文本）：
 *   1. 第一遍收集豁免集（§3.4/§3.5 仓颉扩展豁免）：
 *      - 声明名：DECL_KEYWORDS（func/class/struct/enum/interface/extend/let/var/
 *        const/prop/type/macro）后紧跟的标识符；
 *      - 参数名/解构绑定：声明名后 `(...)` 区间内的标识符（含 `let (a, b)`）；
 *      - 模式绑定：`for (名 in ...)`、`case 构造器(名)` / `case 名 =>`、
 *        lambda `{名: 类型 => ...}`（`=>` 未出现前只是候选，`}` 时丢弃——
 *        避免对象字面量 `{a: 1}` 误收集）。
 *   2. 第二遍逐 token 替换：豁免集内的名字在全文件所有裸使用处（含 `.` 之后）
 *      不替换；未豁免的标识符查别名表（stdlib.toml）；`.段` 照常替换（§3.5 闭环）。
 *
 * 保护规则：字符串/注释/反引号内容不替换；字符串内 `${}` 插值段是代码——
 * 递归按代码态做别名替换（豁免集同样生效）；`@` 后宏名跳过（宏名只查宏表，
 * 词法阶段已处理）。
 */

public class AliasReplaceResult {
    public var text: String
    public var count: Int64
    public var map: ArrayList<MapEntry>   // 替换条目（输入文本 Rune 偏移，供源映射合并）

    public init(text: String, count: Int64, map: ArrayList<MapEntry>) {
        this.text = text
        this.count = count
        this.map = map
    }
}

/** 声明关键字（官方名，第一遍豁免集收集的触发词）。 */
private func declKeywords(): HashSet<String> {
    let s = HashSet<String>()
    s.add("func")
    s.add("class")
    s.add("struct")
    s.add("enum")
    s.add("interface")
    s.add("extend")
    s.add("let")
    s.add("var")
    s.add("const")
    s.add("prop")
    s.add("type")
    s.add("macro")
    return s
}

public func replaceAliases(text: String, lang: LangPack): AliasReplaceResult {
    let runes = text.toRuneArray()
    let exempt = collectExempts(runes, lang)
    let map = ArrayList<MapEntry>()
    let (sb, count) = aliasCode(runes, 0, runes.size, lang, exempt, map)
    return AliasReplaceResult(sb, count, map)
}

/** 第一遍：收集豁免集（声明名/参数名/解构绑定/模式绑定）。 */
private func collectExempts(runes: Array<Rune>, lang: LangPack): HashSet<String> {
    let n = runes.size
    let exempt = HashSet<String>()
    let decls = declKeywords()
    var i: Int64 = 0
    var last = ""                      // 上一个非空白 token（标识符或单字符符号）
    var pendingDecl = false            // 刚见 DECL，等待声明名
    var afterDeclName = false          // 刚收集声明名，期待 `(` 参数列表
    var inParen = false                // DECL 的 `(...)` 参数/解构绑定收集态
    var parenDepth: Int64 = 0
    var forParen = false               // `for (` 模式绑定收集态
    var forSeenIn = false
    var casePending = false            // `case` 后第一个标识符是绑定
    var caseCand = ""                  // `case` 后标识符候选：`(` 前未定（构造器 vs 绑定）
    var caseParen = false              // `case 构造器(` 内绑定收集态
    var caseParenDepth: Int64 = 0
    var lambdaActive = false           // `{` 后可能在 lambda 中
    var lambdaCand = ArrayList<String>()

    while (i < n) {
        let ch = runes[i]
        if (ch == r'"' || ch == r'\'') {
            let (_, next) = scanQuoted(runes, i, n, ch)
            i = next
        } else if (ch == r'/' && i + 1 < n && runes[i + 1] == r'/') {
            let (_, next) = scanLineComment(runes, i, n)
            i = next
        } else if (ch == r'/' && i + 1 < n && runes[i + 1] == r'*') {
            let (_, next) = scanBlockComment(runes, i, n)
            i = next
        } else if (ch == r'`') {
            var j = i + 1
            while (j < n && runes[j] != r'`') {
                j += 1
            }
            i = if (j < n) { j + 1 } else { n }
        } else if (isIdentStart(ch)) {
            var j = i
            while (j < n && isIdentPart(runes[j])) {
                j += 1
            }
            let token = String(runes[i..j])
            if (inParen) {
                // 参数名/解构绑定：`:` 前标识符与 let/var 后标识符；
                // `:` 后是类型名（可被别名替换），不收集（§5.3）
                if (last == "(" || last == "," || last == "let" || last == "var") {
                    exempt.add(token)
                }
            }
            if (forParen && !forSeenIn) {
                if (token == "in") {
                    forSeenIn = true
                } else if (last == "(" || last == ",") {
                    exempt.add(token)  // `for (键 in ...)` 绑定
                }
            }
            if (casePending) {
                // 延迟决定：`case x =>` 是裸绑定（豁免），`case X(y)` 是构造器模式
                // （构造器名应被别名替换，括号内参数才豁免）
                caseCand = token
                casePending = false
            }
            if (caseCand.isEmpty()) {
                ()                  // 无候选
            } else if (caseParen && (last == "(" || last == ",")) {
                exempt.add(token)      // `case 点(x, y)` 绑定
            } else if (last == "(") {
                ()                  // `case 构造器(` 的构造器名不豁免（可别名替换）
            } else if (caseParen) {
                exempt.add(token)      // 构造器模式括号内的嵌套标识符
            } else if (!casePending && lang.aliases.contains(token)) {
                ()                  // `case 无值 =>` 无参构造器模式：候选是别名 → 不豁免
            }
            if (lambdaActive && (last == "{" || last == ",")) {
                lambdaCand.add(token)  // lambda 候选绑定（`:` 后是类型名，不收集）
            }
            if (pendingDecl) {
                exempt.add(token)      // 声明名
                pendingDecl = false
                afterDeclName = true
            } else {
                afterDeclName = false
            }
            if (decls.contains(token)) {
                pendingDecl = true
            }
            if (token == "for") {
                forParen = true
                forSeenIn = false
            }
            if (token == "case") {
                casePending = true
            }
            last = token
            i = j
        } else if (ch == r'(') {
            if (pendingDecl) {
                inParen = true         // `let (a, b)` 解构
                parenDepth = 1
                pendingDecl = false
            } else if (inParen) {
                parenDepth += 1
            } else if (afterDeclName) {
                inParen = true         // `func 名(参数...)`
                parenDepth = 1
                afterDeclName = false
            }
            if (casePending) {
                caseParen = true       // `case (a, b)` 元组绑定（casePending 未消费）
                caseParenDepth = 1
                casePending = false
            } else if (!caseCand.isEmpty()) {
                caseCand = ""          // `case 构造器(`：构造器名不豁免（可别名替换）
                caseParen = true
                caseParenDepth = 1
            } else if (caseParen) {
                caseParenDepth += 1
            }
            afterDeclName = false
            last = "("
            i += 1
        } else if (ch == r')') {
            if (inParen) {
                parenDepth -= 1
                if (parenDepth == 0) {
                    inParen = false
                }
            }
            if (caseParen) {
                caseParenDepth -= 1
                if (caseParenDepth == 0) {
                    caseParen = false
                }
            }
            if (forParen) {
                forParen = false
            }
            afterDeclName = false
            last = ")"
            i += 1
        } else if (ch == r'{') {
            lambdaActive = true
            lambdaCand = ArrayList<String>()
            afterDeclName = false
            last = "{"
            i += 1
        } else if (ch == r'}') {
            if (lambdaActive) {
                lambdaCand.clear()     // 未确认：对象字面量/块，丢弃候选
            }
            lambdaActive = false
            afterDeclName = false
            last = "}"
            i += 1
        } else if (ch == r'=' && i + 1 < n && runes[i + 1] == r'>') {
            if (!caseCand.isEmpty()) {
                if (!lang.aliases.contains(caseCand)) {
                    exempt.add(caseCand)   // `case x =>` 裸绑定确认（非别名 → 豁免）
                }                          // `case 无值 =>` 无参构造器：别名 → 不豁免
                caseCand = ""
            }
            if (lambdaActive) {
                for (cand in lambdaCand) {
                    exempt.add(cand)   // `{名: 类型 => ...}` 确认绑定
                }
                lambdaActive = false
            }
            afterDeclName = false
            last = "=>"
            i += 2
        } else if (ch == r';') {
            if (!caseCand.isEmpty()) {
                if (!lang.aliases.contains(caseCand)) {
                    exempt.add(caseCand)   // 防御：`case x` 未到 `=>` 也豁免（异常语句容错）
                }
                caseCand = ""
            }
            casePending = false        // 防御：case 绑定必须到 `=>`，分号结束语句
            afterDeclName = false
            last = ";"
            i += 1
        } else if (ch == r' ' || ch == r'\t' || ch == r'\n' || ch == r'\r') {
            i += 1                     // 空白不更新 last（修饰符链/空白不打断收集态）
        } else {
            if (!caseCand.isEmpty()) {
                if (!lang.aliases.contains(caseCand)) {
                    exempt.add(caseCand)   // 防御：非 `(` 非 `=>` 的其它符号后按裸绑定豁免
                }
                caseCand = ""
            }
            afterDeclName = false
            last = String(runes[i])
            i += 1
        }
    }
    return exempt
}

/** 第二遍：逐 token 别名替换（豁免优先）；字符串插值段递归（代码态）。
 * map 记录每次实际替换的 (输入偏移, 长度, 原文, 替换文)——递归调用传入绝对
 * 偏移的 start，插值段内条目同样以输入文本绝对 Rune 偏移记录（源映射安全）。 */
private func aliasCode(runes: Array<Rune>, start: Int64, end: Int64, lang: LangPack, exempt: HashSet<String>, map: ArrayList<MapEntry>): (String, Int64) {
    var sb = ""
    var count: Int64 = 0
    var i = start
    var atPending = false              // @ 后宏名：跳过

    while (i < end) {
        let ch = runes[i]
        if (ch == r'"') {
            let (piece, next, c) = scanAliasString(runes, i, end, lang, exempt, map)
            sb = "${sb}${piece}"
            count += c
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
            // 反引号原始标识符：只走词法阶段的关键字表，别名阶段跳过（强制原文）
            var j = i + 1
            while (j < end && runes[j] != r'`') {
                j += 1
            }
            let next = if (j < end) { j + 1 } else { end }
            sb = "${sb}${String(runes[i..next])}"
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
            if (atPending) {
                sb = "${sb}${token}"   // @ 宏名：只查宏表（词法阶段已处理），别名跳过
                atPending = false
            } else if (exempt.contains(token)) {
                sb = "${sb}${token}"   // 豁免集：声明名/参数名/模式绑定，含 `.` 后使用处
            } else {
                let mapped = lang.aliases.get(token)
                if (mapped == None) {
                    sb = "${sb}${token}"
                } else {
                    sb = "${sb}${mapped.getOrThrow()}"
                    count += 1
                    map.add(MapEntry(i, j - i, token, mapped.getOrThrow()))
                }
            }
            i = j
        } else {
            sb = "${sb}${ch}"
            if (!isSpace(ch)) {
                atPending = false
            }
            i += 1
        }
    }
    return (sb, count)
}

/** 字符串扫描（别名版）：普通文本原样；`${}` 插值段递归做代码态别名替换。
 *  返回 (文本, 结束位置, 替换计数)。 */
private func scanAliasString(runes: Array<Rune>, start: Int64, end: Int64, lang: LangPack, exempt: HashSet<String>, map: ArrayList<MapEntry>): (String, Int64, Int64) {
    var sb = ""
    var count: Int64 = 0
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
            return (sb, j + 1, count)
        } else if (c == r'$' && j + 1 < end && runes[j + 1] == r'{') {
            let (endIdx, codeText, c2) = scanAliasInterp(runes, j + 2, end, lang, exempt, map)
            sb = "${sb}${"${runes[j]}${runes[j + 1]}"}${codeText}${runes[endIdx - 1]}"
            count += c2
            j = endIdx
        } else {
            sb = "${sb}${c}"
            j += 1
        }
    }
    return (sb, end, count)
}

/** 插值代码态扫描（别名版）：括号栈配对找结束 `}`，内容递归 aliasCode。 */
private func scanAliasInterp(runes: Array<Rune>, start: Int64, end: Int64, lang: LangPack, exempt: HashSet<String>, map: ArrayList<MapEntry>): (Int64, String, Int64) {
    var depth: Int64 = 1
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
                let (codeText, c2) = aliasCode(runes, start, j - 1, lang, exempt, map)
                return (j, codeText, c2)
            }
        } else {
            j += 1
        }
    }
    let (codeText, c2) = aliasCode(runes, start, end, lang, exempt, map)
    return (end, codeText, c2)
}
