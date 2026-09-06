package zhc

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.io.*
import std.process.*

/**
 * LSP 代理（设计 §11 阶段 4，实测驱动的混合档架构，§13.1）。
 *
 * 实测结论（cjc 1.0.5 配套 LSPServer）：官方 LSPServer 可独立启动、能力齐全
 * （补全/悬停/定义/语义 Token），但 capabilities 无 diagnosticProvider——
 * didOpen 后不推送任何诊断。因此最终架构为混合档：
 *   - 语言能力：转发官方 LSPServer（第一档代理：initialize/didOpen/补全等）；
 *   - 诊断：zhc 自跑 cjc 编译 → 解析 JSON 诊断 → 教学翻译 → 位置经源映射
 *     还原回 .zc 坐标 → publishDiagnostics（第二档轮询）。
 *   - 官方 LSP 不可用时自动降级为仅诊断档（initialize 返回最小能力集，
 *     诊断照常），不报错（验收标准 §11）。
 *
 * 强制全量同步：代理把 initialize 响应中的 "textDocumentSync":2 改写为 1，
 * 客户端只发送全量 didChange，避免增量 range 应用。
 *
 * 帧 I/O（仓颉 runtime 行化实测，§13.1）：stdin/stdout/子进程管道的一切
 * read(Array<UInt8>) 均为行语义——等 \n 或 EOF 才返回，无换行的长连接数据
 * 永久阻塞；libc read(fd 0) 亦被 runtime 接管（EOF）。File.readFrom 则为
 * 字节级正常。因此最终架构：
 *   - 编辑器 ↔ zhc：行帧协议（JSON 单行 + \n，等价 readln/writeln）；
 *   - zhc ↔ LSPServer：stdInPipe 写标准 LSP 帧（写无行化限制）；输出经
 *     bash 重定向到临时文件，ServerStream 轮询（File.readFrom 全读 +
 *     parseFrameAt 偏移续解析，usleep 步进）。
 * zhc 的一切提示走 stderr，不得污染协议通道。
 */

// ==================== 帧 I/O ====================

/** 从流读取一行（到 \n，不含换行符）；EOF 且无数据返回 None。
 * 行化实测下等价 readln：无 \n 的数据等 EOF 才返回（行帧协议保证每帧换行结尾）。 */
func readLineBytes(reader: InputStream): ?Array<UInt8> {
    let bytes = ArrayList<UInt8>()
    while (true) {
        let buf = Array<UInt8>(1, { _ => 0 })
        let n = reader.read(buf)
        if (n <= 0) {
            // EOF：有缓冲内容也算一行（最后一帧可能无换行结尾）
            if (bytes.isEmpty()) {
                return None
            }
            let snap = ArrayList<UInt8>(bytes)
            let arr = Array<UInt8>(snap.size, { i => snap[i] })
            return Some(arr)
        }
        let b = buf[0]
        if (b == 10) {   // '\n'
            let snap = ArrayList<UInt8>(bytes)
            let arr = Array<UInt8>(snap.size, { i => snap[i] })
            return Some(arr)
        }
        bytes.add(b)
    }
    return None   // 不可达（while 为真循环），满足返回类型检查
}

/** 读编辑器行帧：一行 JSON（行帧协议）；EOF 返回 None。 */
func readEditorFrame(): ?String {
    let lineOpt = readLineBytes(getStdIn())
    if (lineOpt == None) {
        return None
    }
    return Some(String.fromUtf8(lineOpt.getOrThrow()))
}

/** 写编辑器行帧：JSON 单行 + 换行（行帧协议，避免行化写入端歧义）。 */
func writeEditorFrame(body: String) {
    let out = getStdOut()
    out.write("${body}\n".toArray())
    out.flush()
}

/** 写给 LSPServer 的标准 LSP 帧：Content-Length 头（UTF-8 字节数）+ body。 */
func writeFrame(stream: OutputStream, body: String) {
    let b = body.toArray()
    let head = "Content-Length: ${b.size}\r\n\r\n"
    stream.write(head.toArray())
    stream.write(b)
    stream.flush()
}

// ==================== ServerStream（文件轮询读）====================

foreign func usleep(microseconds: UInt32): Int32

/**
 * 从响应文件解析出一帧（标准 LSP 帧，\(offset\) 起）：
 * Content-Length 头 → \r\n\r\n → body（N 字节，UTF-8 字节数）。
 * body 未到齐或格式损坏返回 None（下轮轮询续解析）。
 * 返回 (下一帧起始偏移, 帧体 JSON)。
 */
func parseFrameAt(data: String, offset: Int64): ?(Int64, String) {
    let rest = data[offset..data.size]
    let hOpt = rest.indexOf("Content-Length:")
    if (hOpt == None) {
        return None
    }
    let h = hOpt.getOrThrow()
    let nlOpt = rest.indexOf("\r\n", h)
    if (nlOpt == None) {
        return None
    }
    let nl = nlOpt.getOrThrow()
    let len = try {
        Int64.parse(rest[h + "Content-Length:".size..nl].trimAscii())
    } catch (e: Exception) {
        return None
    }
    let heOpt = rest.indexOf("\r\n\r\n", nl)
    if (heOpt == None) {
        return None
    }
    let he = heOpt.getOrThrow() + 4
    if (rest.size - he < len) {
        return None   // body 未到齐，等待下轮轮询
    }
    return Some((offset + he + len, rest[he..he + len]))
}

/**
 * LSPServer 响应流（文件轮询，规避管道行化限制）：
 * File.readFrom 全读 + consumed 偏移防重复解析；usleep 50ms 步进。
 */
class ServerStream {
    public var respFile: String
    public var consumed: Int64

    public init(respFile: String) {
        this.respFile = respFile
        this.consumed = 0
    }

    /** 轮询响应文件解析下一帧；timeoutMs 超时返回 None。 */
    public func pollNextFrame(timeoutMs: Int64): ?String {
        var elapsed: Int64 = 0
        while (elapsed < timeoutMs) {
            if (exists(Path(respFile))) {
                let text = String.fromUtf8(File.readFrom(respFile))
                let parsed = parseFrameAt(text, consumed)
                match (parsed) {
                    case None => ()
                    case Some(p) =>
                        let (next, body) = p
                        consumed = next
                        return Some(body)
                }
            }
            unsafe { usleep(50000) }
            elapsed += 50
        }
        return None
    }
}

// ==================== 文档状态 ====================

/** 文档语言缓存（P-2 多方言）：code → LangPack / TypeMap，VS Code 多方言文档并发打开时共享。 */
var lspDocPacks = HashMap<String, LangPack>()
var lspDocMaps = HashMap<String, TypeMap>()

/** 打开中的方言文档：转译产物路径 + 源映射（诊断位置还原用）+ 文档语言。 */
class LspDoc {
    public var uri: String
    public var srcPath: String
    public var cjPath: String
    public var version: Int64
    public var cjText: String
    public var map: SourceMap
    public var lang: LangPack
    public var typeMap: TypeMap

    public init(uri: String, srcPath: String, cjPath: String, version: Int64, cjText: String,
                map: SourceMap, lang: LangPack, typeMap: TypeMap) {
        this.uri = uri
        this.srcPath = srcPath
        this.cjPath = cjPath
        this.version = version
        this.cjText = cjText
        this.map = map
        this.lang = lang
        this.typeMap = typeMap
    }
}

// ==================== 诊断收集（双通道，复用 §7.1 解析逻辑）====================

/** 一条结构化诊断（cjc JSON 字段原样 + 文本兑底行）。 */
class RawDiag {
    public var kind: String
    public var sev: String
    public var msg: String
    public var content: String
    public var file: String
    public var line: String
    public var col: String
    public var note: String

    public init(kind: String, sev: String, msg: String, content: String,
                file: String, line: String, col: String, note: String) {
        this.kind = kind
        this.sev = sev
        this.msg = msg
        this.content = content
        this.file = file
        this.line = line
        this.col = col
        this.note = note
    }
}

/**
 * 解析 cjc 输出为结构化诊断（与 printDiagnostics 同源的状态机）：
 * JSON 通道（DiagKind 锚定）收集字段；文本兑底通道收集 [error]/[warning] 行。
 * 不打印任何内容（LSP 场景 stdout 是协议通道）。
 */
func collectDiags(stdoutB: Array<Byte>, stderrB: Array<Byte>): ArrayList<RawDiag> {
    let out = ArrayList<RawDiag>()
    let outs = ArrayList<String>()
    if (stdoutB.size > 0) {
        outs.add(String.fromUtf8(stdoutB))
    }
    if (stderrB.size > 0) {
        outs.add(String.fromUtf8(stderrB))
    }
    for (chunk in outs) {
        var depth: Int64 = 0
        var inJson = false
        var sawDiag = false
        var bufKind = ""
        var bufSev = ""
        var bufMsg = ""
        var bufContent = ""
        var bufFile = ""
        var bufLine = ""
        var bufCol = ""
        var bufNote = ""
        var haveMsg = false
        var haveContent = false
        var inNotes = false
        var haveNote = false
        for (line in chunk.split("\n")) {
            let trimmed = line.trimAscii()
            if (trimmed.isEmpty()) {
                continue
            }
            if (!inJson) {
                if (trimmed.startsWith("{")) {
                    inJson = true
                    depth = 0
                    sawDiag = false
                    bufKind = ""
                    bufSev = ""
                    bufMsg = ""
                    bufContent = ""
                    bufFile = ""
                    bufLine = ""
                    bufCol = ""
                    bufNote = ""
                    haveMsg = false
                    haveContent = false
                    inNotes = false
                    haveNote = false
                } else {
                    // 文本兑底：锚定行收集，其余忽略
                    if (trimmed.startsWith("[error]")) {
                        out.add(RawDiag("", "error", trimmed[7..trimmed.size], "", "", "", "", ""))
                    } else if (trimmed.startsWith("[warning]")) {
                        out.add(RawDiag("", "warning", trimmed[9..trimmed.size], "", "", "", "", ""))
                    }
                    continue
                }
            }
            if (!sawDiag) {
                let k = extractField(trimmed, "DiagKind")
                if (k != None) {
                    sawDiag = true
                    bufKind = k.getOrThrow()
                }
            }
            if (sawDiag) {
                let sev = extractField(trimmed, "Severity")
                if (sev != None) {
                    bufSev = sev.getOrThrow()
                }
                if (!haveMsg) {
                    let m = extractField(trimmed, "Message")
                    if (m != None) {
                        bufMsg = m.getOrThrow()
                        haveMsg = true
                    }
                }
                if (!haveContent) {
                    let c = extractField(trimmed, "Content")
                    if (c != None && !c.getOrThrow().isEmpty()) {
                        bufContent = c.getOrThrow()
                        haveContent = true
                    }
                }
                if (bufFile.isEmpty()) {
                    let f = extractField(trimmed, "File")
                    if (f != None) {
                        bufFile = f.getOrThrow()
                    }
                }
                if (bufLine.isEmpty()) {
                    let l = extractIntField(trimmed, "Line")
                    if (l != None) {
                        bufLine = l.getOrThrow()
                    }
                }
                if (bufCol.isEmpty()) {
                    let c2 = extractIntField(trimmed, "Column")
                    if (c2 != None) {
                        bufCol = c2.getOrThrow()
                    }
                }
                if (trimmed.contains("\"Notes\"") || trimmed.contains("\"Helps\"")) {
                    inNotes = true
                }
                if (inNotes && !haveNote) {
                    let nm = extractField(trimmed, "Message")
                    if (nm != None && !nm.getOrThrow().isEmpty()) {
                        bufNote = nm.getOrThrow()
                        haveNote = true
                    }
                }
            }
            depth += countBraces(trimmed)
            if (depth <= 0 && inJson) {
                if (sawDiag) {
                    out.add(RawDiag(bufKind, bufSev, bufMsg, bufContent, bufFile, bufLine, bufCol, bufNote))
                }
                inJson = false
            }
        }
    }
    return out
}

// ==================== 工具 ====================

/** uri → 文件系统路径：file:// 剥离 + 百分号解码；untitled 落临时目录。 */
func uriToPath(uri: String): String {
    var p = uri
    if (p.startsWith("file://")) {
        p = p[7..p.size]
    } else if (p.startsWith("untitled:")) {
        let tmp = getTempDirectory().toString()
        var name = p["untitled:".size..p.size]
        if (name.isEmpty()) {
            name = "untitled"
        }
        p = "${tmp}/${name}.zc"
    }
    return pctDecode(p)
}

/** 百分号解码（%XX 连续字节按 UTF-8 还原；非编码字符原样）。 */
func pctDecode(s: String): String {
    let runes = s.toRuneArray()
    var sb = ""
    var i: Int64 = 0
    while (i < runes.size) {
        let c = runes[i]
        if (c == r'%' && i + 2 < runes.size) {
            let h1 = hexVal(runes[i + 1])
            let h2 = hexVal(runes[i + 2])
            if (h1 >= 0 && h2 >= 0) {
                // 收集连续 %XX 字节序列（UTF-8 多字节字符）
                var bytes = ArrayList<UInt8>()
                bytes.add(UInt8(h1 * 16 + h2))
                var j = i + 3
                while (j + 2 < runes.size && runes[j] == r'%') {
                    let g1 = hexVal(runes[j + 1])
                    let g2 = hexVal(runes[j + 2])
                    if (g1 < 0 || g2 < 0) {
                        break
                    }
                    bytes.add(UInt8(g1 * 16 + g2))
                    j += 3
                }
                let snap = ArrayList<UInt8>(bytes)
                let arr = Array<UInt8>(snap.size, { k => snap[k] })
                sb = "${sb}${String.fromUtf8(arr)}"
                i = j
                continue
            }
        }
        sb = "${sb}${c}"
        i += 1
    }
    return sb
}

/** 帧的 id 字段原文（数字或字符串）；无 id 返回空串。 */
func frameId(frame: String): String {
    let n = extractJsonNum(frame, "id")
    if (n != None) {
        return n.getOrThrow()
    }
    let s = extractJsonStr(frame, "id")
    if (s != None) {
        return jsonQuote(s.getOrThrow())
    }
    return ""
}

/** 初始化响应改写：textDocumentSync 2（增量）→ 1（全量）。 */
func forceFullSync(resp: String): String {
    let key = "\"textDocumentSync\":2"
    let at = resp.indexOf(key)
    if (at == None) {
        return resp
    }
    let i = at.getOrThrow()
    return "${resp[0..i]}\"textDocumentSync\":1${resp[i + key.size..resp.size]}"
}

// ==================== LSPServer 探测 ====================

/**
 * 构造 LSPServer 启动环境：继承当前环境并确保 CANGJIE_HOME 族变量。
 * 实测：LSPServer 缺 CANGJIE_HOME/CANGJIE_HOME_BIN 时静默挂起不响应
 * （§13.1）；PATH 前缀保证其内部工具链与 zhc 的 cjc 一致。
 */
func buildServerEnv(serverBin: String): HashMap<String, String> {
    let env = HashMap<String, String>()
    for ((k, v) in getVariables()) {
        env.add(k, v)
    }
    var home = ""
    let homeOpt = env.get("CANGJIE_HOME")
    if (homeOpt != None && !homeOpt.getOrThrow().isEmpty()) {
        home = homeOpt.getOrThrow()
    } else if (serverBin.endsWith("/tools/bin/LSPServer")) {
        home = serverBin[0..serverBin.size - "/tools/bin/LSPServer".size]
    }
    if (!home.isEmpty()) {
        if (!env.contains("CANGJIE_HOME")) {
            env.add("CANGJIE_HOME", home)
        }
        if (!env.contains("CANGJIE_HOME_BIN")) {
            env.add("CANGJIE_HOME_BIN", "${home}/bin")
        }
        let pathOpt = env.get("PATH")
        let newPath = "${home}/bin:${home}/tools/bin"
        if (pathOpt == None || pathOpt.getOrThrow().isEmpty()) {
            env.add("PATH", newPath)
        } else if (!pathOpt.getOrThrow().startsWith("${home}/bin")) {
            env.add("PATH", "${newPath}:${pathOpt.getOrThrow()}")
        }
        let ldOpt = env.get("LD_LIBRARY_PATH")
        if (ldOpt == None || ldOpt.getOrThrow().isEmpty()) {
            env.add("LD_LIBRARY_PATH", "${home}/lib:${home}/tools/lib")
        } else if (!ldOpt.getOrThrow().contains("${home}/tools/lib")) {
            env.add("LD_LIBRARY_PATH", "${home}/lib:${home}/tools/lib:${ldOpt.getOrThrow()}")
        }
    }
    return env
}

/** 探测官方 LSPServer：ZHC_LSP_BIN → CANGJIE_HOME/tools/bin → PATH 扫描。 */
func probeServer(): ?String {
    let envOpt = getVariable("ZHC_LSP_BIN")
    if (envOpt != None && !envOpt.getOrThrow().isEmpty()) {
        let p = envOpt.getOrThrow()
        if (exists(Path(p))) {
            return Some(p)
        }
    }
    let homeOpt = getVariable("CANGJIE_HOME")
    if (homeOpt != None && !homeOpt.getOrThrow().isEmpty()) {
        let cand = "${homeOpt.getOrThrow()}/tools/bin/LSPServer"
        if (exists(Path(cand))) {
            return Some(cand)
        }
    }
    let pathOpt = getVariable("PATH")
    if (pathOpt != None) {
        for (d in pathOpt.getOrThrow().split(":")) {
            let cand = "${d}/LSPServer"
            if (exists(Path(cand))) {
                return Some(cand)
            }
        }
    }
    return None
}

// ==================== 文档处理 ====================

/**
 * P-2 文档语言代码决议：editor languageId（zhc-dialect → zh；zhc-<code>，
 * 与 tools/vscode-extension/package.json 注册约定同源）→ uri 扩展名
 * （已安装语言包 lang_info.toml 声明）→ 进程默认（ZHCLANG）。
 */
func docLangCode(frame: String, srcPath: String, defaultCode: String): String {
    let lidOpt = extractJsonStr(frame, "languageId")
    if (lidOpt != None) {
        let lid = lidOpt.getOrThrow()
        if (lid == "zhc-dialect") {
            return "zh"
        }
        if (lid.startsWith("zhc-") && lid.size > 4) {
            let c = lid[4..lid.size]
            if (!c.isEmpty() && !c.contains("-")) {
                return c
            }
        }
    }
    match (langCodeByExt(srcPath, packRootCandidates())) {
        case None => return defaultCode
        case Some(c) => return c
    }
}

/** 取文档语言包（进程内缓存，不切换全局 UI 语言）；候选根链加载失败回退默认。 */
func docPackFor(code: String, fallback: LangPack): LangPack {
    match (lspDocPacks.get(code)) {
        case Some(p) => return p
        case None => ()
    }
    for (base in packRootCandidates()) {
        let loaded = loadLangPack(base, code)
        match (loaded) {
            case None => ()
            case Some(p) =>
                lspDocPacks.add(code, p)
                lspDocMaps.add(code, buildTypeMap(p.keywords, p.macros, p.aliases, p.modulePaths))
                return p
        }
    }
    return fallback
}

/** 文档类型本地化映射（缓存）；未加载过返回回退映射。 */
func docMapFor(code: String, fallback: TypeMap): TypeMap {
    match (lspDocMaps.get(code)) {
        case Some(m) => return m
        case None => return fallback
    }
}

/**
 * didOpen/didChange 处理（代理档与仅诊断档共用）：
 * 转译 → 落盘 .zhc/lsp/ → 建源映射 → 自跑 cjc → publishDiagnostics。
 * 语言按文档解析（P-2）：多方言文档可并发打开，互不串扰。
 */
func handleDocChange(frame: String, lang: LangPack, typeMap: TypeMap, docs: HashMap<String, LspDoc>): ?LspDoc {
    try {
        let uriOpt = extractJsonStr(frame, "uri")
        if (uriOpt == None) {
            return None
        }
        let uri = uriOpt.getOrThrow()
        let textOpt = extractJsonStr(frame, "text")
        if (textOpt == None) {
            return None
        }
        let v = extractJsonNum(frame, "version")
        let version = if (v != None) { Int64.parse(v.getOrThrow()) } else { 0 }
        let srcPath = uriToPath(uri)
        let code = docLangCode(frame, srcPath, lang.code)
        let dlang = docPackFor(code, lang)
        let dmap = docMapFor(code, typeMap)
        let lspDir = "${dirOf(srcPath)}/.zhc/lsp"
        ensureDir(lspDir)
        let cjPath = "${lspDir}/${baseNameOf(srcPath)}.cj"
        let result = transpileFull(textOpt.getOrThrow(), dlang)
        File.writeTo(cjPath, result.text.toArray())
        let doc = LspDoc(uri, srcPath, cjPath, version, result.text, SourceMap(textOpt.getOrThrow(), result.text, result.map), dlang, dmap)
        if (docs.contains(uri)) {
            docs.remove(uri)
        }
        docs.add(uri, doc)
        publishCjcDiags(doc)
        return Some(doc)
    } catch (e: Exception) {
        getStdErr().write((uiTextF("zhc lsp：文档处理失败：{0}", [e.message]) + "\n").toArray())
        return None
    }
}

/**
 * 自跑 cjc 编译并推送诊断（轮询档核心）：
 * 位置经源映射还原为 .zc 坐标（1-based → LSP 0-based），消息走 §7.2
 * 教学翻译链；无诊断时推送空数组（编辑器清除旧标记）。
 */
func publishCjcDiags(doc: LspDoc) {
    let lang = doc.lang
    let typeMap = doc.typeMap
    let outDir = "${dirOf(doc.cjPath)}/out"
    ensureDir(outDir)
    let (_, outB, errB) = try {
        executeWithOutput("cjc", ["--diagnostic-format=json", "--output-dir", outDir, doc.cjPath])
    } catch (e: Exception) {
        getStdErr().write((uiTextF("zhc lsp：cjc 启动失败：{0}", [e.message]) + "\n").toArray())
        (1, Array<Byte>(0, { _ => 0 }), Array<Byte>(0, { _ => 0 }))
    }
    let diags = collectDiags(outB, errB)
    var items = ArrayList<String>()
    for (d in diags) {
        var sl: Int64 = 0
        var sc: Int64 = 0
        if (!d.line.isEmpty() && !d.col.isEmpty()) {
            try {
                let (l, c) = doc.map.mapBack(Int64.parse(d.line), Int64.parse(d.col))
                sl = l
                sc = c
            } catch (e: Exception) {
                ()
            }
        }
        let notes = ArrayList<String>()
        if (!d.note.isEmpty()) {
            notes.add(d.note)
        }
        let out = translateDiag(lang, typeMap, d.kind, d.msg, d.content, notes)
        var msg = out.mainText
        if (!out.detail.isEmpty()) {
            msg = "${msg} — ${out.detail}"
        }
        if (!out.tip.isEmpty()) {
            msg = "${msg}（💡 ${out.tip}）"
        }
        let sev = if (d.sev == "warning") { 2 } else { 1 }
        // 诊断位置单点标记（start=end；LSP 0-based）
        let item = "{\"range\":{\"start\":{\"line\":${sl - 1},\"character\":${sc - 1}}," +
            "\"end\":{\"line\":${sl - 1},\"character\":${sc - 1}}}," +
            "\"severity\":${sev},\"source\":\"zhc\",\"message\":${jsonQuote(msg)}}"
        items.add(item)
    }
    var itemsJson = ""
    var first = true
    for (it in items) {
        if (!first) {
            itemsJson = "${itemsJson},"
        }
        itemsJson = "${itemsJson}${it}"
        first = false
    }
    let body = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\"," +
        "\"params\":{\"uri\":${jsonQuote(doc.uri)},\"version\":${doc.version}," +
        "\"diagnostics\":[${itemsJson}]}}"
    writeEditorFrame(body)
}

/** didClose：转发后推送空诊断（清标记）并移除文档状态。 */
func clearDiags(frame: String, docs: HashMap<String, LspDoc>) {
    let uriOpt = extractJsonStr(frame, "uri")
    if (uriOpt == None) {
        return
    }
    let uri = uriOpt.getOrThrow()
    let docOpt = docs.get(uri)
    match (docOpt) {
        case None => ()
        case Some(doc) =>
            let body = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\"," +
                "\"params\":{\"uri\":${jsonQuote(uri)},\"version\":${doc.version},\"diagnostics\":[]}}"
            writeEditorFrame(body)
            docs.remove(uri)
    }
}

/** 构造发给 LSPServer 的全量同步帧（text 为转译产物，uri/version 原样）。 */
func buildSyncFrame(method: String, doc: LspDoc, orig: String): String {
    let uri = jsonQuote(doc.uri)
    let version = doc.version
    if (method == "textDocument/didOpen") {
        let langIdOpt = extractJsonStr(orig, "languageId")
        let langId = if (langIdOpt != None) { jsonQuote(langIdOpt.getOrThrow()) } else { "\"cangjie\"" }
        return "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\"," +
            "\"params\":{\"textDocument\":{\"uri\":${uri},\"languageId\":${langId}," +
            "\"version\":${version},\"text\":${jsonQuote(doc.cjText)}}}}"
    }
    return "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\"," +
        "\"params\":{\"textDocument\":{\"uri\":${uri},\"version\":${version}}," +
        "\"contentChanges\":[{\"text\":${jsonQuote(doc.cjText)}}]}}"
}

// ==================== 主循环 ====================

/** 仅诊断档帧处理（降级/独立档共用）；返回 false 表示应退出循环。 */
func handleDiagOnlyFrame(frame: String, lang: LangPack, typeMap: TypeMap, docs: HashMap<String, LspDoc>): Bool {
    let methodOpt = extractJsonStr(frame, "method")
    match (methodOpt) {
        case None => ()
        case Some(method) =>
            if (method == "initialize") {
                let id = frameId(frame)
                writeEditorFrame("{\"jsonrpc\":\"2.0\",\"id\":${id},\"result\":{\"capabilities\":{\"textDocumentSync\":1}}}")
            } else if (method == "textDocument/didOpen" || method == "textDocument/didChange") {
                handleDocChange(frame, lang, typeMap, docs)
            } else if (method == "textDocument/didClose") {
                clearDiags(frame, docs)
            } else if (method == "shutdown") {
                let id = frameId(frame)
                writeEditorFrame("{\"jsonrpc\":\"2.0\",\"id\":${id},\"result\":null}")
            } else if (method == "exit") {
                return false
            } else {
                let id = frameId(frame)
                if (!id.isEmpty()) {
                    writeEditorFrame("{\"jsonrpc\":\"2.0\",\"id\":${id},\"result\":null}")
                }
            }
    }
    return true
}

/**
 * 代理档：转发官方 LSPServer（initialize 响应改全量同步；诊断自跑 cjc）。
 * 单线程"请求驱动 + 阻塞读"模型：编辑器行帧请求 → 转发 → 轮询 server
 * 响应文件 → 行帧回传；server 无主动推送（实测无 diagnosticProvider）。
 * initialize 无响应（server 失联）时本地最小能力集接管，自动降级不报错。
 */
func proxyLoop(server: SubProcess, respFile: String, lang: LangPack, typeMap: TypeMap) {
    let serverIn = server.stdInPipe
    let stream = ServerStream(respFile)
    let docs = HashMap<String, LspDoc>()
    var proxied = true
    while (true) {
        let frameOpt = readEditorFrame()
        if (frameOpt == None) {
            break   // 编辑器关闭连接
        }
        let frame = frameOpt.getOrThrow()
        if (!proxied) {
            if (!handleDiagOnlyFrame(frame, lang, typeMap, docs)) {
                break
            }
            continue
        }
        let methodOpt = extractJsonStr(frame, "method")
        match (methodOpt) {
            case None => ()   // 响应帧（编辑器不应主动发）：忽略
            case Some(method) =>
                if (method == "initialize") {
                    writeFrame(serverIn, frame)
                    let respOpt = stream.pollNextFrame(30000)
                    if (respOpt == None) {
                        getStdErr().write((uiText("zhc lsp：LSPServer 无响应，已降级为仅诊断模式。") + "\n").toArray())
                        let id = frameId(frame)
                        writeEditorFrame("{\"jsonrpc\":\"2.0\",\"id\":${id},\"result\":{\"capabilities\":{\"textDocumentSync\":1}}}")
                        proxied = false
                    } else {
                        writeEditorFrame(forceFullSync(respOpt.getOrThrow()))
                    }
                } else if (method == "initialized") {
                    writeFrame(serverIn, frame)
                } else if (method == "textDocument/didOpen" || method == "textDocument/didChange") {
                    let docOpt = handleDocChange(frame, lang, typeMap, docs)
                    match (docOpt) {
                        case None => ()
                        case Some(doc) =>
                            writeFrame(serverIn, buildSyncFrame(method, doc, frame))
                    }
                } else if (method == "textDocument/didClose") {
                    clearDiags(frame, docs)
                    writeFrame(serverIn, frame)
                } else if (method == "shutdown") {
                    writeFrame(serverIn, frame)
                    let respOpt = stream.pollNextFrame(30000)
                    if (respOpt != None) {
                        writeEditorFrame(respOpt.getOrThrow())
                    }
                } else if (method == "exit") {
                    writeFrame(serverIn, frame)
                    break
                } else {
                    // 其他请求（有 id）转发并回传响应；通知直接透传
                    let id = frameId(frame)
                    if (!id.isEmpty()) {
                        writeFrame(serverIn, frame)
                        let respOpt = stream.pollNextFrame(30000)
                        if (respOpt != None) {
                            writeEditorFrame(respOpt.getOrThrow())
                        }
                    } else {
                        writeFrame(serverIn, frame)
                    }
                }
        }
    }
}

/** 仅诊断档（降级）：无 LSPServer 时仍提供诊断；语言能力返回最小集。 */
func diagOnlyLoop(lang: LangPack, typeMap: TypeMap) {
    let docs = HashMap<String, LspDoc>()
    while (true) {
        let frameOpt = readEditorFrame()
        if (frameOpt == None) {
            break
        }
        if (!handleDiagOnlyFrame(frameOpt.getOrThrow(), lang, typeMap, docs)) {
            break
        }
    }
}

/** LSP 主入口（zhc lsp）：语言包 → 探测 → 代理档/仅诊断档。 */
public func lspMain(): Int64 {
    let (lang, typeMap) = try {
        let lang = resolveLangPack(resolveLang())
        let typeMap = buildTypeMap(lang.keywords, lang.macros, lang.aliases, lang.modulePaths)
        (lang, typeMap)
    } catch (e: Exception) {
        getStdErr().write((uiTextF("zhc lsp：语言包加载失败：{0}", [e.message]) + "\n").toArray())
        return 1
    }
    let serverOpt = probeServer()
    match (serverOpt) {
        case None =>
            // 降级：仅诊断档（官方 LSP 不可用，自动降级不报错）
            getStdErr().write((uiText("zhc lsp：未找到官方 LSPServer（可设置 ZHC_LSP_BIN 或将其放入 PATH），已降级为仅诊断模式。") + "\n").toArray())
            diagOnlyLoop(lang, typeMap)
            return 0
        case Some(bin) =>
            try {
                // 输出重定向到临时文件（管道读行化限制，§13.1）：bash -c exec 替换
                let pid = getProcessId()
                let respFile = "${getTempDirectory()}/zhc-lsp-${pid}-resp"
                let errFile = "${getTempDirectory()}/zhc-lsp-${pid}-err"
                let server = launch("bash", ["-c", "exec '${bin}' > '${respFile}' 2> '${errFile}'"],
                                    stdIn: ProcessRedirect.Pipe, stdOut: ProcessRedirect.Discard,
                                    stdErr: ProcessRedirect.Discard, environment: buildServerEnv(bin))
                proxyLoop(server, respFile, lang, typeMap)
            } catch (e: Exception) {
                getStdErr().write((uiTextF("zhc lsp：LSPServer 启动失败：{0}，已降级为仅诊断模式。", [e.message]) + "\n").toArray())
                diagOnlyLoop(lang, typeMap)
            }
            return 0
    }
}
