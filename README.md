# zhc —— 仓颉方言编程框架

面向中文母语教学的仓颉（Cangjie）方言编程框架：把标准仓颉代码转译为中文方言
（`.zc`），并反向把编译器的英文诊断翻译为**中文教学信息**（错误码 → 消息表 →
类型本地化 → 修复示例），让初学者零语言门槛上手系统编程。

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
- **教学诊断**：cjc 官方 DiagKind 全集 644 条 + 方言错误码母语化（13 官方精翻 + 631 自动纯中文 + 方言码），主消息/detail/note/教学提示全中文，💡 教学提示 + 可粘贴修复示例，位置映射回方言源码；
- **双向语言包**：`zh`/`en` 语言包（关键字/别名/模块路径/标准库/错误表），`mapping check`
  五项质量门禁，`mapping auto` 从三方库提取映射，`scaffold` 生成语言包骨架；
- **完整工具链**：`init`（含 `--native` cjpm 构建钩子）/`run`/`check`/`lint`（方言风格
  检查 + `--fix`）/`eject`/`add`/`lang`/`test`/`expand`（宏展开教学视图）/`lsp`（官方
  LSPServer 代理）/`mapping` 共 12 个子命令，项目/工作区自动探测；
- **生态配套**：VS Code 扩展（高亮/全角转换/右键运行/LSP 诊断）、九章递进教程、
  错误信息字典、离线发布包（无网络教学环境解压即用）。

## 快速开始

前提：仓颉 SDK 1.0.5（`cjc`/`cjpm` 可用），Linux x86_64。

```bash
# 构建
cd zhc && cjpm build

# 运行方言示例（转译 → 编译 → 运行）
ZHC_LANG_PACKS=$PWD target/release/bin/main run examples/hello.zc

# 一键全量验收（50 项断言：构建/映射/示例/教程/lint/test/单元测试/诊断/离线包）
cd .. && bash scripts/acceptance.sh
```

本地开发时建议 `export ZHC_LANG_PACKS=$PWD`（语言包定位链：环境变量 → 当前目录
`./lang-packs` → 可执行文件旁 → `~/.zhc/lang-packs`）。

## 子命令一览

| 命令 | 说明 |
|---|---|
| `zhc init [--native] <项目名>` | 生成方言项目骨架（cjc-version 动态探测；`--native` 加 cjpm 构建钩子） |
| `zhc run <文件.zc\|目录>` | 转译 → 编译 → 运行（项目/工作区自动探测） |
| `zhc check <文件.zc\|目录>` | 转译 → 编译检查（不运行） |
| `zhc lint <文件.zc> [--fix]` | 方言风格检查（全角/尾随空白/CRLF/空行/行长）+ cjlint 集成 |
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
├── zhc/                    # 主项目（仓颉实现，约 20 个模块）
│   ├── src/                # 词法转译/别名/诊断翻译/语言包/LSP/工作区…
│   ├── lang-packs/         # zh + en 语言包（关键字/别名/模块路径/stdlib/错误表）
│   └── examples/           # 方言示例（hello/stdlib/教程综合/宏演示）
├── docs/
│   ├── tutorial/           # 九章递进教程（全部母语示例）
│   └── errors-dictionary.md# 错误信息字典（由 tools/gen_error_dict.py 生成）
├── scripts/
│   ├── acceptance.sh       # 一键全量验收（本地与 CI 共用，50 项断言）
│   └── release.sh          # 离线发布包（bin/zhc 启动器 + 运行时库 + 语言包 + docs/tools）
├── tools/                  # VS Code 扩展 + 高亮/字典生成脚本
├── .github/workflows/ci.yml# Linux 全量验收 + Windows 构建自检
└── zhc-design.md           # 落地设计文档（含 §13.1 实测记录）
```

## 文档

- [教学教程](docs/tutorial/README.md)（09 章递进，全部母语示例）
- [入门书（初中生版）](docs/cangjie-book.md)（零基础学编程：12 章 + 练习答案，全部示例实测可运行）
- [错误信息字典](docs/errors-dictionary.md)（按官方错误码反查）
- [设计文档](zhc-design.md)（架构/语言包规范/风险与实测记录）

## CI 与发布

- CI：Linux runner 跑 `scripts/acceptance.sh` 全量验收并上传离线包 artifact；
  Windows runner 构建 + 自检（best-effort）。仓颉 SDK 安装步骤为占位命令，
  发布前替换为实际下载渠道。
- 发布：`scripts/release.sh [版本] [系统] [架构]` 产出
  `zhc/dist/zhc-<版本>-<系统>-<架构>.tar.gz`（解压即用，无需 SDK 与环境变量）；
  annotated tag `vX.Y.Z` 触发 GitHub Release 工作流。

## 许可证

[MIT](LICENSE)
