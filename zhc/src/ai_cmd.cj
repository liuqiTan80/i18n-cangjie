package zhc

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.process.*
import std.sort.*

/**
 * zhc ai（设计 §17.3）：按自然语言需求生成方言代码，自动编译验证迭代。
 *
 * 闭环（§17.3 ②）：LLM 产码 → 本命令自调用 `zhc check <临时.zc>`（子进程完整
 * 复用转译 + cjc 编译 + 母语诊断管线，与用户实际体验一致）→ 编译失败把母语
 * 诊断文本回喂 LLM（只要求输出修正后完整代码）→ 重试，最多 --iter N 轮
 * （默认 3）。成功或耗尽都写 -o 文件（默认 ai-输出.zc）+ 报告轮数/最终状态。
 *
 * 方言知识注入（§17.3 ①）：提示词携带关键字映射全表 + stdlib 高频别名 +
 * 模块路径全表（import 语句内生效），约束 LLM 优先写母语标识符；不确定的
 * API 允许官方英文名（转译原样通过，仍可编译）。
 *
 * 传输/配置走公共模块 ai_client.cj（§17.1/§17.4）；无模型或网络失败由
 * cmdAi 统一报错，不影响其他命令。
 */

/** zhc ai 子命令入口（main.cj case "ai" 分发）。 */
public func cmdAi(args: Array<String>): Int64 {
    if (args.size < 2) {
        println(uiText("用法：zhc ai <需求文本> [-o 输出.zc] [--iter N]"))
        println(uiText("  按自然语言需求生成方言代码，自动转译编译验证迭代"))
        println(uiText("  -o 输出文件（默认 ai-输出.zc）；--iter 迭代轮数（1-10，默认 3）；配置 AI 同 zhc translate"))
        return 1
    }
    let req = args[1]
    if (req.trimAscii().isEmpty()) {
        println(uiText("需求为空：请用一句话描述想实现的程序"))
        return 1
    }
    var outPath = "ai-输出.zc"
    var iter: Int64 = 3
    var i: Int64 = 2
    while (i < args.size) {
        if (args[i] == "-o" && i + 1 < args.size) {
            outPath = args[i + 1]
            i += 2
        } else if (args[i] == "--iter" && i + 1 < args.size) {
            let n = Int64.parse(args[i + 1])
            if (n < 1 || n > 10) {
                println(uiTextF("--iter 需为 1-10 的整数：{0}", [args[i + 1]]))
                return 1
            }
            iter = n
            i += 2
        } else {
            i += 1
        }
    }
    try {
        let lang = resolveLangPack(resolveLang())
        let cfg = loadAiConfig()
        return aiWrite(req, outPath, iter, lang, cfg)
    } catch (e: Exception) {
        println(uiTextF("ai 失败：{0}", [snippet(e.message, 300)]))
        return 1
    }
}

/** ai 主闭环（§17.3 ②③）：生成 → 验证 → 回喂迭代 → 落盘报告。 */
private func aiWrite(req: String, outPath: String, iter: Int64, lang: LangPack, cfg: AiConfig): Int64 {
    let system = aiCodePrompt(lang)
    var diag = ""
    var lastCode = ""
    var attempt: Int64 = 1
    while (attempt <= iter) {
        let msgs = ArrayList<ChatMsg>()
        msgs.add(ChatMsg("system", system))
        var user = "实现以下需求：${req}"
        if (!diag.isEmpty()) {
            user = "${user}\n\n上一轮代码编译失败，诊断如下（可参考修复）：\n${snippet(diag, 900)}" +
                "\n请修复后重新输出完整代码（仍用 ${lang.code} 方言，```cangjie 围栏）。"
        }
        msgs.add(ChatMsg("user", user))
        let resp = llmChat(cfg, msgs)
        let code = extractCodeBlock(resp)
        if (code.isEmpty()) {
            println(uiTextF("第 {0} 轮 AI 响应为空，重试…", [attempt.toString()]))
            attempt += 1
            continue
        }
        lastCode = code
        let (ok, diagText) = verifyAiCode(code)
        if (ok) {
            try {
                File.writeTo(outPath, code.toArray())
            } catch (e: Exception) {
                println(uiTextF("写输出文件失败：{0}", [e.message]))
                return 1
            }
            println(uiTextF("AI 生成代码编译通过（第 {0} 轮）：已写入 {1}", [attempt.toString(), outPath]))
            println(uiTextF("运行：zhc run {0}", [outPath]))
            return 0
        }
        diag = diagText
        if (attempt < iter) {
            println(uiTextF("第 {0} 轮编译失败，回喂诊断重试（剩余 {1} 轮）…", [attempt.toString(), (iter - attempt).toString()]))
        }
        attempt += 1
    }
    // 耗尽：仍落盘最后一份代码（人工可改），报告最终状态
    try {
        File.writeTo(outPath, lastCode.toArray())
    } catch (e: Exception) {
        println(uiTextF("写输出文件失败：{0}", [e.message]))
        return 1
    }
    println(uiTextF("迭代耗尽（{0} 轮均编译失败）：已写入 {1}，可人工修改后 zhc run", [iter.toString(), outPath]))
    return 1
}

/**
 * AI 系统提示词（§17.3 ① 方言知识注入）：
 * 关键字映射全表 + stdlib 高频别名（候选白名单内查当前语言包，换方言自适应）
 * + 模块路径全表；约束只写母语标识符（不确定用官方名，不编造）。
 * 注意：提示词不得出现「不合规」字样（acceptance mock 以该词分发重试场景）。
 */
private func aiCodePrompt(lang: LangPack): String {
    var kw = ""
    var first = true
    let kwList = ArrayList<String>()
    for (k in lang.keywords.keys()) {
        kwList.add(k)
    }
    sort(kwList)
    for (k in kwList) {
        if (!first) {
            kw = "${kw}，"
        }
        first = false
        kw = "${kw}${k}"
    }
    var al = ""
    first = true
    for (c in ["打印行", "打印", "读取行", "断言", "断言相等", "退出", "真", "假", "字符串", "字节数组",
               "整数", "整数32", "无符号整数", "浮点", "浮点32", "布尔", "向量", "哈希映射", "哈希集合",
               "数组", "范围", "元组", "选项", "异常", "结果", "字符", "单元", "空类型", "可比较", "可打印"]) {
        let v = lang.aliases.get(c)
        if (v == None) {
            continue
        }
        if (!first) {
            al = "${al}，"
        }
        first = false
        al = "${al}${c}=${v.getOrThrow()}"
    }
    var mp = ""
    first = true
    let mpList = ArrayList<String>()
    for (k in lang.modulePaths.keys()) {
        mpList.add(k)
    }
    sort(mpList)
    for (k in mpList) {
        if (!first) {
            mp = "${mp}，"
        }
        first = false
        mp = "${mp}${k}=${lang.modulePaths.get(k).getOrThrow()}"
    }
    return "你是「仓颉母语方言」代码生成助手：用户用 ${lang.name}（代码 ${lang.code}）书写仓颉程序，" +
        "映射表把官方仓颉翻译成 ${lang.name} 标识符。写代码时必须遵守：\n" +
        "1. 程序入口写 主函数()（对应官方 main）；import 语句以 导入 开头，路径与导入符号只能从下列母语名中选；\n" +
        "2. 关键字只能用母语名，禁止官方英文关键字（func/let/class/import/main 等）；\n" +
        "3. 本方言关键字全表：${kw}；\n" +
        "4. 常用标准库标识符（母语=官方）：${al}；\n" +
        "5. 模块路径（母语=官方，仅 import 语句内使用）：${mp}；\n" +
        "6. 不确定的 API 用官方英文名原样写（官方名可编译），不要编造不存在的 API 或映射；\n" +
        "7. 只输出一个 ```cangjie 代码块（含完整 import 与 主函数），不要输出任何其它文字。"
}

/**
 * 从 LLM 响应提取代码：剥 ```cangjie（或裸 ```）围栏；无围栏时全文返回。
 * 取首个围栏起始行之后、下一个围栏行之前的全部内容。
 * public：单测（ai_cmd_test.cj）与潜在复用。
 */
public func extractCodeBlock(resp: String): String {
    let lines = resp.split("\n")
    var start: Int64 = -1
    var k: Int64 = 0
    while (k < lines.size) {
        if (lines[k].trimAscii().startsWith("```")) {
            start = k
            break
        }
        k += 1
    }
    if (start < 0) {
        return resp.trimAscii()
    }
    var body = ""
    var first = true
    var j: Int64 = start + 1
    while (j < lines.size) {
        if (lines[j].trimAscii().startsWith("```")) {
            break
        }
        if (!first) {
            body = "${body}\n"
        }
        first = false
        body = "${body}${lines[j]}"
        j += 1
    }
    return body.trimAscii()
}

/**
 * 验证方言代码：写入临时 .zc，自调用当前可执行文件 `zhc check`（子进程完整
 * 复用转译 + cjc 编译 + 母语诊断管线）。返回 (是否通过, 诊断文本)。
 */
private func verifyAiCode(code: String): (Bool, String) {
    let dir = "${getTempDirectory()}/zhc-ai-${getProcessId()}"
    ensureDir(dir)
    let zcPath = "${dir}/ai.zc"
    File.writeTo(zcPath, code.toArray())
    let exe = SymbolicLink.readFrom("/proc/self/exe").toString()
    let (rc, outB, errB) = executeWithOutput(exe, ["check", zcPath])
    var text = String.fromUtf8(outB)
    if (errB.size > 0) {
        text = "${text}${String.fromUtf8(errB)}"
    }
    return (rc == 0, text)
}
