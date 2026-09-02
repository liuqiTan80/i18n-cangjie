#!/usr/bin/env python3
"""zhc lsp 端到端冒烟测试（建议 A3）——验收段 14 与 CI 共用。

按行帧协议（JSON 单行 + \\n，设计 §13.1）走完整会话：
  initialize → initialized → didOpen（含错误方言源码）→ 断言收到
  publishDiagnostics 且诊断消息为中文教学翻译 → shutdown → exit。

用法：python3 scripts/lsp-smoke.py [zhc 二进制] [工作目录]
环境：ZHC_BIN（默认 zhc）、ZHC_LSP_BIN（可选，指定官方 LSPServer）；
      需要 CANGJIE_HOME 及其 runtime/tools lib（zhc 开发构建与 cjc 子进程必需）。
退出码：0 全部通过；1 任一断言失败；2 环境/进程异常。
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ERROR_SRC = '主函数() {\n    打印行(不存在的标识符)\n}\n'
MUST_HAVE = "未声明"          # 与验收段 3 黄金样例同源的口径
READ_TIMEOUT = 90             # 单帧最长等待（LSPServer 首启 + cjc 编译）
POLL_INTERVAL = 0.1

def fail(msg):
    print(f"❌ {msg}", file=sys.stderr)
    sys.exit(1)

def read_frame(proc, deadline):
    """阻塞读一行 stdout（行帧）；返回 None 表示超时/EOF。
    跨帧剩余字节缓存在 proc 上（read1 可能一次读多帧，不能丢）。"""
    import select
    buf = getattr(proc, "_frame_rest", b"")
    while time.time() < deadline:
        if b"\n" in buf:
            line, _, buf = buf.partition(b"\n")
            proc._frame_rest = buf
            return line.decode("utf-8", "replace").strip()
        r, _, _ = select.select([proc.stdout], [], [], POLL_INTERVAL)
        if r:
            chunk = proc.stdout.read(4096)   # select 已保证可读；EOF 返回 b""
            if not chunk:      # EOF
                if buf:
                    proc._frame_rest = b""
                    return buf.decode("utf-8", "replace").strip()
                return None
            buf += chunk
    return None

def main():
    zhc = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("ZHC_BIN", "zhc")
    work = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.mkdtemp(prefix="zhc-lsp-smoke-"))
    work.mkdir(parents=True, exist_ok=True)
    uri = (work / "err.zc").as_uri()

    print(f"==> LSP 冒烟（zhc={zhc}，uri={uri}）")
    try:
        proc = subprocess.Popen(
            [zhc, "lsp"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            bufsize=0, text=False,
        )
    except FileNotFoundError:
        fail(f"无法启动 zhc：{zhc}")

    def send(obj):
        proc.stdin.write(json.dumps(obj, ensure_ascii=False).encode("utf-8") + b"\n")
        proc.stdin.flush()

    try:
        # ① initialize：应回 id=1 的 result 帧（代理档/仅诊断档都回 capabilities）
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"capabilities": {}}})
        frame = read_frame(proc, time.time() + READ_TIMEOUT)
        if frame is None:
            fail("initialize 无响应（超时/进程退出）")
        resp = json.loads(frame)
        if resp.get("id") != 1 or "result" not in resp:
            fail(f"initialize 响应异常：{frame[:200]}")
        caps = resp.get("result", {}).get("capabilities", {})
        print(f"✅ initialize 响应（capabilities.textDocumentSync={caps.get('textDocumentSync')}）")

        # ② initialized 通知 + didOpen（含错误源码）
        send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        send({"jsonrpc": "2.0", "method": "textDocument/didOpen",
              "params": {"textDocument": {
                  "uri": uri, "languageId": "zhc-dialect", "version": 1,
                  "text": ERROR_SRC}}})

        # ③ 等待 publishDiagnostics（didOpen 后 zhc 自跑 cjc 并推送）
        deadline = time.time() + READ_TIMEOUT
        got = None
        while time.time() < deadline:
            frame = read_frame(proc, deadline)
            if frame is None:
                break
            try:
                msg = json.loads(frame)
            except json.JSONDecodeError:
                continue
            if msg.get("method") == "textDocument/publishDiagnostics":
                got = msg
                break
        if got is None:
            fail("didOpen 后未收到 publishDiagnostics（诊断推送链路异常）")
        params = got.get("params", {})
        if params.get("uri") != uri:
            fail(f"诊断 uri 不匹配：{params.get('uri')}")
        diags = params.get("diagnostics", [])
        if not diags:
            fail("诊断数组为空（错误源码未产出诊断）")
        text = diags[0].get("message", "")
        if MUST_HAVE not in text:
            fail(f"诊断消息非中文教学翻译（缺「{MUST_HAVE}」）：{text[:120]}")
        print(f"✅ publishDiagnostics：{len(diags)} 条，首条消息「{text[:60]}…」")

        # ④ shutdown → exit（干净退出，不留僵尸进程）
        send({"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None})
        frame = read_frame(proc, time.time() + 30)
        if frame is None or json.loads(frame).get("id") != 2:
            fail("shutdown 无响应")
        send({"jsonrpc": "2.0", "method": "exit", "params": None})
        proc.wait(timeout=15)
        print("✅ shutdown/exit 干净退出")
        print("==> ✅ LSP 冒烟通过")
        return 0
    except (subprocess.TimeoutExpired, OSError) as e:
        fail(f"进程交互异常：{e}")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)

if __name__ == "__main__":
    sys.exit(main())
