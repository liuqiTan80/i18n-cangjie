#!/usr/bin/env python3
"""zhc AI 验收用 mock LLM（设计 §17.5）——本地 OpenAI 兼容 /v1/chat/completions。

不依赖外网/Ollama 即可驱动 zhc translate / zhc ai 全链路。按请求内容分发：

- translate 标识符场景（user 含「逐条翻译以下」）：首次返回含**故意违规**的
  预设映射（area→函数 撞关键字「函数」；render→形状 与 Shape 译名重复），
  验证 zhc 本地门禁检出 + 携带冲突清单重试；重试请求（system 含「不合规」）
  返回修正版，验证降级闭环（无冲突即全部采纳）；
- translate 模块路径场景（user 含「子模块目录段」）：返回预设段映射
  {"ui": "界面"}；
- zhc ai 场景（user 含「实现以下需求」）：首次返回编译必败代码（字符串赋给
  整数——类型不匹配硬错误，见 AI_BAD 上方踩坑注释），第二次返回正确代码——
  验证「生成 → 编译诊断回喂 → 修复」迭代闭环。

用法：python3 tools/mock_llm.py [端口=8011]
响应计数打印到 stderr（断言用：translate 应恰好 3 次 = 首轮 + 重试 + 模块路径）。

注意：mock 映射与测试库固定绑定（zhc 实测库 API：Shape/Panel/Point/area/render；
子目录 ui）。更换测试库需同步修改本文件预设。
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# translate 首轮：2 条故意违规（area→函数 撞关键字；render→形状 重复）
BAD_IDS = {
    "Shape": "形状",
    "Panel": "面板",
    "area": "函数",
    "render": "形状",
    "Point": "点",
}
# 重试修正版：全部合规
FIX_IDS = {
    "Shape": "形状",
    "Panel": "面板",
    "area": "面积",
    "render": "渲染",
    "Point": "点",
}
# 模块路径段映射
SEG_IDS = {"ui": "界面"}

# ai 场景：首轮类型错误（编译必败），次轮正确。实测踩坑（2026-09-03）：
# ① cjc 单文件下 println/main 隐式可用——缺 import 不报错；
# ② 仓颉 let/var 声明与语句分号可选——漏分号不报错；
# ③ 只有类型不匹配/未声明等硬错误才让 cjc 退出码非 0。
AI_BAD = ('导入 标准核心.{打印行}\n\n主函数() {\n'
          '    让 数字: 整数 = "这不是数字"\n    打印行(数字)\n}\n')
AI_GOOD = ('导入 标准核心.{打印行}\n\n主函数() {\n'
           '    让 数字: 整数 = 42\n    打印行(数字)\n}\n')

counts = {"translate": 0, "ai": 0}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n))
        user = ""
        sysc = ""
        for m in body.get("messages", []):
            if m.get("role") == "system":
                sysc = m.get("content", "")
            elif m.get("role") == "user":
                user = m.get("content", "")
        if "逐条翻译以下" in user:
            counts["translate"] += 1
            out = FIX_IDS if "不合规" in sysc else BAD_IDS
        elif "子模块目录段" in user:
            counts["translate"] += 1
            out = SEG_IDS
        elif "实现以下需求" in user:
            counts["ai"] += 1
            out = AI_GOOD if counts["ai"] > 1 else AI_BAD
        else:
            out = {}
        # dict 场景转成 JSON 文本（zhc parseJsonObj 解析）；纯代码场景（AI_GOOD/
        # AI_BAD）原样返回——若在此 json.dumps 会被外层 payload 再转义一次，
        # 代码里的 \n/\" 双重转义后 zhc 解码回来仍是字面量（实测踩坑）。
        content = json.dumps(out, ensure_ascii=False) if isinstance(out, dict) else out
        payload = {
            "choices": [{"message": {"role": "assistant", "content": content}}]
        }
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        sys.stderr.write("mock_llm: translate=%d ai=%d\n" % (counts["translate"], counts["ai"]))


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8011
    sys.stderr.write("mock_llm listening on 127.0.0.1:%d\n" % port)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
