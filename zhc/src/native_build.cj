package zhc

import std.collection.*
import std.fs.*

/**
 * 阶段 5（s5t8）：cjpm 原生构建集成（设计 §16.2）。
 *
 * 实测结论（§13.1 第 31 条之后补记）：
 *   - 项目根放 build.cj（可执行脚本）→ cjpm build/run/test 每次在
 *     pre-build 阶段自动执行（输出进 build-script-cache/<...>/bin/script-log）；
 *   - 钩子执行先于源码编译：钩子生成的源文件会被本次编译包含（实测
 *     build.cj 写 src/generated.cj 后 main 调用其函数运行成功）；
 *   - 钩子编译失败或运行抛异常 → `Error: failed to run build script ...
 *     by operation 'pre-build'`，构建中断（错误安全）；
 *   - build.cj 的 main 必须显式标注 `: Unit`（否则推断报错）；
 *   - `cjpm build --skip-script` 可禁用钩子。
 *
 * 集成方式：
 *   - `zhc init --native` 生成的 build.cj 调用 `zhc native`（本文件）；
 *   - zhc native 把 src/ 全部方言 .zc 转译到 src/ 内同名 .cj
 *     （与方言源码并存；cjc/cjpm 只编译 .cj，忽略 .zc——§13 实测项 #6）；
 *     官方 .cj 原样不动；转译失败退出非零 → 钩子抛异常中断构建。
 */

/** zhc native 构建钩子模板（zhc init --native 写入项目根 build.cj）。
 * 注：仓颉字符串不支持三引号/字面换行，模板用 \n 转义；
 * build.cj 内部用拼接代替 ${} 插值，避免模板外层二次转义。 */
public let BUILD_CJ_TEMPLATE: String = "// zhc native 构建钩子（zhc-design §16.2）\n" +
    "// cjpm build/run/test 的 pre-build 阶段自动转译方言源码：\n" +
    "//   src/*.zc → src/*.cj（与方言源码并存，cjc 忽略 .zc）\n" +
    "// 由 `zhc init --native` 生成；删除本文件或 `cjpm build --skip-script` 即关闭。\n" +
    "// zhc 定位：ZHC_BIN 环境变量优先，其次 PATH。\n" +
    "import std.env.*\n" +
    "import std.process.*\n" +
    "\n" +
    "main(): Unit {\n" +
    "    // 1) 定位 zhc\n" +
    "    var zhcBin = \"\"\n" +
    "    let envBin = getVariable(\"ZHC_BIN\")\n" +
    "    if (envBin != None && !envBin.getOrThrow().isEmpty()) {\n" +
    "        zhcBin = envBin.getOrThrow()\n" +
    "    } else {\n" +
    "        let (code, out, _) = executeWithOutput(\"bash\", [\"-c\", \"command -v zhc\"])\n" +
    "        if (code == 0) {\n" +
    "            zhcBin = String.fromUtf8(out).trimAscii()\n" +
    "        }\n" +
    "    }\n" +
    "    if (zhcBin.isEmpty()) {\n" +
    "        println(\"zhc 构建钩子：未找到 zhc（设置 ZHC_BIN 或将 zhc 加入 PATH），跳过方言转译\")\n" +
    "        return\n" +
    "    }\n" +
    "    // 2) 转译方言源码（cwd 即项目根：cjpm 在项目根执行 build.cj）\n" +
    "    let (rcode, routB, rerrB) = executeWithOutput(zhcBin, [\"native\"])\n" +
    "    if (routB.size > 0) {\n" +
    "        print(String.fromUtf8(routB))\n" +
    "    }\n" +
    "    if (rerrB.size > 0) {\n" +
    "        print(String.fromUtf8(rerrB))\n" +
    "    }\n" +
    "    // 3) 转译失败 → 抛异常中断构建（实测：pre-build 异常 → cjpm build failed）\n" +
    "    if (rcode != 0) {\n" +
    "        throw Exception(\"zhc 转译失败（退出码 \" + rcode.toString() + \"），中止 cjpm 构建\")\n" +
    "    }\n" +
    "}\n"

/**
 * zhc native：把 src/ 全部方言 .zc 转译到 src/ 内同名 .cj（覆盖写）。
 * 供 cjpm 构建钩子（build.cj）调用；也可手动执行 `zhc native`。
 * 返回进程退出码（0 成功；非零时钩子将中断 cjpm 构建）。
 */
public func cmdNative(root: String): Int64 {
    let srcDir = "${root}/src"
    if (!exists(Path(srcDir))) {
        println(uiTextF("zhc native：{0} 不存在（非 zhc 项目？）", [srcDir]))
        return 1
    }
    let lang = resolveLangPack(resolveLang())
    // 从 cjpm.toml 读包名：转译产物 .cj 需 package 声明（cjpm 要求，cjc 不要求）
    var pkgName = ""
    let tomlPath = "${root}/cjpm.toml"
    if (exists(Path(tomlPath))) {
        let toml = parseToml(readTextFile(tomlPath))
        let pkgSec = toml.get("package")
        if (pkgSec != None) {
            let nm = pkgSec.getOrThrow().get("name")
            if (nm != None) {
                pkgName = nm.getOrThrow()
            }
        }
    }
    let entries = ArrayList<SourceEntry>()
    collectSourceFiles(srcDir, "", entries)
    var mappedCount: Int64 = 0
    var zhCount: Int64 = 0
    for (e in entries) {
        if (!e.isZh) {
            continue
        }
        // 目标 src/<同名>.cj；与既有 .cj 同名时覆盖（提示）
        let dst = zhToCj(e.absPath)
        if (!e.relPath.contains("/") && exists(Path(dst)) && dst != e.absPath) {
            println(uiTextF("提示：覆盖既有官方源文件 {0}", [dst]))
        }
        let srcText = readTextFile(e.absPath)
        scanUnicodeRisks(srcText, e.absPath)
        // s5t9a：增量缓存（§4.3）——命中跳过转译（native 钩子每次全量转译，
        // 大项目靠缓存省去未变更文件的 lexer 全流程）
        let fingerprint = langFingerprint(lang)
        match (lookupTranspile("${root}/.zhc/cache", srcText, fingerprint)) {
            case Some(cached) =>
                mappedCount += cached.total
                File.writeTo(dst, withPackage(cached.text, pkgName).toArray())
            case None =>
                let result = transpileFull(srcText, lang)
                mappedCount += result.total
                File.writeTo(dst, withPackage(result.text, pkgName).toArray())
                storeTranspile("${root}/.zhc/cache", srcText, fingerprint, result)
        }
        zhCount += 1
    }
    println(uiTextF("zhc native：转译 {0} 个方言源文件，替换 {1} 处方言标识符 → src/*.cj", [zhCount.toString(), mappedCount.toString()]))
    return 0
}
