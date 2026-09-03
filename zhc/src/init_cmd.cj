package zhc

import std.fs.*

/**
 * zhc init（设计 §8）：生成方言项目骨架。
 *   cjpm.toml  ：[package] 含 cjc-version（动态探测自 cjc --version，§3.10）
 *                与空 [dependencies]
 *   src/main.zc：方言入口模板（1.0 语法：`主函数()` 不带"函数"前缀，
 *                见 §12.2 风险 9）
 *   .gitignore ：.zhc/ 转译产物与 target/ 均忽略
 *
 * 1.0 适配：Directory.create 对已存在目录抛异常（先 exists 判断）；
 * File.writeTo 覆盖写；字符串 toArray() 为 UTF-8 字节。
 *
 * --native（设计 §16.2）：额外生成 build.cj 构建钩子，使 cjpm build/run/test
 * 直接驱动方言项目（pre-build 阶段自动转译 src 下 .zc → 同名 .cj）。
 */

/** 执行 init；返回进程退出码。项目名 "." 表示当前目录。 */
public func cmdInit(projName: String, native: Bool): Int64 {
    let root = projName
    let displayName = if (projName == ".") { uiText("当前目录") } else { projName }

    // 目标目录：已存在且非空则拒绝（避免覆盖既有项目）
    if (projName != "." && exists(Path(projName))) {
        let list = Directory.readFrom(projName)
        if (list.size > 0) {
            println(uiTextF("目录已存在且非空：{0}", [projName]))
            return 1
        }
    }
    if (!exists(Path(root))) {
        Directory.create(Path(root))
    }

    // 版本探测（§3.10：动态探测，不硬编码）
    var verText = "1.0.0"
    let version = probeCjcVersion()
    if (version == None) {
        println(uiText("警告：未能探测 cjc 版本（cjc --version 不可用？），cjc-version 回退 1.0.0。"))
    } else {
        verText = version.getOrThrow()
    }

    // src/main.zc 模板
    if (!exists(Path("${root}/src"))) {
        Directory.create(Path("${root}/src"))
    }
    let mainZh = "主函数() {\n    打印行(\"你好，仓颉！\")\n}\n"
    File.writeTo("${root}/src/main.zc", mainZh.toArray())

    // cjpm.toml：包名须符合 cjpm 命名规则（字母开头，仅 [-._a-zA-Z0-9]），
    // 因此取项目名最后一段（绝对路径如 /tmp/x/proj → proj），非法字符转下划线
    let rawName = if (projName == ".") { "zhc_demo" } else {
        let slashOpt = projName.lastIndexOf("/")
        if (slashOpt == None) { projName } else {
            let slash = slashOpt.getOrThrow()
            if (slash + 1 >= projName.size) { "zhc_demo" } else { projName[slash + 1..projName.size] }
        }
    }
    var pkgName = ""
    for (c in rawName.toRuneArray()) {
        if (pkgName.isEmpty() && !c.isAsciiLetter()) {
            pkgName += "_"
            continue
        }
        if (c.isAsciiLetter() || c.isAsciiNumber() || c == r'_' || c == r'-' || c == r'.') {
            pkgName += String(c)
        } else {
            pkgName += "_"
        }
    }
    if (pkgName.isEmpty()) {
        pkgName = "zhc_demo"
    }
    let cjpmToml = "[package]\ncjc-version = \"${verText}\"\nname = \"${pkgName}\"\nversion = \"0.1.0\"\ndescription = \"仓颉方言项目（zhc init 生成）\"\noutput-type = \"executable\"\ncompile-option = \"\"\n\n[dependencies]\n"
    File.writeTo("${root}/cjpm.toml", cjpmToml.toArray())

    // .gitignore
    File.writeTo("${root}/.gitignore", ".zhc/\n.zhc-run/\ntarget/\nbuild-script-cache/\n".toArray())

    println(uiTextF("已创建方言项目：{0}", [displayName]))
    println(uiTextF("  {0}/cjpm.toml   （cjc-version = {1}，init 动态探测）", [root, verText]))
    println(uiTextF("  {0}/src/main.zc （方言入口：主函数()）", [root]))
    println("  ${root}/.gitignore")
    if (native) {
        File.writeTo("${root}/build.cj", BUILD_CJ_TEMPLATE.toArray())
        println(uiTextF("  {0}/build.cj   （cjpm 构建钩子：pre-build 自动转译方言源码）", [root]))
        println(uiTextF("下一步：cd {0} && cjpm run（钩子自动转译；zhc run src/main.zc 仍可用）", [root]))
        println(uiText("提示：zhc 需在 PATH 中或设置 ZHC_BIN；`cjpm build --skip-script` 可临时禁用钩子"))
    } else {
        println(uiTextF("下一步：cd {0} && zhc run src/main.zc", [root]))
    }
    return 0
}
