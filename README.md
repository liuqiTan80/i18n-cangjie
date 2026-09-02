# zhc —— 仓颉母语编程框架

面向母语教学的仓颉（Cangjie）方言编程框架：把标准仓颉代码转译为**任意国家母语**
方言（如中文 `.zc`、俄语 `.rc`），并反向把编译器的英文诊断翻译为**母语教学信息**
（错误码 → 消息表 → 类型本地化 → 修复示例），让初学者零语言门槛上手系统编程。
方言语言由 `ZHCLANG` 环境变量切换（默认 zh），转译/反向转译/诊断翻译/类型
本地化全部由所选语言包驱动——提供 `lang-packs/<代码>/` 即可支持新母语。

```
主函数() {
    让 名字: 字符串 = "仓颉"
    如果 (名字.size > 1) {
        打印行("你好，${名字}！")
    }
}
```

## 特性

- **转译代理**：方言 `.zc` → 词法转译 → 标准 `.cj`，增量缓存（源码 + 语言包指纹）；
- **教学诊断**：cjc 官方 DiagKind 全集 644 条 + 方言码共 **645 条诊断码全部母语化**（13 条精翻 + 631 条自动 + 消息兜底表），主消息/detail/note/教学提示全中文，💡 教学提示 + 可粘贴修复示例，位置映射回方言源码；
- **双向语言包**：`zh`/`en`/`ru`（演示）语言包（关键字/别名/模块路径/标准库/错误表），`mapping check`
  五项质量门禁 + 跨语言一致性检查，`mapping auto` 从三方库提取映射，`scaffold` 生成语言包骨架；
- **完整工具链**：`init`（含 `--native` cjpm 构建钩子）/`run`/`check`/`lint`（方言风格
  检查 + `--fix` 自动修复 + `--style` 排版门禁）/`eject`/`add`/`lang`/`test`/`expand`
  （宏展开教学视图）/`lsp`（官方 LSPServer 代理）/`mapping` 共 12 个子命令，项目/工作区自动探测；
- **生态配套**：VS Code 扩展（高亮/全角转换/右键运行/LSP 诊断）、错误信息字典、
  离线发布包（无网络教学环境解压即用）与一键安装脚本（教程 md 源随包分发，
  GitCode 在线直接阅读）。

## 快速开始

前提：仓颉 SDK 1.0.5（`cjc`/`cjpm` 可用），Linux x86_64。

```bash
# 构建
cd zhc && cjpm build

# 运行方言示例（转译 → 编译 → 运行）
ZHC_LANG_PACKS=$PWD target/release/bin/main run examples/hello.zc

# 一键全量验收（构建/映射/示例/教程/lint/test/单元测试/诊断/离线包，断言数动态汇总）
cd .. && bash scripts/acceptance.sh
```

本地开发时建议 `export ZHC_LANG_PACKS=$PWD`（语言包定位链：环境变量 → 当前目录
`./lang-packs` → 可执行文件旁 → `~/.zhc/lang-packs`）。

支持任意母语（语言无关，2026-09 起）：

```bash
# 中文方言（默认，无需设置）
ZHCLANG=zh target/release/bin/main run examples/hello.zc

# 俄语方言（ru 演示语言包 + 俄语示例，.rc 扩展名来自语言包声明）
ZHCLANG=ru target/release/bin/main run examples/ru-hello.rc

# 英语方言（en 包为恒等映射：英语方言 = 官方仓颉）
ZHCLANG=en target/release/bin/main run examples/en-hello.en
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

## 目录结构

```
├── CONTRIBUTING.md          # 贡献指南（开发/测试/文档/发布流程，见 docs/语言包开发.md）
├── .github/                 # CI 流水线 + issue/PR 模板（bug/feature/PR 三件套）
├── zhc/                     # 主项目（仓颉实现，约 20 个模块）
│   ├── src/                 # 词法转译/别名/诊断翻译/语言包/LSP/工作区…
│   ├── lang-packs/          # zh + en + ru（演示）语言包（关键字/别名/模块路径/stdlib/错误表）
│   └── examples/            # 方言示例（hello/stdlib/教程综合/宏演示/projects 成品）
├── docs/
│   ├── tutorial/            # 11 章字典级教程（含设计思想与软工知识）
│   ├── 中文仓颉程序设计/    # 《中文仓颉程序设计》：三卷 20 章 + 附录 A/B/C + 答案（150+ 代码块全部实测）
│   ├── 特性覆盖矩阵.md      # 官方特性 ↔ 教程覆盖矩阵（含第 20 章候选清单）
│   ├── cangjie-book.md      # 初中生入门书（12 章，零基础最短路径）
│   ├── 术语表.md            # 官方英文术语 ↔ 中文教学说法（三教程统一用词）
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
└── zhc-design.md            # 落地设计文档（含 §13.1 实测记录）
```

## 文档

三本教程内容互补（语法重叠，角度不同）：

| 教程 | 读者 | 特点 | 从哪开始 |
|---|---|---|---|
| [入门书](docs/cangjie-book.md) | 完全零基础（含中小学生） | 12 章最短路径，10 分钟/章，故事化 | 想先体验「编程是怎么回事」 |
| [《中文仓颉程序设计》](docs/中文仓颉程序设计/README.md) | 想系统学到底的人 | 三卷 20 章手册级 + 附录 A/B/C 速查 + 思考题答案 | 想认真学一门语言、并当案头手册查 |
| [教学教程](docs/tutorial/README.md) | 想边学边掌握 zhc 工具链的人 | 11 章字典级 + 每章官方对照 + 诊断/宏展开/语言包玩法 | 想深入 zhc 生态或对照官方文档 |

配套资产：[术语表](docs/术语表.md)（官方术语 ↔ 中文说法，三教程统一用词）·
[错误信息字典](docs/errors-dictionary.md)（645 条错误码按官方码反查）·
[特性覆盖矩阵](docs/特性覆盖矩阵.md)（官方特性 ↔ 教程覆盖盘点 + 第 20 章候选清单）·
[设计文档](zhc-design.md)（架构/语言包规范/风险与实测记录）。

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
- 发布状态（**v0.1.0，2026-09**）：`zhc/dist/zhc-0.1.0-linux-x86_64.tar.gz` 已构建
  （sha256 `e6c0c148…a86f`，release.sh 输出为准），`install.sh --url/--sha256` 安装闭环
  已本地实测（HTTP 服务器模拟 Release 直链：下载 → 解压 → 软链 → 自检 → 方言程序运行）；
  **GitCode 待办（需网页操作）**：打 Release `zhc-0.1.0` 并上传该 tar.gz（附 sha256），
  之后默认命令 `bash scripts/install.sh` 即从 GitCode 直链安装。

## 许可证

[MIT](LICENSE)
