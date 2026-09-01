package zhc

import std.collection.*
import std.fs.*
import std.env.*
import std.process.*

/**
 * §16.4 宏展开教学视图（zhc expand）。1.0.5 宏链路实测打通（补 §13.1 第 30 条）：
 *   - 宏包：源码首行声明 `macro package <名>`（独立包，仅暴露宏），编译分两步：
 *     `cjc define/` 下全部 .cj 以 `--compile-macro` 编译，生成 <名>.cjo（与宏包文件同目录），
 *     主程序（import <名>.*）编译时自动发现；
 *   - 宏调用：`@名(...)`；宏定义 `public macro 名(input: Tokens): Tokens`，
 *     参数与返回均为 Tokens；quote(...) 内 `$(expr)` 仅在代码位置插值
 *     （字符串字面量内不插值），基本类型插值为字面量、Tokens 直接嵌入；
 *   - 展开产物：编译主程序加 `--debug-macro` 生成 <文件>.cj.macrocall，
 *     展开区带形如「Emitted by MacroCall @名 in 文件:行:列」的斜杠星包裹标记
 *     与「n.m」序号注释，宏体真实执行（非模板演示）；
 *   - println 1.0.5 仅单参数（`println("a", 7)` 报 extra argument），
 *     多段输出用 print($(s) + " = ") 拼接（String 的 + 为连接）。
 *
 * 流程：方言 .zc → 转译官方 → 临时工程（宏包目录复制 + main.cj）
 * → cjc 两步编译 → 解析 .macrocall → 反向转译母语 → 对照输出。
 */

/** 宏展开区块（.macrocall 中一次 @调用 的展开结果）。 */
public class MacroEmit {
    public var name: String      // 宏名（官方）
    public var line: Int64       // 转译文行（1 起）
    public var col: Int64        // 转译文列（1 起）
    public var body: String      // 展开代码文本（含 /* n.m */ 序号注释）

    public init(name: String, line: Int64, col: Int64, body: String) {
        this.name = name
        this.line = line
        this.col = col
        this.body = body
    }
}

/** expand 主入口；args 形如 [expand, 文件.zc, --macro-pkg?, 目录?]。 */
public func cmdExpand(args: Array<String>): Int64 {
    let lang = resolveLangPack(resolveLang())
    var path = ""
    var pkgDir = ""
    var i = 1
    while (i < args.size) {
        if (args[i] == "--macro-pkg" && i + 1 < args.size) {
            pkgDir = args[i + 1]
            i += 2
        } else if (path.isEmpty()) {
            path = args[i]
            i += 1
        } else {
            println("未知参数：${args[i]}")
            return 1
        }
    }
    if (path.isEmpty()) {
        println("用法：zhc expand <文件.zc> [--macro-pkg <宏包目录>]")
        println("  宏包目录为官方仓颉宏实现（宏包声明，如 define/）")
        return 1
    }
    if (!exists(Path(path))) {
        println("文件不存在：${path}")
        return 1
    }
    let src = readTextFile(path)
    scanUnicodeRisks(src, path)
    let result = transpileFull(src, lang)

    // ① 宏包目录：--macro-pkg 指定，或文件同目录/父目录链的 define/
    var macroRoot = ""
    if (!pkgDir.isEmpty()) {
        macroRoot = pkgDir
    } else {
        let found = findMacroDir(dirOf(path))
        match (found) {
            case None =>
                println("未找到宏包目录 define/（官方宏实现）：请在文件同目录或其父目录提供，或用 --macro-pkg 指定")
                return 1
            case Some(d) => macroRoot = d
        }
    }
    if (!exists(Path(macroRoot))) {
        println("宏包目录不存在：${macroRoot}")
        return 1
    }

    // ② 临时工程（~/.zhc/expand/<hash>/src/），键含路径与源文本保证唯一；
    // 有界清理（审计 D6）：目录数超过 16 时清空重建，避免长期累积
    let home = getVariable("HOME").getOrThrow()
    let expandRoot = "${home}/.zhc/expand"
    if (exists(Path(expandRoot))) {
        let dirs = Directory.readFrom(expandRoot)
        if (dirs.size > 16) {
            for (d in dirs) {
                removeIfExists("${expandRoot}/${d.name}", recursive: true)
            }
        }
    }
    let work = "${expandRoot}/${hexOf(hash64("${path}\u{0}${src}"))}"
    let srcDir = "${work}/src"
    ensureDir("${srcDir}/define")
    let macroName = copyMacroPkg(macroRoot, "${srcDir}/define")
    if (macroName.isEmpty()) {
        println("宏包目录 ${macroRoot} 中未找到 `macro package` 声明（宏包源码首行）")
        return 1
    }

    // ③ 主程序：转译文 + 自动补宏包 import（方言侧未 import 时）
    var mainText = result.text
    if (!mainText.contains("import ${macroName}")) {
        mainText = "import ${macroName}.*\n" + mainText
    }
    let mainCj = "${srcDir}/main.cj"
    File.writeTo(mainCj, mainText.toArray())

    // ④ 两步编译：宏包 --compile-macro → 主程序 --debug-macro（生成 .macrocall）
    let (c1, _, e1) = executeWithOutput("bash", ["-c", "cd '${srcDir}' && cjc define/*.cj --compile-macro 2>&1"])
    if (c1 != 0) {
        println("宏包编译失败（退出码 ${c1}）：")
        print(String.fromUtf8(e1))
        return c1
    }
    let macrocall = "${srcDir}/main.cj.macrocall"
    let (c2, _, e2) = executeWithOutput("bash", ["-c", "cd '${srcDir}' && cjc main.cj -o main --debug-macro 2>&1"])
    if (!exists(Path(macrocall))) {
        println("宏展开失败（cjc 退出码 ${c2}）：")
        print(String.fromUtf8(e2))
        return if (c2 == 0) { 1 } else { c2 }
    }
    if (c2 != 0) {
        // 展开产物已生成但编译报错（展开后代码不合法）——仍展示视图，附带错误
        print(String.fromUtf8(e2))
    }

    // ⑤ 解析展开区 + 反向转译（官方 → 母语）
    let emits = parseMacrocall(readTextFile(macrocall))
    if (emits.size == 0) {
        println("未发现宏展开（文件中没有宏调用？）")
        return 1
    }
    let rev = buildReverseMap(lang.keywords, lang.macros, lang.aliases)
    let smap = SourceMap(src, result.text, result.map)
    println("")
    println("═══ zhc expand：宏展开教学视图 ═══")
    println("宏包：${macroRoot}（${macroName}）")
    for (e in emits) {
        let (sLine, _) = smap.mapBack(e.line, e.col)
        println("")
        println("[展开前] ${path}:${sLine}")
        println("  ${lineAt(src, sLine)}")
        println("[展开后] 官方（${baseNameOf(macrocall)}）")
        for (l in e.body.split("\n")) {
            println("  ${l}")
        }
        let dialect = reverseTranslate(e.body, rev)
        println("[展开后] 方言（反向转译）")
        for (l in dialect.split("\n")) {
            println("  ${l}")
        }
    }
    if (c2 != 0) {
        println("")
        println("注：展开后代码编译报错（见上），教学视图仍已生成。")
    }
    return 0
}

/** 从 dir 向上逐级查找 define/ 目录（含宏包源码）；未找到返回 None。 */
func findMacroDir(dir: String): ?String {
    var cur = dir
    var found: ?String = None
    while (found == None) {
        let cand = "${cur}/define"
        if (exists(Path(cand)) && Directory.readFrom(cand).size > 0) {
            found = Some(cand)
        } else if (cur.isEmpty() || cur == "/" || cur == ".") {
            break
        } else {
            let parent = dirOf(cur)
            if (parent == cur || parent == "." || parent.isEmpty()) {
                break
            }
            cur = parent
        }
    }
    return found
}

/** 复制宏包源码到 dst，返回首个 `macro package` 声明的包名；未声明返回空串。 */
func copyMacroPkg(root: String, dst: String): String {
    var macroName = ""
    let list = Directory.readFrom(root)
    for (f in list) {
        if (f.isDirectory()) {
            continue
        }
        if (!f.name.endsWith(".cj")) {
            continue
        }
        let text = readTextFile("${root}/${f.name}")
        if (macroName.isEmpty()) {
            let marker = "macro package "
            for (ln in text.split("\n")) {
                let t = ln.trimAscii()
                if (t.startsWith(marker)) {
                    macroName = t[marker.size..t.size].trimAscii()
                    break
                }
            }
        }
        File.writeTo("${dst}/${f.name}", text.toArray())
    }
    return macroName
}

/** 解析 .macrocall：提取每个 Emitted 展开区（宏名、转译文行列、展开体）。 */
public func parseMacrocall(text: String): ArrayList<MacroEmit> {
    let emits = ArrayList<MacroEmit>()
    var inEmit = false
    var name = ""
    var line: Int64 = 0
    var col: Int64 = 0
    var body = ""
    let lines = text.split("\n")
    for (ln in lines) {
        if (inEmit && ln.contains("End of the Emit")) {
            emits.add(MacroEmit(name, line, col, body))
            inEmit = false
            body = ""
            continue
        }
        let marker = ln.indexOf("Emitted by MacroCall")
        if (marker != None) {
            if (inEmit) {
                emits.add(MacroEmit(name, line, col, body))
            }
            inEmit = true
            body = ""
            let runes = ln.toRuneArray()
            // 提取 @名（marker 之后的第一个 @；indexOf 无起始参数，手写扫描）
            name = ""
            var k = marker.getOrThrow() + 1
            while (k < runes.size && runes[k] != r'@') {
                k += 1
            }
            if (k < runes.size) {
                var j = k + 1
                while (j < runes.size && (runes[j].isAsciiLetter() || runes[j].isAsciiNumber() || runes[j] == r'_')) {
                    j += 1
                }
                name = String(runes[k + 1..j])
            }
            // 最后的 ":数字:数字" 即 行:列（标记行全 ASCII，字节/Rune 偏移一致）
            var lastColon = -1
            for (m in 0..runes.size) {
                if (runes[m] == r':') {
                    lastColon = m
                }
            }
            if (lastColon >= 0) {
                var secondColon = -1
                for (m in 0..lastColon) {
                    if (runes[m] == r':') {
                        secondColon = m
                    }
                }
                if (secondColon >= 0) {
                    col = parseIntS(String(runes[lastColon + 1..runes.size]))
                    line = parseIntS(String(runes[secondColon + 1..lastColon]))
                }
            }
            continue
        }
        if (inEmit) {
            body = "${body}${ln}\n"
        }
    }
    if (inEmit) {
        emits.add(MacroEmit(name, line, col, body))
    }
    return emits
}

/** 反向转译：官方代码 → 母语（字符串/注释原样，标识符查反向表首命中）。 */
public func reverseTranslate(text: String, rev: ReverseMap): String {
    let runes = text.toRuneArray()
    let parts = ArrayList<String>()
    var i: Int64 = 0
    while (i < runes.size) {
        let c = runes[i]
        if (c == r'"') {
            // 字符串字面量（含 \" 转义）
            var j = i + 1
            while (j < runes.size) {
                if (runes[j] == r'\\') {
                    j += 2
                } else if (runes[j] == r'"') {
                    j += 1
                    break
                } else {
                    j += 1
                }
            }
            parts.add(String(runes[i..j]))
            i = j
        } else if (c == r'/' && i + 1 < runes.size && runes[i + 1] == r'/') {
            // 行注释
            var j = i
            while (j < runes.size && runes[j] != r'\n') {
                j += 1
            }
            parts.add(String(runes[i..j]))
            i = j
        } else if (c == r'/' && i + 1 < runes.size && runes[i + 1] == r'*') {
            // 块注释
            var j = i + 2
            while (j + 1 < runes.size && !(runes[j] == r'*' && runes[j + 1] == r'/')) {
                j += 1
            }
            let endJ = if (j + 2 < runes.size) { j + 2 } else { runes.size }
            parts.add(String(runes[i..endJ]))
            i = endJ
        } else if (c.isAsciiLetter() || c == r'_') {
            var j = i
            while (j < runes.size && (runes[j].isAsciiLetter() || runes[j].isAsciiNumber() || runes[j] == r'_')) {
                j += 1
            }
            let word = String(runes[i..j])
            let cands = rev.entries.get(word)
            match (cands) {
                case Some(list) => parts.add(list[0])
                case None => parts.add(word)
            }
            i = j
        } else {
            parts.add(String(runes[i..i + 1]))
            i += 1
        }
    }
    var out = ""
    for (p in parts) {
        out = "${out}${p}"
    }
    return out
}

/** 取文本第 n 行（1 起）；越界返回空串。 */
func lineAt(text: String, n: Int64): String {
    let lines = text.split("\n")
    if (n < 1 || n > lines.size) {
        return ""
    }
    return lines[Int64(n - 1)]
}

/** 解析十进制整数前缀（ASCII 片段，如 "5 ===== 结尾" → 5）；无数字返回 0。 */
func parseIntS(s: String): Int64 {
    var v: Int64 = 0
    var any = false
    for (b in s.toArray()) {
        if (b < 48 || b > 57) {
            break
        }
        any = true
        v = v * 10 + Int64(b) - 48
    }
    return if (any) { v } else { 0 }
}
