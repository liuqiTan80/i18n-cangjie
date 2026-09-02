---
name: 报告问题（bug / 词表缺词 / 文档错误）
about: 任何不符合预期的行为——工具、词表、教程、文档皆可
title: "[问题] 简述"
labels: bug
---

## 环境

- OS：Linux / macOS / Windows（版本）
- 仓颉 SDK 版本：（如 1.0.5；`cjc --version`）
- zhc 来源：源码构建 / 离线包 / install.sh
- zhc 版本：（`zhc help` 首行）

## 复现

最小 `.zc` 文件（或文档位置）：

```cangjie
（贴代码）
```

完整命令与输出：

```text
$ （命令）
（实际输出——含报错原文，不要截图）
```

期望输出：

```text
（期望内容）
```

## 归属（不确定可不选）

- [ ] 工具 bug（转译/诊断/lint/LSP 行为错误）
- [ ] 词表缺词（教程/示例跑不过、报「未收录」）
- [ ] 教程/文档错误（正文与代码不一致、链接失效、口径过期）
- [ ] 其他

## 备注

（验收参考：`bash scripts/acceptance.sh`；改词表/翻译前先读 CONTRIBUTING 与 docs/语言包开发.md）
