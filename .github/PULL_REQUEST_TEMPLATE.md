## 改动摘要

（一句话说明动机与范围；对应 Issue 编号：#）

## 验收结果（提交前必跑，粘贴汇总即可）

```text
$ bash scripts/acceptance.sh
共 N 项断言，通过：N    失败：0
```

## 自查清单

- [ ] `bash scripts/acceptance.sh` 全过（或注明跳过项与原因）
- [ ] 教程正文/代码有改动 → 已 `bash scripts/tutorial-check.sh --refresh` 更新快照基线并一并提交
- [ ] 语言包/翻译有改动 → 已重新生成 `errors.toml` 与 `errors-dictionary.md`（不手改生成物）
- [ ] 新增脚本/文件已进 acceptance 段 11 语法检查列表（如适用）
- [ ] 文档同步：README / 术语表 / 语言包开发 / 选书指南 涉及处已更新
- [ ] 提交信息风格与 `git log` 一致（动词开头、中文、小步可验证）

## 备注

（未尽事项、已知边界、后续建议——不需要贴大段日志，维护者会看验收输出）
