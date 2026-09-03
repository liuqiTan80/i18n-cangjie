# zhc —— 仓颉母语编程框架

面向母语教学的仓颉（Cangjie）方言编程框架：把标准仓颉代码转译为**任意国家母语**
方言（如中文 `.zc`、俄语 `.rc`），并反向把编译器的英文诊断翻译为**母语教学信息**
（错误码 → 消息表 → 类型本地化 → 修复示例），让初学者零语言门槛上手系统编程。
方言语言由 `ZHCLANG` 环境变量切换（默认 zh），转译/反向转译/诊断翻译/类型
本地化全部由所选语言包驱动——提供 `lang-packs/<代码>/` 即可支持新母语。

```
主函数() {
    让 名字: 字符串 = "仓颉"
    如果 (名字.长度 > 1) {
        打印行("你好，${名字}！")
    }
}
```

## 特性

- **转译代理**：方言 `.zc` → 词法转译 → 标准 `.cj`，增量缓存（源码 + 语言包指纹）＋产物缓存
  （源码与 SDK 版本未变自动跳过 cjc 编译，实测热重跑 ~290ms → ~150ms）；
- **教学诊断**：cjc 官方 DiagKind 全集 644 条 + 方言码共 **645 条诊断码全部母语化**（13 条精翻 + 631 条自动 + 消息兜底表），主消息/detail/note/教学提示全中文，💡 教学提示 + 可粘贴修复示例，位置映射回方言源码；
- **双向语言包**：`zh`/`en`/`ru`（演示）语言包（关键字/别名/模块路径/标准库/错误表），`mapping check`
  五项质量门禁 + 跨语言一致性检查，`mapping auto` 从三方库提取映射，`scaffold` 生成语言包骨架；
- **完整工具链**：`init`（含 `--native` cjpm 构建钩子）/`run`/`check`/`lint`（方言风格
  检查 + `--fix` 自动修复 + `--style` 排版门禁）/`eject`/`add`/`lang`/`test`/`expand`
  （宏展开教学视图）/`lsp`（官方 LSPServer 代理）/`mapping`/`translate`/`ai` 共 14 个子命令，项目/工作区自动探测；
- **AI 辅助（可接入任意模型）**：`zhc translate` 用 AI 把第三方库公开 API 自动翻译成当前方言映射
  （含本地质量门禁：撞关键字/宏/重复自动重试；`--share` 可选导出共享目录给他人安装）；
  `zhc ai` 按自然语言需求生成方言代码并自动编译验证迭代（失败回喂母语诊断修复）。
  后端 OpenAI 兼容 API / Ollama 皆可，无模型也不影响其他命令；
- **生态配套**：VS Code 扩展（高亮/全角转换/右键运行/LSP 诊断）、错误信息字典、
  离线发布包（无网络教学环境解压即用）与一键安装脚本（教程 md 源随包分发，
  GitCode 在线直接阅读）。

## 新手上手指南

本指南面向**第一次接触 zhc 的人**：从安装编译器到跑通第一个方言程序，全程约
10 分钟（不含 SDK 下载时间）。Linux 与 Windows 分别给出详细步骤；zhc 本体是
编译好的原生程序，Windows 用户同样无障碍。

### ① 准备什么（前置条件）

| 项目 | 要求 | 说明 |
|---|---|---|
| 操作系统 | **Linux x86_64** 或 **Windows 10+ x86_64** | zhc 本体双平台原生支持 |
| 仓颉 SDK | **1.0.5**（含 `cjc`、`cjpm`） | 唯一外部依赖，见 ②；版本锁定于 `zhc/cjpm.toml` |
| 终端 | 系统自带即可 | Windows 建议用 Windows Terminal；跑验收脚本需 bash（Git Bash / WSL） |
| 网络 | 仅下载 SDK 时需要 | zhc 无第三方依赖，SDK 装好后全程离线可用 |
| 不需要 | python3 / gcc / node 等 | zhc 本体与教程示例均零依赖（仅 ⑤ 打包 VS Code 扩展时需要 Node.js） |

> 若你使用**离线发布包**（`zhc/dist/zhc-<版本>-*.tar.gz`，解压即用，内含语言包
> 与教程 md），则跳过 ②③，直接按包内说明运行。

### ② 安装仓颉 SDK（唯一外部依赖）

从仓颉官网下载中心（cangjie-lang.cn/download）下载 **1.0.5**：Linux x86_64 为
tar.gz 包；**Windows x86_64 提供 zip 压缩包与 exe 安装程序两种格式**（任选其一，
对应步骤见下）。zhc 的 `zhc/cjpm.toml` 锁定 `cjc-version = "1.0.5"`，请使用同版本
SDK。

**Linux（方式 A，推荐）：解压后 source SDK 自带的 envsetup.sh**，它会一次性配好
CANGJIE_HOME、PATH、LD_LIBRARY_PATH 三项：

```bash
cd ~/下载
tar xzf cangjie-1.0.5-linux-x86_64.tar.gz   # 包名以实际下载为准
SDK=<解压出的 SDK 根目录>                    # 含 bin/、runtime/、tools/ 的目录
source $SDK/envsetup.sh                      # 官方脚本，自动配置全部环境变量
```

**Linux（方式 B，手工）：原理同上，适合写入 `~/.bashrc` 一劳永逸**

```bash
export CANGJIE_HOME=<SDK 根目录>
export PATH=$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$PATH
export LD_LIBRARY_PATH=$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH
```

验证（新开终端）：

```bash
cjc --version    # 应输出 Cangjie Compiler: 1.0.5 (cjnative)
cjpm --version   # 构建 zhc 需要 cjpm（位于 tools/bin）
```

**Windows 详细步骤**（下载中心提供两种格式，按你下载到的任选一种安装）

**形态 A：zip 压缩包**（如 `cangjie-sdk-windows-x64-1.0.5.zip`）

1. 解压到不含空格与中文的路径，如 `C:\cangjie`；
2. 让环境变量生效，三选一：
   - **当前窗口临时生效**：执行 SDK 自带的官方脚本 `C:\cangjie\envsetup.bat`
     （PowerShell 用 `. C:\cangjie\envsetup.ps1`；Git Bash 用
     `source /c/cangjie/envsetup.sh`）——像 Linux 的 envsetup.sh 一样一次配好，
     但只对当前窗口有效，新开窗口需重新执行；
   - **永久生效 · 图形界面**：`系统属性 → 高级系统设置 → 环境变量`，新建系统变量
     `CANGJIE_HOME = C:\cangjie`；再编辑 `Path`，把 `cjc.exe` 与 `cjpm.exe`
     所在目录加入（通常为 `%CANGJIE_HOME%\bin` 与 `%CANGJIE_HOME%\tools\bin`，
     以实际解压结构为准）；
   - **永久生效 · 命令行**：`setx CANGJIE_HOME "C:\cangjie"`，再对每个 bin 目录
     执行一次 `setx Path "%Path%;<目录>"`（setx 只影响之后新开的窗口）。

**形态 B：exe 安装程序**（如 `Cangjie-1.0.5-windows_x64.exe`）

1. 双击运行，跟随安装向导完成安装（建议自定义安装到不含空格与中文的路径，如
   `C:\cangjie`，并**记下安装路径**——若向导询问「添加环境变量 / 加入 PATH」类
   选项，勾选即可，后续步骤可跳过）；
2. 装完后若 `cjc` 仍不是可用命令（向导没自动配置或你没勾选），回到形态 A 第 2
   步手动补环境变量，把其中的 `C:\cangjie` 换成你的实际安装路径；若 `cjc` 可用但
   `cjpm` 找不到，是自动配置只加了 `bin`——补上 `tools\bin` 所在目录即可。

**安装后验证**（两种形态相同）：**重新打开终端**（环境变量只对之后新开的窗口生效）：

   ```
   cjc --version
   ```

   应输出 `Cangjie Compiler: 1.0.5`。若提示「不是内部或外部命令」，说明 PATH
   未生效——回到对应形态补环境变量；若输出中文乱码，先执行 `chcp 65001` 切到 UTF-8。

### ③ 构建 zhc（编译前端本体）

拿到源码（`git clone` 仓库或下载源码压缩包）后，在 `zhc/` 子目录执行——Linux 与
Windows 命令完全相同（Windows 产物带 `.exe` 后缀）：

```bash
cd zwCangjie/zhc
cjpm build
# 产物：target/release/bin/main     （Windows：target\release\bin\main.exe）
```

- 前提只有一条：② 中 `cjc`/`cjpm` 已验证可用；
- 无需网络：zhc 无第三方依赖，纯官方 SDK 即可构建；
- 首次 `cjpm build` 稍慢属正常（SDK 需建立缓存），之后增量构建很快。

（可选）把产物做成全局 `zhc` 命令，后续示例更简短：

- Linux：`ln -s "$PWD/target/release/bin/main" ~/.local/bin/zhc`（需 `~/.local/bin` 在 PATH）；
- Windows：将 `main.exe` 复制到任意目录，把该目录加入 `Path`，即可直接敲 `zhc`。

### ④ 验证：跑通第一个方言程序

```bash
cd zwCangjie/zhc
export ZHC_LANG_PACKS=$PWD        # Windows(cmd)：set ZHC_LANG_PACKS=%CD%
zhc run examples/hello.zc         # 未做③可选步则用：target/release/bin/main run examples/hello.zc
```

预期输出（首次运行）：

```
✅ 编译成功：替换方言标识符 8 处。
func main let var —— 这是字符串内容
消息：你好，仓颉！
```

第二次运行会显示「✅ 编译成功（缓存命中）：源码与语言包未变，已跳过 cjc 编译。」
并明显更快。

`ZHC_LANG_PACKS` 指向**语言包根目录**（内含 `lang-packs/zh`、`lang-packs/en`…）。
zhc 按「环境变量 → 当前目录 `./lang-packs` → 可执行文件旁 → `~/.zhc/lang-packs`」
的顺序自动定位；本仓库即 `zwCangjie/zhc/lang-packs`，建议把上面的 export 写进
shell 配置。换方言只需设 `ZHCLANG`（语言无关）：

```bash
ZHCLANG=en zhc run examples/en-hello.en    # 英语方言（恒等映射）
ZHCLANG=ru zhc run examples/ru-hello.rc    # 俄语方言（演示语言包）
```

### ⑤ 编写代码：安装 VS Code 扩展（推荐）

zhc 是命令行工具；写方言代码推荐配官方 VS Code 扩展，获得一站式体验（`.zc` 语法
高亮 / 右键运行与检查 / LSP 诊断 / 全角标点自动转半角）。扩展未上 VS Code 市场，
且 `.vsix` 是构建产物（不入源码库，clone 后需先本地打包，见下方分平台步骤）。

**Linux / macOS（bash）**，在仓库根执行：

```bash
# ① 打包（需 Node.js；npx 自动按需下载打包器 vsce，仅首次联网）
bash tools/vscode-extension/build-vsix.sh
# 产物：tools/vscode-extension/zhc-dialect-0.1.1.vsix（版本以 package.json 为准）

# ② 安装
code --install-extension tools/vscode-extension/zhc-dialect-0.1.1.vsix
```

**Windows（cmd 或 PowerShell，已装 Node.js 即可，无需 Git Bash）**：

```powershell
# ① 打包（首次联网自动拉取 vsce）
cd tools\vscode-extension
npx --yes @vscode/vsce@2 package --baseContentUrl https://gitcode.com/tan80/zwCangjie/blob/master --baseImagesUrl https://gitcode.com/tan80/zwCangjie/raw/master
# 产物：tools\vscode-extension\zhc-dialect-0.1.1.vsix（版本自动取自 package.json）

# ② 安装（先回到仓库根）
cd ..\..
code --install-extension tools\vscode-extension\zhc-dialect-0.1.1.vsix
```

> 没有 `code` 命令时（VS Code 未加入 PATH）：打开 VS Code，`Ctrl+Shift+X` 打开
> 扩展面板 → 右上角 `…` → 「从 VSIX 安装…」→ 选中上面打包出的 `.vsix` 文件。

装完打开任意 `.zc` 文件即自动激活：彩色语法高亮；编辑器右键菜单可直接
「运行 / 检查方言文件」，无需敲命令；输入全角 `（），；：` 自动转半角
（字符串与注释内保留）。

若右键运行提示找不到 zhc：设置里搜索 `zhc.binPath`，填入 zhc 可执行文件完整路径
（默认按 `ZHC_BIN` → PATH → `~/.zhc` 顺序探测）。扩展构建来源与重新打包见
[tools/vscode-extension/README.md](tools/vscode-extension/README.md)。

> **免打包途径**：离线发布包（`zhc/dist/zhc-<版本>-*.tar.gz`）内已附带打包好的
> `.vsix`，解压即装，无需 Node.js。不装扩展也完全可用：任意文本编辑器写好 `.zc`
> 源码（示例写法见下方「文档」的教程第一卷），命令行 `zhc run` 运行即可。

### ⑥（可选）一键全量验收

在仓库根执行 `bash scripts/acceptance.sh`：构建、语言包质量门禁、示例、教程 150+
代码块全量实测、排版门禁、单元测试、离线包打包等——首次约需几分钟，适合确认
环境完备；只想快速验证可用 `ZHC_SKIP_TUTORIAL=1` 跳过教程环节。Windows 上请用
**Git Bash 或 WSL** 执行（脚本为 bash 编写），zhc 本体不受影响。

### ⑦ 常见问题排查

| 症状 | 原因 | 修复 |
|---|---|---|
| `cjc: command not found` | PATH 未配置或新终端未生效 | 重新 `source $SDK/envsetup.sh`，或新开终端（Windows：setx 后必须新开窗口） |
| `cjpm: command not found` | 只配了 bin，漏了 tools/bin | 把 `cjpm`/`cjpm.exe` 所在目录加入 PATH |
| 运行 zhc 报找不到共享库 `libcangjie*` | 缺 LD_LIBRARY_PATH（仅 Linux） | export `LD_LIBRARY_PATH` 含 `<SDK>/runtime/lib/linux_x86_64_cjnative` 与 `<SDK>/tools/lib` |
| 报「未找到语言包 `zh`」 | 语言包根目录不对 | `ZHC_LANG_PACKS` 指向含 `lang-packs/` 的目录（zhc/ 或仓库根） |
| Windows 终端中文乱码 | 控制台代码页非 UTF-8 | `chcp 65001` 后重开 zhc |
| `zhc lint` 报「cjlint 执行失败（退出码 255）」 | 环境缺 `CANGJIE_HOME`（cjlint 依赖它定位 SDK） | `export CANGJIE_HOME=<SDK 根目录>`（见 ②） |
| Windows 上 `zhc ai` 报「无法自动定位 zhc 可执行文件」 | `/proc/self/exe` 是 Linux 特性 | 设置 `ZHC_SELF_EXE` 为 zhc 可执行文件完整路径 |
| 构建 zhc 报 cjc 版本不匹配 | SDK 版本不是 1.0.5 | `zhc/cjpm.toml` 锁定 `cjc-version = "1.0.5"`，安装对应 SDK |
| Windows 杀毒软件拦截产物 | 新编译程序常被误报 | 将构建目录加入信任/排除后重新构建 |

想继续学语言本身？→ 见下方「文档」的《中文仓颉程序设计》（新手从第一卷开始）。
各子命令的完整说明见「子命令一览」。

## AI 辅助（可选接入，zhc translate / zhc ai）

两个 AI 子命令共用一套配置（OpenAI 兼容协议，Ollama 亦兼容），**不配置也不影响其他命令**：

```bash
# 方式一：环境变量（优先级最高）
export ZHC_AI_BASE="https://api.openai.com/v1"   # 或 Ollama: http://127.0.0.1:11434/v1
export ZHC_AI_KEY="sk-..."                        # 本地端点可留空
export ZHC_AI_MODEL="gpt-4o-mini"                 # 或 qwen2.5 / deepseek-chat / llama3 等

# 方式二：~/.zhc/ai.toml（[ai] 节；密钥建议 chmod 600）
# [ai]
# base = "https://api.openai.com/v1"
# key = "sk-..."
# model = "gpt-4o-mini"
```

```bash
# ① 自动翻译第三方库 → 当前方言 crates/ 映射（含冲突门禁自动重试）
zhc translate <库目录>                 # 仅写入本机语言包（不共享）
zhc translate <库目录> --share 导出名   # 额外导出 zhc-共享-<导出名>/ 给他人

# ② 按需求自动写方言代码（生成 → 编译验证 → 失败回喂诊断修复，默认最多 3 轮）
zhc ai "打印 1 到 100 的质数" -o 质数.zc --iter 3
zhc run 质数.zc
```

## 子命令一览

| 命令 | 说明 |
|---|---|
| `zhc init [--native] <项目名>` | 生成方言项目骨架（cjc-version 动态探测；`--native` 加 cjpm 构建钩子） |
| `zhc run <文件.zc\|目录>` | 转译 → 编译 → 运行（项目/工作区自动探测） |
| `zhc check <文件.zc\|目录>` | 转译 → 编译检查（不运行） |
| `zhc lint <文件.zc> [--fix/--style]` | 方言风格检查（全角/尾随空白/CRLF/空行/行长）+ cjlint 集成；`--style` 仅排版门禁（不转译） |
| `zhc eject <文件.zc>` | 导出标准 `.cj` 源码 + 反向映射碰撞报告 |
| `zhc add <库> [--git/--path]` | 添加依赖（编辑 cjpm.toml） |
| `zhc lang list\|install\|remove` | 语言包管理 |
| `zhc mapping check\|scaffold\|auto` | 映射质量门禁 / 骨架 / 三方库提取 |
| `zhc expand <文件.zc> [--macro-pkg]` | 宏展开教学视图（展开前/后对照，反向母语） |
| `zhc test` | 方言测试（转译 → cjpm test → 母语输出） |
| `zhc native` | cjpm 构建钩子内部命令（`init --native` 生成） |
| `zhc lsp` | LSP 代理（语言能力转发官方 LSPServer，诊断自跑 cjc） |
| `zhc translate <库目录> [--share [导出名]]` | AI 翻译第三方库公开 API → crates/ 映射（冲突门禁重试；`--share` 导出共享目录） |
| `zhc ai "<需求>" [-o 文件] [--iter N]` | 按需求生成方言代码，自动编译验证迭代（默认 3 轮） |

## 目录结构

```
├── CONTRIBUTING.md          # 贡献指南（开发/测试/文档/发布流程，见 docs/语言包开发.md）
├── .github/                 # CI 流水线 + issue/PR 模板（bug/feature/PR 三件套）
├── zhc/                     # 主项目（仓颉实现，约 20 个模块）
│   ├── src/                 # 词法转译/别名/诊断翻译/语言包/LSP/工作区…
│   ├── lang-packs/          # zh + en + ru（演示）语言包（关键字/别名/模块路径/stdlib/错误表）
│   └── examples/            # 方言示例（hello/stdlib/综合示例/宏演示/projects 成品）
├── docs/
│   ├── 中文仓颉程序设计/    # 项目唯一教程《中文仓颉程序设计》：三卷 20 章 + 附录 A/B/C + 答案（150+ 代码块全部实测）
│   ├── 特性覆盖矩阵.md      # 官方特性 ↔ 教程覆盖矩阵（含第 20 章候选清单）
│   ├── 术语表.md            # 官方英文术语 ↔ 中文教学说法（教程统一用词）
│   ├── 语言包开发.md        # 语言包贡献指南（完整度矩阵/生成链/质量门禁/诊断码触发率）
│   └── errors-dictionary.md # 错误信息字典（由 tools/gen_error_dict.py 生成）
├── scripts/
│   ├── acceptance.sh        # 一键全量验收（本地与 CI 共用，断言数动态汇总）
│   ├── setup-cangjie.sh     # 仓颉 SDK 定位/下载（本地与 CI 共用，sha256 可选）
│   ├── tutorial-check.sh    # 教程代码全量验证（抽取→实测→组合→排版门禁→快照回归）
│   ├── install.sh           # 一键安装（发布包 sha256 校验 + 软链，本地/远程 URL）
│   ├── lsp-smoke.py         # LSP 端到端冒烟（stdio 行帧协议：initialize→诊断→退出）
│   ├── sdk-smoke.sh         # SDK 冒烟 5 项（构建/映射/示例/诊断），CI sdk-canary 用
│   └── release.sh           # 离线发布包（bin/zhc 启动器 + 运行时库 + 语言包 + docs/tools）
├── tools/                   # VS Code 扩展 + 高亮/字典/诊断覆盖/教学用例库脚本
├── .verify/                 # 教程验证快照基线（snapshots.sha256）与中间产物（不入库）
├── .github/workflows/ci.yml # Linux 全量验收 + Windows 构建自检 + sdk-canary 手动哨兵

```

## 文档

项目只有一本教程：[《中文仓颉程序设计》](docs/中文仓颉程序设计/README.md)——三卷 20 章
手册级 + 附录 A/B/C 速查 + 思考题答案（150+ 代码块全部实测），面向任何阶段的人：
零基础从第一卷开始，想系统掌握语法翻第二卷与附录，想写出高质量代码读第三卷；
配套资产：[术语表](docs/术语表.md)（官方术语 ↔ 中文说法，教程统一用词）·
[错误信息字典](docs/errors-dictionary.md)（645 条错误码按官方码反查）·
[特性覆盖矩阵](docs/特性覆盖矩阵.md)（官方特性 ↔ 教程覆盖盘点 + 第 20 章候选清单）·

## CI 与发布

- CI：仓库根 `.github/workflows/ci.yml`（GitHub Actions 兼容语法，Linux 全量验收 +
  Windows 构建自检 best-effort）。SDK 安装统一走 `scripts/setup-cangjie.sh`（复用
  `CANGJIE_HOME` → 已装目录 → 下载 `CANGJIE_SDK_URL` + 可选 sha256 校验），URL 在
  仓库 Secrets 配置；仓库托管于 **GitCode**（gitcode.com/tan80/zwCangjie，唯一 remote）——平台若提供
  兼容流水线可直接启用，否则自托管/本地 runner 运行；本地验收不受影响：
  `bash scripts/acceptance.sh`（含教程 150+ 代码块全量验证、排版门禁、转译快照回归
  与生成物防漂移检查，可用 `ZHC_SKIP_TUTORIAL=1` 跳过教程环节加速）。
  另提供 **sdk-canary** 手动哨兵（workflow_dispatch）：传入新 SDK 安装 URL 即跑
  `scripts/sdk-smoke.sh` 5 项冒烟，作为 SDK 升级前哨。
- 发布：`scripts/release.sh [版本] [系统] [架构]` 产出
  `zhc/dist/zhc-<版本>-<系统>-<架构>.tar.gz`（解压即用，无需 SDK 与环境变量，
  内含教程 md 与错误字典）；一键安装：
  `bash scripts/install.sh --url <下载地址> [--sha256 <校验和>]`（装到
  `~/.zhc/zhc-<版本>` 并软链 `~/.zhc/bin/zhc`，卸载说明见脚本头）；
  tag 约定 `zhc-<版本>`（GitCode Releases 直链 = 默认安装 URL）。
- 发布状态（**v0.1.1，2026-09**）：`zhc/dist/zhc-0.1.1-linux-x86_64.tar.gz` 已构建
  （sha256 `f5beb87e…f00d`，以 release.sh 输出为准；教程为 md 源随包分发），
  `install.sh --url/--sha256` 安装闭环已本地实测（HTTP 服务器模拟 Release 直链：
  下载 → 解压 → 软链 → 自检 → 方言程序运行）；
  **GitCode 待办（需网页操作）**：打 Release `zhc-0.1.1` 并上传该 tar.gz（附 sha256），
  之后默认命令 `bash scripts/install.sh` 即从 GitCode 直链安装。

## 许可证

[MIT](LICENSE)
