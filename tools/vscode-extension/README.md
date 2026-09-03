# zhc 仓颉方言 — VS Code 扩展

仓颉方言编程框架（zhc）的 VS Code 配套扩展：`.zc` 方言文件的一站式编辑体验。

## 功能

| 能力 | 说明 |
|---|---|
| **语法高亮** | `.zc` 方言文件按语言包着色（关键字/类型/函数/宏分节），语法文件由 [tools/gen_highlight.py](../gen_highlight.py) 从语言包自动生成，与映射永不漂移 |
| **右键运行/检查** | 编辑器右键 → 「zhc：运行方言文件 / 检查方言文件」，终端执行 `zhc run` / `zhc check`（Windows PowerShell 自动加 `& ` 调用操作符） |
| **LSP 诊断** | 行帧协议驱动 `zhc lsp` 代理：官方 LSPServer 可用时转发语言能力，诊断由 zhc 自跑 cjc 翻译后推送（教学提示 + 方言坐标对齐）；官方 LSP 不可用时 zhc 自动降级为仅诊断档，扩展无需感知 |
| **词表联想补全** | 中文词（或官方名）即打即联想：敲「打」→ 打印/打印行…；词条与语言包同源（tools/gen_words.py 生成 zhc-words.json，273 词条不漂移）。**函数类选中自动带括号且光标居中**（`打印行()`），**类型/关键字/字面量/模块路径**分类显示；敲 `@` 弹出宏词条（`@派生`/`@测试`/`@期望`），中文输入法上屏同样触发（VS Code 对上屏文本不自动弹补全，扩展手动拉起） |
| **悬停释义** | 鼠标停在中文词上显示对应官方名与词条类别（函数附「补全自动带括号」提示）；输入法无需切换即可对照官方教程 |
| **全角标点自动转换** | 输入时把全角 `（），；：`、中文引号 `“”‘’`（含直引号全角形态）、全角空格自动转半角；**字符串字面量与注释内保留原文**（含未闭合字符串行尾继续输入）；兼容输入法「智能成对」一次上屏 `（）` 与双段提交（Linux IME），不产生重复字符；也可用命令整篇转换 |
| **依赖添加** | 命令面板「zhc：添加依赖」→ 输入库名 → `zhc add` |

## 安装

1. 确保已安装 zhc CLI（`zhc help` 可用；随离线发布包分发，或从 GitCode 仓库 gitcode.com/tan80/zwCangjie 构建；离线包解压后把 `bin/zhc` 放入 PATH 或设置 `ZHC_BIN`）；
2. 获取 `.vsix`，两种途径任选：

   **途径 1（推荐）：从 GitCode Release 附件直接下载**（与离线发布包同页，无需 Node.js）

   ```bash
   curl -LO https://gitcode.com/tan80/zwCangjie/releases/download/zhc-0.2.0/zhc-dialect-0.2.0.vsix
   code --install-extension zhc-dialect-0.2.0.vsix
   ```

   **途径 2：源码本地打包**（clone 仓库后；`.vsix` 为构建产物不入源码库，需 Node.js，`npx` 自动按需下载 vsce）

   **Linux / macOS（bash），仓库根执行**：

   ```bash
   bash tools/vscode-extension/build-vsix.sh   # 产物：tools/vscode-extension/zhc-dialect-0.2.0.vsix
   code --install-extension tools/vscode-extension/zhc-dialect-0.2.0.vsix
   ```

   **Windows（cmd / PowerShell，无需 Git Bash）**：

   ```powershell
   cd tools\vscode-extension
   npx --yes @vscode/vsce@2 package --baseContentUrl https://gitcode.com/tan80/zwCangjie/blob/master --baseImagesUrl https://gitcode.com/tan80/zwCangjie/raw/master
   cd ..\..
   code --install-extension tools\vscode-extension\zhc-dialect-0.2.0.vsix
   ```

   无 `code` 命令时改用 VS Code 内「扩展面板 → … → 从 VSIX 安装…」选中该文件；
   离线发布包内 `tools/` 亦附带打包好的 `.vsix`，解压即装；
3. 打开任意 `.zc` 文件即自动激活。

也可临时使用（无 `code` 命令/命令损坏时的备用安装法，本机实测）：
把解压后的扩展目录放到 VS Code 的扩展目录并重启窗口：

```bash
mkdir -p ~/.vscode/extensions
unzip -q zhc-dialect-0.2.0.vsix -d /tmp/vsix-x
mkdir -p ~/.vscode/extensions/zhc-project.zhc-dialect-0.2.0
cp -r /tmp/vsix-x/extension/. ~/.vscode/extensions/zhc-project.zhc-dialect-0.2.0/
```

然后 VS Code 内 `Ctrl+Shift+P` → `Reload Window`。若输入转换/补全行为异常，
查看「输出」面板下拉列表中的 `zhc 输入` 通道（输入/转换/补全轨迹与异常日志）。

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

# 语法校验 + 纯逻辑单测（lib/ 无 vscode 依赖，acceptance 段 11 调用）
node --check extension.js
node test/fullwidth.test.js    # 全角转换：词法状态机 + 插入点判定（10 项）
node test/words.test.js        # 词表：前缀联想/双向查/分类（6 项）
```
