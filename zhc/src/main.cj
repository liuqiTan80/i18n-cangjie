package zhc

import std.collection.*
import std.fs.*
import std.env.*
import std.process.*
import std.sort.*

/**
 * zhc CLI 入口（阶段 5：生态与规模化）。
 *
 * 流程（设计 §4.1 正向管线）：
 *   源码.zc ─→ L0 词法转译 ─→ .cj 写入 .zhc/ ─→ cjc 编译（JSON 诊断）
 *   ─→ 诊断翻译（DiagKind 错误码 → 消息表 → 类型本地化，§7）─→ 运行产物（run 模式）
 *
 * 语言包定位链（resolveLangPack）：环境变量 ZHC_LANG_PACKS → 当前目录
 * ./lang-packs → 可执行文件旁（含离线包父目录）→ ~/.zhc/lang-packs。
 * 界面语言当前固定中文（§5.5 审计修正：ZHCLANG 切换未实现）。
 *
 * 1.0 适配记录（本机 cjc 1.0.5 实测）：
 *   - main 入口声明不带 func 关键字（`func main` 是语法错误）；
 *   - Environment.get → std.env 顶层 getVariable；
 *   - ProcessBuilder → Process.runOutput（返回 (Int64, Array<Byte>, Array<Byte>)）；
 *   - File.exists → 顶层 exists(Path)；写文件用 File.writeTo（覆盖写，
 *     File.create 对已存在文件抛异常）；
 *   - cjc --output-dir 要求目录已存在，且产物固定名为 main；
 *   - JSON 诊断字段：DiagKind（稳定错误码）/Severity/Message/MainHint.Content/
 *     Location.File/Line/Column；具体消息在 Content（阶段 3 实测）；
 *   - String.lastIndexOf 返回 ?Int64（字节偏移）。
 */

main(args: Array<String>): Int64 {
    // 1.0 实测：args 不含程序名，args[0] 即第一个参数
    // §5.5 扩展：界面语言跟随 ZHCLANG——入口先静默装载语言包（resolveLangPack
    // 成功后已 setUiLang 接线），此后用法提示/帮助/进度等全部 UI 经 uiText/
    // uiTextF 查询当前语言包 ["界面消息"] 表；装载失败不阻断（未装载时回退
    // key 本身，即 zh 原文模板，中文用户无感）。
    try {
        resolveLangPack(resolveLang())
    } catch (e: Exception) {
        ()
    }
    if (args.size < 1) {
        printUsage()
        return 1
    }
    let cmd = args[0]
    match (cmd) {
        case "run" =>
            if (args.size < 2) {
                println(uiText("用法：zhc run <文件.zc>"))
                return 1
            }
            return runFile(args[1], true)
        case "check" =>
            if (args.size < 2) {
                println(uiText("用法：zhc check <文件.zc>"))
                return 1
            }
            return runFile(args[1], false)
        case "init" =>
            // --native（§16.2）：额外生成 build.cj 构建钩子，cjpm 直接驱动方言项目
            var nativeMode = false
            var projName = "."
            for (a in args[1..]) {
                if (a == "--native") {
                    nativeMode = true
                } else {
                    projName = a
                }
            }
            return cmdInit(projName, nativeMode)
        case "eject" =>
            if (args.size < 2) {
                println(uiText("用法：zhc eject <文件.zc>"))
                return 1
            }
            return cmdEject(args[1])
        case "lsp" =>
            // 阶段 4：LSP 代理（混合档：语言能力转发官方 LSPServer，诊断自跑 cjc）
            return lspMain()
        case "add" =>
            // 阶段 5：包管理器封装（§3.11：向 cjpm.toml [dependencies] 追加）
            if (args.size < 2) {
                println(uiText("用法：zhc add <库> [--git <URL> | --path <目录>]"))
                return 1
            }
            return cmdAdd(args)
        case "lang" =>
            // 阶段 5：语言包管理（§8：list/install/remove，install 校验扩展名冲突）
            if (args.size < 2) {
                println(uiText("用法：zhc lang list | install <目录> | remove <代码>"))
                return 1
            }
            return cmdLang(args)
        case "mapping" =>
            // 阶段 5：映射质量工具链（§10：check 五项门禁 / scaffold 语言包骨架；
            // §16.5：check --missing 诊断日志 → 待翻译清单）
            if (args.size < 2) {
                println(uiText("用法：zhc mapping check [--missing] | scaffold <源> <目标> | auto <库目录> [--install <库名>=<路径>]"))
                return 1
            }
            return cmdMapping(args)
        case "lint" =>
            // 阶段 5：方言风格检查（--fix）+ cjlint 集成（§16.6：转译 → cjlint JSON 报告 → 母语 lint）
            if (args.size < 2) {
                println(uiText("用法：zhc lint <文件.zc> [--fix]"))
                return 1
            }
            return cmdLint(args)
        case "expand" =>
            // §16.4：宏展开教学视图（转译 → cjc 展开 → 反向母语对照）
            return cmdExpand(args)
        case "test" =>
            // 阶段 5：方言测试（§16.8：转译全部方言源 → cjpm test → 翻译输出）
            return cmdTest()
        case "translate" =>
            // §17.2：AI 自动翻译第三方库公开 API → crates/ 映射（可选 --share 共享）
            return cmdTranslate(args)
        case "ai" =>
            // §17.3：需求 → 方言代码 → 自动编译验证迭代（可选 -o/--iter）
            return cmdAi(args)
        case "native" =>
            // §16.2：cjpm 构建钩子（build.cj）调用；转译 src/*.zc → src/*.cj
            return cmdNative(if (args.size >= 2) { args[1] } else { "." })
        case "help" =>
            printUsage()
            return 0
        case "--help" =>
            printUsage()
            return 0
        case "-h" =>
            printUsage()
            return 0
        case _ =>
            println(uiTextF("未知命令：{0}", [cmd]))
            printUsage()
            return 1
    }
}

func printUsage() {
    println(uiText("zhc —— 仓颉方言编程框架（阶段 5：生态与规模化）"))
    println(uiText("用法："))
    println(uiText("  zhc init [--native] [项目名]   生成项目骨架（--native 加 cjpm 构建钩子）"))
    println(uiText("  zhc run <文件.zc>      转译 → 编译 → 运行（workspace 根转译全部成员）"))
    println(uiText("  zhc check <文件.zc>    转译 → 编译检查（不运行；workspace 按模块输出诊断）"))
    println(uiText("  zhc eject <文件.zc>    导出标准 .cj 源码 + 反向映射碰撞报告"))
    println(uiText("  zhc add <库> [--git URL | --path 目录]   添加依赖（编辑 cjpm.toml）"))
    println(uiText("  zhc lang list|install <目录>|remove <代码>   语言包管理（用户目录安装）"))
    println(uiText("  zhc mapping check [--missing] | scaffold <源> <目标> | auto <库目录>   映射质量门禁 / 骨架 / 待翻译清单 / 三方库提取"))
    println(uiText("  zhc lint <文件.zc> [--fix]  方言风格检查 + cjlint 集成（母语报告；--fix 自动修复全角/空白/CRLF/空行）"))
    println(uiText("  zhc expand <文件.zc>   宏展开教学视图（展开前/后对照，反向母语）"))
    println(uiText("  zhc native             转译 src/*.zc → src/*.cj（cjpm 构建钩子调用）"))
    println(uiText("  zhc test               方言测试（转译 → cjpm test；workspace 测试全部方言成员）"))
    println(uiText("  zhc translate <库目录> [--share [导出名]]   AI 翻译第三方库 API（配置 ZHC_AI_MODEL 等）"))
    println(uiText("  zhc ai <需求> [-o 文件] [--iter N]           AI 按需求生成方言代码（自动编译验证迭代）"))
    println(uiText("  zhc lsp                启动 LSP 代理（语言能力转发官方 LSPServer，诊断自跑 cjc）"))
    println(uiText("  zhc help               显示本帮助"))
    println(uiText("环境变量：ZHC_LANG_PACKS  语言包根目录（默认当前目录）"))
    println(uiText("          ZHCLANG         方言语言代码（默认 zh；ru/en/ja…任意语言包）"))
    println(uiText("          ZHC_LSP_BIN    官方 LSPServer 路径（默认 PATH/CANGJIE_HOME 探测）"))
}

/**
 * 定位并加载语言包；失败时抛异常。
 * 定位链（优先级从高到低，§6.3 用户安装目录覆盖内置）：
 *   ① 环境变量 ZHC_LANG_PACKS（显式指定，未命中直接报错）
 *   ② 当前目录 ./lang-packs
 *   ③ 可执行文件旁 <exe目录>/lang-packs（Linux /proc/self/exe）
 *   ④ 用户目录 ~/.zhc/lang-packs
 */
func resolveLangPack(code: String): LangPack {
    let envDir = getVariable("ZHC_LANG_PACKS")
    if (envDir != None && !envDir.getOrThrow().isEmpty()) {
        let lang = loadLangPack(envDir.getOrThrow(), code)
        match (lang) {
            case None =>
                throw TomlParseError("未找到语言包 `${code}`：ZHC_LANG_PACKS 指向的目录中缺少 lang-packs/${code}")
            case Some(l) =>
                setUiLang(l)
                return l
        }
    }
    let candidates = ArrayList<String>()
    candidates.add(".")
    let exeDir = executableDir()
    if (exeDir != None) {
        candidates.add(exeDir.getOrThrow())
        // 离线发布包结构（§14.3/s5t9c）：bin/zhc-core + 顶层 lang-packs/
        candidates.add(dirOf(exeDir.getOrThrow()))
    }
    let home = getVariable("HOME")
    if (home != None && !home.getOrThrow().isEmpty()) {
        candidates.add("${home.getOrThrow()}/.zhc")
    }
    for (base in candidates) {
        let lang = loadLangPack(base, code)
        match (lang) {
            case None => ()
            case Some(l) =>
                setUiLang(l)
                return l
        }
    }
    throw TomlParseError("未找到语言包 `${code}`：请设置 ZHC_LANG_PACKS、在当前目录提供 lang-packs/${code}，或安装到 ~/.zhc/lang-packs")
}

/** 可执行文件所在目录（Linux /proc/self/exe 符号链接）；不可用时返回 None。 */
func executableDir(): ?String {
    try {
        let exePath = SymbolicLink.readFrom("/proc/self/exe")
        let d = dirOf(exePath.toString())
        if (d == "." || d.isEmpty()) {
            return None
        }
        return d
    } catch (e: Exception) {
        return None
    }
}

/**
 * run/check 入口（设计 §4.1 正向管线）。
 * 项目模式：源文件向上找到项目根（cjpm.toml）且 src/ 下含方言源码时，
 * 转译整个 src/ 到 .zhc/src/ 并 cjc -p 编译；否则单文件模式（cjc 单文件）。
 * 项目模式判定兼容 zhc 自身仓库（src/ 全为 .cj）与散文件场景。
 */
func runFile(path: String, runMode: Bool): Int64 {
    let lang = resolveLangPack(resolveLang())

    if (!exists(Path(path))) {
        println(uiTextF("文件不存在：{0}", [path]))
        return 1
    }
    // 目录参数（如 `zhc check .`）：以该目录为基准进入项目/workspace 模式
    var isDir = false
    try {
        Directory.readFrom(path)
        isDir = true
    } catch (e: Exception) {
        isDir = false
    }
    if (isDir) {
        let rootOpt = findProjectRoot(path)
        if (rootOpt != None) {
            let root = rootOpt.getOrThrow()
            if (exists(Path("${root}/cjpm.toml")) && isWorkspaceRoot(readTextFile("${root}/cjpm.toml"))) {
                return runWorkspace(root, lang, runMode)
            }
            let wsOpt = findWorkspaceRoot(root)
            if (wsOpt != None) {
                return runWorkspace(wsOpt.getOrThrow(), lang, runMode)
            }
            if (dirHasZhFiles("${root}/src")) {
                return runProject(root, lang, runMode)
            }
        }
        println(uiTextF("目录参数未匹配项目/workspace：{0}", [path]))
        return 1
    }
    let src = readTextFile(path)
    // 坑 ⑫：Unicode 安全检查（零宽/双向控制符告警不阻断，位置精确）
    scanUnicodeRisks(src, path)

    let rootOpt = findProjectRoot(dirOf(path))
    if (rootOpt != None) {
        let root = rootOpt.getOrThrow()
        // workspace 多模块（§11 s5t7）：根 cjpm.toml 含 [workspace] 节 →
        // 转译全部成员包 + 按模块输出诊断（run 模式依次运行可执行成员）
        if (exists(Path("${root}/cjpm.toml")) && isWorkspaceRoot(readTextFile("${root}/cjpm.toml"))) {
            return runWorkspace(root, lang, runMode)
        }
        // 成员根：向上查找 workspace 根（成员内任意位置驱动整个 workspace）
        let wsOpt = findWorkspaceRoot(root)
        if (wsOpt != None) {
            return runWorkspace(wsOpt.getOrThrow(), lang, runMode)
        }
        if (dirHasZhFiles("${root}/src")) {
            return runProject(root, lang, runMode)
        }
    }
    return runSingle(path, src, lang, runMode)
}

/** 单文件模式：转译 → cjc 单文件编译 →（可选）运行。 */
func runSingle(path: String, src: String, lang: LangPack, runMode: Bool): Int64 {
    // ① 完整转译管线（§4.1）：词法（含插值态）→ import 路径 → 别名（豁免集）
    // s5t9a：增量缓存（§4.3）——键 = 源文本 + 语言包指纹
    let workDir = ".zhc"
    let fingerprint = langFingerprint(lang)
    let result: TranspileResult
    match (lookupTranspile("${workDir}/cache", src, fingerprint)) {
        case Some(cached) =>
            result = cached
        case None =>
            result = transpileFull(src, lang)
            storeTranspile("${workDir}/cache", src, fingerprint, result)
    }
    let mappedCount = result.total

    // ② 写入转译产物（隔离目录 .zhc/，见 §12.2 第 10 条）
    if (!exists(Path(workDir))) {
        Directory.create(Path(workDir))
    }
    let outBase = baseNameOf(path)
    let cjPath = "${workDir}/${outBase}.cj"
    let outDir = "${workDir}/out"
    if (!exists(Path(outDir))) {
        Directory.create(Path(outDir))
    }
    File.writeTo(cjPath, result.text.toArray())

    // ③ cjc 编译（JSON 诊断；--output-dir 目录需已存在）
    let (code, stdoutB, stderrB) = executeWithOutput(
        "cjc", ["--diagnostic-format=json", "--output-dir", outDir, cjPath])
    // 阶段 4：诊断位置映射回源 .zc（产物路径 → 源映射/源路径）
    let maps = HashMap<String, SourceMap>()
    maps.add(cjPath, SourceMap(src, result.text, result.map))
    let srcs = HashMap<String, String>()
    srcs.add(cjPath, path)
    printDiagnostics(stdoutB, stderrB, lang, buildTypeMap(lang.keywords, lang.macros, lang.aliases, lang.modulePaths),
                     DiagLocator(maps, srcs))

    if (code != 0) {
        println(uiTextF("❌ 编译失败（退出码 {0}）：已替换 {1} 处方言标识符。", [code.toString(), mappedCount.toString()]))
        return code
    }
    println(uiTextF("✅ 编译成功：替换方言标识符 {0} 处。", [mappedCount.toString()]))

    // ④ 运行（run 模式；cjc 单文件产物固定名为 main）
    if (runMode) {
        let exePath = "${outDir}/main"
        if (!exists(Path(exePath))) {
            println(uiTextF("未找到编译产物：{0}", [exePath]))
            return 1
        }
        let (rcode, routB, rerrB) = executeWithOutput(exePath, [])
        if (routB.size > 0) {
            print(String.fromUtf8(routB))
        }
        if (rerrB.size > 0) {
            print(String.fromUtf8(rerrB))
        }
        if (rcode != 0) {
            return rcode
        }
    }
    return 0
}

/**
 * 项目模式：转译 src/ 全部方言源码到 .zhc/src/（保留相对结构），
 * 官方 .cj 原样复制混编；cjc -p 编译整个目录（cjc 忽略 .zc，见 §13 实测项 #6）。
 * 转译 + 编译主体复用 workspace.cj 的 buildMember（单成员视角）。
 */
func runProject(root: String, lang: LangPack, runMode: Bool): Int64 {
    let r = buildMember(root, lang)
    printDiagnostics(r.stdoutB, r.stderrB, lang, buildTypeMap(lang.keywords, lang.macros, lang.aliases, lang.modulePaths),
                     DiagLocator(r.maps, r.srcs))
    if (r.code != 0) {
        println(uiTextF("❌ 编译失败（退出码 {0}）：已替换 {1} 处方言标识符。", [r.code.toString(), r.mappedCount.toString()]))
        return r.code
    }
    println(uiTextF("✅ 编译成功：替换方言标识符 {0} 处。", [r.mappedCount.toString()]))

    // ④ 运行（run 模式；cjc -p 产物固定名为 main）
    if (runMode) {
        let exePath = "${root}/.zhc/out/main"
        if (!exists(Path(exePath))) {
            println(uiTextF("未找到编译产物：{0}", [exePath]))
            return 1
        }
        let (rcode, routB, rerrB) = executeWithOutput(exePath, [])
        if (routB.size > 0) {
            print(String.fromUtf8(routB))
        }
        if (rerrB.size > 0) {
            print(String.fromUtf8(rerrB))
        }
        if (rcode != 0) {
            return rcode
        }
    }
    return 0
}

/**
 * eject（设计 §8）：导出标准 .cj 源码 + 反向映射碰撞报告（§5.1 第 7 条）。
 * 项目内（src/ 含方言源码）导出整个 src/ 到 eject/src/；否则单文件导出。
 */
func cmdEject(path: String): Int64 {
    let lang = resolveLangPack(resolveLang())
    if (!exists(Path(path))) {
        println(uiTextF("文件不存在：{0}", [path]))
        return 1
    }

    // 碰撞报告：同一官方词对应多个母语词时，反向展示存在歧义（§5.1 第 7 条）
    let rev = buildReverseMap(lang.keywords, lang.macros, lang.aliases)
    if (rev.collisions.isEmpty()) {
        println(uiText("反向映射无碰撞（每个官方词唯一母语词）。"))
    }
    for (line in rev.collisions) {
        println(line)
    }

    let rootOpt = findProjectRoot(dirOf(path))
    if (rootOpt != None) {
        let root = rootOpt.getOrThrow()
        if (dirHasZhFiles("${root}/src")) {
            return ejectProject(root, lang)
        }
    }

    // 单文件：输出到同目录 <名>.cj
    var cjPath = path
    let dotOpt = cjPath.lastIndexOf(".")
    if (dotOpt != None) {
        cjPath = cjPath[0..dotOpt.getOrThrow()]
    }
    cjPath = "${cjPath}.cj"
    let result = transpileFull(readTextFile(path), lang)
    File.writeTo(cjPath, result.text.toArray())
    println(uiTextF("已导出官方源码：{0}（替换方言标识符 {1} 处）", [cjPath, result.total.toString()]))
    println(uiTextF("可直接编译：mkdir -p out && cjc {0} --output-dir out", [cjPath]))
    return 0
}

/** 项目 eject：转译 src/ 全部方言源码到 eject/src/（保留相对结构）。 */
func ejectProject(root: String, lang: LangPack): Int64 {
    let outRoot = "${root}/eject"
    ensureDir(outRoot)
    var mappedCount: Int64 = 0
    let entries = ArrayList<SourceEntry>()
    collectSourceFiles("${root}/src", "", entries)
    for (e in entries) {
        let dst = if (e.isZh) { zhToCj("${outRoot}/src/${e.relPath}") } else { "${outRoot}/src/${e.relPath}" }
        ensureParentDir(dst)
        if (e.isZh) {
            let result = transpileFull(readTextFile(e.absPath), lang)
            mappedCount += result.total
            File.writeTo(dst, result.text.toArray())
        } else {
            File.writeTo(dst, readTextFile(e.absPath).toArray())
        }
    }
    println(uiTextF("已导出项目官方源码：{0}/src/（替换方言标识符 {1} 处）", [outRoot, mappedCount.toString()]))
    println(uiTextF("可直接编译：cd {0} && mkdir -p out && cjc -p src --output-dir out && ./out/main", [outRoot]))
    return 0
}

/** 项目源码条目（relPath 相对 src 根）。 */
public class SourceEntry {
    public var absPath: String
    public var relPath: String
    public var isZh: Bool

    public init(absPath: String, relPath: String, isZh: Bool) {
        this.absPath = absPath
        this.relPath = relPath
        this.isZh = isZh
    }
}

/** 递归收集目录下的 .zc/.cj 源文件；名字排序保证确定性（§6.3）。 */
func collectSourceFiles(dir: String, relPrefix: String, out: ArrayList<SourceEntry>): Unit {
    if (!exists(Path(dir))) {
        return
    }
    let list = Directory.readFrom(dir)
    let names = ArrayList<String>()
    let dirs = ArrayList<String>()
    for (f in list) {
        if (f.isDirectory()) {
            if (!f.name.startsWith(".")) {   // 跳过隐藏目录（.zhc/.git 等转译与版本目录）
                dirs.add(f.name)
            }
        } else {
            names.add(f.name)
        }
    }
    sort(names)
    sort(dirs)
    for (name in names) {
        let rel = if (relPrefix.isEmpty()) { name } else { "${relPrefix}/${name}" }
        if (name.endsWith(".zc")) {
            out.add(SourceEntry("${dir}/${name}", rel, true))
        } else if (name.endsWith(".cj")) {
            out.add(SourceEntry("${dir}/${name}", rel, false))
        }
    }
    for (name in dirs) {
        let rel = if (relPrefix.isEmpty()) { name } else { "${relPrefix}/${name}" }
        collectSourceFiles("${dir}/${name}", rel, out)
    }
}

/** 目录（递归）下是否存在 .zc 方言源码。 */
func dirHasZhFiles(dir: String): Bool {
    if (!exists(Path(dir))) {
        return false
    }
    let list = Directory.readFrom(dir)
    for (f in list) {
        if (f.isDirectory()) {
            if (!f.name.startsWith(".")) {
                if (dirHasZhFiles("${dir}/${f.name}")) {
                    return true
                }
            }
        } else if (f.name.endsWith(".zc")) {
            return true
        }
    }
    return false
}

/** .zc 转译产物路径：把 .zc 后缀替换为 .cj（后缀为 ASCII，字节切片安全）。 */
func zhToCj(path: String): String {
    if (path.endsWith(".zc")) {
        return "${path[0..path.size - 3]}.cj"
    }
    return path
}

/** 确保目录存在（含中间目录）；已存在则跳过（1.0 命名参数 recursive: true）。 */
func ensureDir(path: String) {
    if (!exists(Path(path))) {
        Directory.create(Path(path), recursive: true)
    }
}

/** 确保目标文件的父目录存在。 */
func ensureParentDir(filePath: String) {
    let d = dirOf(filePath)
    if (d != ".") {
        ensureDir(d)
    }
}

/**
 * 打印诊断（阶段 3：教学诊断；阶段 4：位置映射回源 .zc）。双通道解析（§7.1）：
 *   - JSON 通道：逐行收集诊断对象（DiagKind 字段识别），对象闭合后按
 *     §7.2 决策链翻译（错误码表 → 消息表 → 类型本地化）并格式化输出；
 *     位置经 locator 反向还原到方言源码坐标（§5.6 源映射）；
 *   - 文本通道（兑底）：非 JSON 行中 [error]/[warning] 锚定行提取消息
 *     做消息表翻译，其余行原样透传；任何解析失败不崩溃（坑 ⑦）。
 */
func printDiagnostics(stdoutB: Array<Byte>, stderrB: Array<Byte>, lang: LangPack, map: TypeMap, loc: DiagLocator) {
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
                    printTextFallback(trimmed, lang, map)
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
                // 字段收集：Message/Content 取首次（Notes 内的同名行不覆盖）
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
            // 括号深度：引号感知计数（诊断消息文本里可能含 `}`/`{`，
            // 如 found '}'，误计会导致 JSON 提前退出、尾部字段透传）
            depth += countBraces(trimmed)
            if (depth <= 0 && inJson) {
                if (sawDiag) {
                    printDiag(lang, map, loc, bufKind, bufSev, bufMsg, bufContent,
                              bufFile, bufLine, bufCol, bufNote)
                }
                inJson = false
            }
        }
    }
}

/**
 * 引号感知的括号计数：双引号字符串内的 `{`/`}` 不计（JSON 诊断消息文本
 * 可能含花括号）。转义处理：`\\"`（奇数个反斜杠后的引号）不切换字符串态。
 */
func countBraces(line: String): Int64 {
    var d: Int64 = 0
    var inStr = false
    let runes = line.toRuneArray()
    var i = 0
    while (i < runes.size) {
        let r = runes[i]
        if (r == r'"') {
            var backslashes: Int64 = 0
            var j = i - 1
            while (j >= 0 && runes[j] == r'\\') {
                backslashes += 1
                j -= 1
            }
            if (backslashes % 2 == 0) {
                inStr = !inStr
            }
        } else if (!inStr) {
            if (r == r'{') {
                d += 1
            } else if (r == r'}') {
                d -= 1
            }
        }
        i += 1
    }
    return d
}

/** 格式化输出一条已翻译诊断（教学导向，§7.4/§16.9）。
 * 位置经 locator 映射回源 .zc（诊断的 File 是转译产物 .zhc/ 下的 .cj）。 */
func printDiag(lang: LangPack, map: TypeMap, loc: DiagLocator, kind: String, sev: String, msg: String,
               content: String, file: String, line: String, col: String, note: String) {
    let notes = ArrayList<String>()
    if (!note.isEmpty()) {
        notes.add(note)
    }
    let out = translateDiag(lang, map, kind, msg, content, notes)
    let sevLabel = if (sev == "error") { uiText("错误") } else if (sev == "warning") { uiText("警告") } else { sev }
    var head = "[${sevLabel}] ${out.mainText}"
    if (!file.isEmpty()) {
        let (srcFile, srcLine, srcCol) = loc.resolve(file, line, col)
        head = "${head}  ${srcFile}:${srcLine}:${srcCol}"
    }
    println(head)
    if (!out.detail.isEmpty()) {
        println("  ↳ ${out.detail}")
    }
    if (!out.tip.isEmpty()) {
        println("  💡 ${out.tip}")
    }
    if (!out.fix.isEmpty()) {
        println("  ${uiText("修复示例（可直接粘贴）：")}")
        println("  ```")
        for (fl in out.fix.split("\n")) {
            println("  ${fl}")
        }
        println("  ```")
    }
    for (nl in out.notes) {
        println("  · ${nl}")
    }
}

/** 文本通道兑底（§7.1）：[error]/[warning] 锚定行做消息表翻译，其余透传。 */
func printTextFallback(trimmed: String, lang: LangPack, map: TypeMap) {
    var prefix = ""
    var msg = trimmed
    if (trimmed.startsWith("[error]")) {
        prefix = "[${uiText("错误")}]"
        msg = trimmed[7..trimmed.size]
    } else if (trimmed.startsWith("[warning]")) {
        prefix = "[${uiText("警告")}]"
        msg = trimmed[9..trimmed.size]
    } else {
        println(trimmed)
        return
    }
    let m = matchMessage(lang.msgEntries, msg.trimAscii())
    match (m) {
        case None =>
            println("${prefix} ${localizeText(msg.trimAscii(), map)}")
        case Some(mm) =>
            var t = renderEntry(mm, map)
            if (t.isEmpty()) {
                t = localizeText(msg.trimAscii(), map)
            }
            println("${prefix} ${t}")
            if (!mm.entry.tip.isEmpty()) {
                println("  💡 ${mm.entry.tip}")
            }
    }
}

/**
 * 极简 JSON 字段提取：行内找 `"字段": "值"`，返回引号值（去转义）；
 * 找不到返回 None。基于 Rune 数组：行内中文与转义序列均安全。
 */
func extractField(line: String, field: String): ?String {
    let runes = line.toRuneArray()
    let keyRunes = "\"${field}\"".toRuneArray()
    let klen = keyRunes.size
    var ki: Int64 = -1
    var i = 0
    while (i + klen <= runes.size && ki < 0) {
        var matched = true
        var k2 = 0
        while (k2 < klen) {
            if (runes[i + k2] != keyRunes[k2]) {
                matched = false
                break
            }
            k2 += 1
        }
        if (matched) {
            ki = i
        }
        i += 1
    }
    if (ki < 0) {
        return None
    }
    var j = ki + klen
    while (j < runes.size && (runes[j] == r' ' || runes[j] == r':' || runes[j] == r'\t')) {
        j += 1
    }
    if (j >= runes.size || runes[j] != r'"') {
        return None
    }
    var sb = ""
    var k = j + 1
    while (k < runes.size) {
        let c = runes[k]
        if (c == r'\\' && k + 1 < runes.size) {
            sb = "${sb}${runes[k + 1]}"
            k += 2
        } else if (c == r'"') {
            return sb
        } else {
            sb = "${sb}${c}"
            k += 1
        }
    }
    return None
}

/**
 * 极简 JSON 整数提取：行内找 `"字段": 数字`，返回数字字符串；
 * 找不到返回 None（Line/Column 字段专用，值无引号）。
 */
func extractIntField(line: String, field: String): ?String {
    let key = "\"${field}\":"
    let at = line.indexOf(key)
    if (at == None) {
        return None
    }
    var i = at.getOrThrow() + key.size
    let runes = line.toRuneArray()
    while (i < runes.size && (runes[i] == r' ' || runes[i] == r'\t')) {
        i += 1
    }
    var sb = ""
    while (i < runes.size && runes[i] >= r'0' && runes[i] <= r'9') {
        sb = "${sb}${runes[i]}"
        i += 1
    }
    if (sb.isEmpty()) {
        return None
    }
    return sb
}

/** 取路径的文件名（去掉目录与扩展名）。 */
func baseNameOf(path: String): String {
    var name = path
    let slashOpt = name.lastIndexOf("/")
    if (slashOpt != None) {
        let slash = slashOpt.getOrThrow()
        name = name[slash + 1..name.size]
    }
    let dotOpt = name.lastIndexOf(".")
    if (dotOpt != None) {
        let dot = dotOpt.getOrThrow()
        name = name[0..dot]
    }
    return name
}
