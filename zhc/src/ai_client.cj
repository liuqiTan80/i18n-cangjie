package zhc

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.process.*

/**
 * AI 辅助公共模块（设计 §17.4）：zhc translate / zhc ai 共用。
 *
 * 传输层实测结论（std.net 1.0 仅 socket 层，无 HTTP/TLS 客户端）：LLM 调用走
 * 外部进程 POST {base}/chat/completions（OpenAI 兼容协议，Ollama 亦暴露
 * /v1/chat/completions，单代码路径）：
 *   - curl（优先，https 支持完整；-m 120 超时）
 *   - 缺 curl 自动降级 python3 urllib.request（timeout=120）
 *   - 两者皆无则明确报错
 * 请求体写临时文件（--data-binary @file），规避超长命令行与引号转义。
 * 响应协议统一为：<body>\n<http_code>（curl -w 与 python 脚本同款）。
 * 配置（§17.1）：环境变量 ZHC_AI_BASE / ZHC_AI_KEY / ZHC_AI_MODEL >
 * ~/.zhc/ai.toml [ai] 节 > 默认 https://api.openai.com/v1；model 为空时
 * 明确报错引导设置（不猜模型名）。密钥不进 git/日志/提示词，也不进
 * 命令行参数（经临时头文件/密钥文件传递，用后统一清理）。
 */

/** AI 后端配置。 */
public class AiConfig {
    public var base: String
    public var key: String
    public var model: String

    public init(base: String, key: String, model: String) {
        this.base = base
        this.key = key
        this.model = model
    }
}

/** LLM 调用错误（含可诊断信息：状态码/响应摘要）。 */
public class LlmError <: Exception {
    public init(message: String) {
        super(message)
    }
}

/** chat 消息（role: system/user/assistant）。 */
public class ChatMsg {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        this.role = role
        this.content = content
    }
}

var curlProbed: Bool = false
var curlOk: Bool = false

/** curl 可用性探测（静态缓存：一次进程探测，后续复用）。 */
private func haveCurl(): Bool {
    if (!curlProbed) {
        let (code, _, _) = executeWithOutput("curl", ["--version"])
        curlOk = code == 0
        curlProbed = true
    }
    return curlOk
}

var pyProbed: Bool = false
var pyOk: Bool = false

/** python3 可用性探测（静态缓存）。 */
private func havePython3(): Bool {
    if (!pyProbed) {
        let (code, _, _) = executeWithOutput("python3", ["--version"])
        pyOk = code == 0
        pyProbed = true
    }
    return pyOk
}

/**
 * 加载 AI 配置（§17.1）：环境变量 > ~/.zhc/ai.toml [ai] 节 > 默认。
 * ai.toml 缺失/解析失败静默回退（仅 AI 命令受影响，不拖累其他命令）。
 */
public func loadAiConfig(): AiConfig {
    var base = "https://api.openai.com/v1"
    var key = ""
    var model = ""
    let home = getVariable("HOME")
    if (home != None && !home.getOrThrow().isEmpty()) {
        let aiPath = "${home.getOrThrow()}/.zhc/ai.toml"
        if (exists(Path(aiPath))) {
            try {
                let tables = parseToml(readTextFile(aiPath))
                match (tables.get("ai")) {
                    case None => ()
                    case Some(section) =>
                        let vb = section.get("base")
                        if (vb != None && !vb.getOrThrow().isEmpty()) {
                            base = vb.getOrThrow()
                        }
                        let vk = section.get("key")
                        if (vk != None && !vk.getOrThrow().isEmpty()) {
                            key = vk.getOrThrow()
                        }
                        let vm = section.get("model")
                        if (vm != None && !vm.getOrThrow().isEmpty()) {
                            model = vm.getOrThrow()
                        }
                }
            } catch (e: Exception) {
                ()   // 配置损坏：回退默认/环境变量
            }
        }
    }
    // 环境变量覆盖（最高优先级）
    let eb = getVariable("ZHC_AI_BASE")
    if (eb != None && !eb.getOrThrow().isEmpty()) {
        base = eb.getOrThrow()
    }
    let ek = getVariable("ZHC_AI_KEY")
    if (ek != None && !ek.getOrThrow().isEmpty()) {
        key = ek.getOrThrow()
    }
    let em = getVariable("ZHC_AI_MODEL")
    if (em != None && !em.getOrThrow().isEmpty()) {
        model = em.getOrThrow()
    }
    return AiConfig(base, key, model)
}

/**
 * 单轮 chat 调用：POST {base}/chat/completions，返回 assistant content。
 * 非 2xx / 响应缺 content / 通道缺失均抛 LlmError（含可诊断细节）。
 */
public func llmChat(cfg: AiConfig, messages: ArrayList<ChatMsg>): String {
    if (cfg.model.isEmpty()) {
        throw LlmError("未配置 AI 模型：设置环境变量 ZHC_AI_MODEL，或在 ~/.zhc/ai.toml 的 [ai] 节写 model = \"...\"（如 gpt-4o-mini / qwen2.5 / deepseek-chat）")
    }
    // ① 请求体（jsonQuote 完整转义；temperature 低采样提高 JSON 输出稳定性）
    var msgs = "["
    var first = true
    for (m in messages) {
        if (!first) {
            msgs = "${msgs},"
        }
        first = false
        msgs = "${msgs}{\"role\": ${jsonQuote(m.role)}, \"content\": ${jsonQuote(m.content)}}"
    }
    msgs = "${msgs}]"
    let body = "{\"model\": ${jsonQuote(cfg.model)}, \"messages\": ${msgs}, \"temperature\": 0.2}"
    let url = "${cfg.base}/chat/completions"
    // 临时文件统一登记、用后清理（含密钥头文件与请求体——均含敏感信息，
    // 此前永久残留 /tmp 且进程号可预测）
    let reqFile = aiTempPath("req.json")
    let hdrFile = aiTempPath("hdr.txt")
    let keyFile = aiTempPath("key.txt")
    let pyFile = aiTempPath("post.py")
    try {
        File.writeTo(reqFile, body.toArray())
        // ② 传输（curl → python3 降级）③ 解析（协议：body\n<http_code>）
        let (procCode, outB, errB) = doHttp(reqFile, hdrFile, keyFile, pyFile, url, cfg.key)
        let out = String.fromUtf8(outB)
        var httpCode: Int64 = -1
        var respBody = out
        match (out.lastIndexOf("\n")) {
            case None => ()
            case Some(nl) =>
                respBody = out[0..nl]
                try {
                    httpCode = Int64.parse(out[nl + 1..out.size].trimAscii())
                } catch (e: Exception) {
                    httpCode = -1
                }
        }
        if (procCode != 0 || httpCode < 0) {
            let errText = snippet(String.fromUtf8(errB), 200)
            let msg = if (errText.isEmpty()) { snippet(respBody, 200) } else { errText }
            throw LlmError("AI 请求失败（进程退出码 ${procCode}）：${msg}")
        }
        if (httpCode < 200 || httpCode >= 300) {
            var detail = snippet(respBody, 200)
            match (extractJsonStr(respBody, "message")) {
                case None => ()
                case Some(em) =>
                    if (!em.isEmpty()) {
                        detail = em
                    }
            }
            throw LlmError("AI 请求失败（HTTP ${httpCode}）：${snippet(detail, 200)}")
        }
        match (extractJsonStr(respBody, "content")) {
            case None =>
                throw LlmError("AI 响应缺少 content（HTTP ${httpCode}）：${snippet(respBody, 200)}")
            case Some(content) =>
                if (content.isEmpty()) {
                    throw LlmError("AI 响应缺少 content（HTTP ${httpCode}）：${snippet(respBody, 200)}")
                }
                return content
        }
    } finally {
        // 清理全部临时文件（best-effort：Windows 侧无 unlink，降级清空内容）
        removeFileBestEffort(reqFile)
        removeFileBestEffort(hdrFile)
        removeFileBestEffort(keyFile)
        removeFileBestEffort(pyFile)
    }
}

/** AI 临时文件（/tmp 下进程号前缀；用后由 removeFileBestEffort 清理）。 */
private func aiTempPath(suffix: String): String {
    return "${getTempDirectory()}/zhc-ai-${getProcessId()}-${suffix}"
}

/** 传输通道选择与执行（curl → python3 降级）；通道皆缺抛 LlmError。
 *  密钥经临时文件传递、不进 argv（同机 ps aux 可见性）；文件由调用方 finally 清理。 */
private func doHttp(reqFile: String, hdrFile: String, keyFile: String, pyFile: String,
                    url: String, key: String): (Int64, Array<Byte>, Array<Byte>) {
    if (haveCurl()) {
        // Authorization 固定携带（本地端点如 Ollama/mock 忽略多余头）；-H @file
        // 读取头文件（curl 7.55+），密钥不落在命令行上
        File.writeTo(hdrFile, "Authorization: Bearer ${key}\n".toArray())
        return executeWithOutput("curl", [
            "-sS", "-m", "120", "-w", "\n%{http_code}", "-X", "POST", url,
            "-H", "Content-Type: application/json",
            "-H", "@${hdrFile}",
            "--data-binary", "@${reqFile}"])
    }
    if (havePython3()) {
        return executeWithOutput("python3", pythonPostArgv(reqFile, keyFile, pyFile, url, key))
    }
    throw LlmError("AI 请求不可用：未找到 curl 与 python3（至少其一用于 HTTP 调用）")
}

/**
 * python3 降级通道 argv：urllib.request 脚本（写临时文件执行，避免 -c 内嵌
 * 转义）。脚本仅用单引号字面量，与仓颉字符串无转义冲突；输出协议与
 * curl -w 一致：<body>\n<http_code>；网络异常打印 <原因>\n-1。
 * 密钥经 keyFile 传递（脚本读后立即删除），不进 argv。
 */
private func pythonPostArgv(reqFile: String, keyFile: String, pyFile: String,
                            url: String, key: String): Array<String> {
    let py = "import sys, os, urllib.request, urllib.error\n" +
        "p, u, kf = sys.argv[1], sys.argv[2], sys.argv[3]\n" +
        "k = ''\n" +
        "try:\n" +
        "    k = open(kf).read().strip()\n" +
        "    os.remove(kf)\n" +
        "except Exception:\n" +
        "    pass\n" +
        "req = urllib.request.Request(u, data=open(p, 'rb').read(), method='POST')\n" +
        "req.add_header('Content-Type', 'application/json')\n" +
        "if k:\n" +
        "    req.add_header('Authorization', 'Bearer ' + k)\n" +
        "try:\n" +
        "    r = urllib.request.urlopen(req, timeout=120)\n" +
        "    sys.stdout.write(r.read().decode('utf-8', 'replace'))\n" +
        "    sys.stdout.write('\\n')\n" +
        "    sys.stdout.write(str(r.status))\n" +
        "except urllib.error.HTTPError as e:\n" +
        "    sys.stdout.write(e.read().decode('utf-8', 'replace'))\n" +
        "    sys.stdout.write('\\n')\n" +
        "    sys.stdout.write(str(e.code))\n" +
        "except Exception as e:\n" +
        "    sys.stdout.write(str(e))\n" +
        "    sys.stdout.write('\\n-1')\n"
    File.writeTo(pyFile, py.toArray())
    File.writeTo(keyFile, key.toArray())
    return [pyFile, reqFile, url, keyFile]
}

/**
 * 解析 LLM 返回的 JSON 对象（容错：剥 ```json 围栏与前后说明文字——
 * 取首个 `{` 到末个 `}` 之间的文本再解析）；值只收字符串。失败返回空表。
 */
public func parseJsonObj(text: String): HashMap<String, String> {
    let out = HashMap<String, String>()
    var lo: Int64 = -1
    var hi: Int64 = -1
    var i: Int64 = 0
    let n = text.size
    while (i < n) {
        let b = text[i]
        if (b == 0x7B && lo < 0) {   // '{'
            lo = i
        }
        if (b == 0x7D) {   // '}'
            hi = i
        }
        i += 1
    }
    if (lo < 0 || hi < 0 || hi <= lo) {
        return out
    }
    match (parseJsonValue(text[lo..hi + 1])) {
        case None => ()
        case Some(root) =>
            if (root.kind == 0) {
                for (k in root.obj.keys()) {
                    let v = root.obj.get(k).getOrThrow()
                    if (v.kind == 1) {
                        out.add(k, v.str)
                    }
                }
            }
    }
    return out
}

/** 摘要：换行压平 + 超长截断（Rune 安全，中文不切坏）。public：translate 等共用。 */
public func snippet(s: String, max: Int64): String {
    var t = s.replace("\n", " ").replace("\r", " ").replace("\t", " ")
    let rs = t.toRuneArray()
    if (rs.size <= max) {
        return t
    }
    var out = ""
    var k: Int64 = 0
    while (k < max) {
        out = "${out}${rs[k]}"
        k += 1
    }
    return "${out}…"
}
