# zhc 仓颉方言 — VS Code 扩展

仓颉方言编程框架（zhc）的 VS Code 配套扩展：`.zc` 方言文件的一站式编辑体验。

## 功能

| 能力 | 说明 |
|---|---|
| **语法高亮** | `.zc` 方言文件按语言包着色（关键字/类型/函数/宏分节），语法文件由 [tools/gen_highlight.py](../gen_highlight.py) 从语言包自动生成，与映射永不漂移 |
| **右键运行/检查** | 编辑器右键 → 「zhc：运行方言文件 / 检查方言文件」，终端执行 `zhc run` / `zhc check`（Windows PowerShell 自动加 `& ` 调用操作符） |
| **LSP 诊断** | 行帧协议驱动 `zhc lsp` 代理：官方 LSPServer 可用时转发语言能力，诊断由 zhc 自跑 cjc 翻译后推送（教学提示 + 方言坐标对齐）；官方 LSP 不可用时 zhc 自动降级为仅诊断档，扩展无需感知 |
| **全角标点自动转换** | 输入时把全角 `（），；：` 自动转半角；字符串字面量与注释内保留原文（词法状态机）；也可用命令整篇转换 |
| **依赖添加** | 命令面板「zhc：添加依赖」→ 输入库名 → `zhc add` |

## 安装

1. 确保已安装 zhc CLI（`zhc --version` 可用；随离线发布包分发，或从 GitCode 仓库 gitcode.com/tan80/zwCangjie 构建；离线包解压后把 `bin/zhc` 放入 PATH 或设置 `ZHC_BIN`）；
2. 打开本目录，执行 `npm install -g @vscode/vsce && vsce package` 生成 `.vsix`，或直接 `code --install-extension zhc-dialect-0.1.0.vsix`；
3. 打开任意 `.zc` 文件即自动激活。

也可临时使用：把本目录复制到 `~/.vscode/extensions/zhc-dialect-0.1.0/` 后重启 VS Code。

## 配置

| 键 | 默认 | 说明 |
|---|---|---|
| `zhc.binPath` | `""` | zhc 可执行文件路径；留空按 `ZHC_BIN` → PATH（Windows 含 PATHEXT 探测）→ `~/.zhc` 顺序解析 |
| `zhc.autoConvertFullwidth` | `true` | 输入时自动转换全角标点（字符串/注释内保留） |

## 与 zhc LSP 代理的协议

编辑器 ↔ zhc 采用**行帧协议**：JSON 单行 + `\n`（zhc 侧 `lsp_proxy.cj` 实现，适配仓颉 runtime 行化读取限制）。诊断经标准 `textDocument/publishDiagnostics` 推送（0-based 坐标、`severity` 1=错误 2=警告、`source: "zhc"`）。

## 开发

```bash
# 重新生成语法高亮（语言包更新后执行）
python3 ../gen_highlight.py

# 语法校验
node --check extension.js
```
