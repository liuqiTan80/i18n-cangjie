# 诊断教学用例库（tools/diag-cases）

> 定位：**目录化的黄金错误样例**——每个用例 = 一个「刻意写错的方言程序」+ 期望的母语诊断片段 + 期望命中码。用于回归防漂移（错误翻译回退英文、码面改名/失效）与教学（每段源码带 `// 教学` 注释，标注对应教程章节与坑点）。

## 目录约定

```
tools/diag-cases/
├── README.md
├── sema_undeclared_identifier/        # 目录名 = 期望命中的诊断码（errors.toml 码面键）
│   ├── main.zc                        # 错误源码（方言；首行注释写教学场景出处）
│   └── expect.txt                     # 期望输出中的母语片段（每行一个，全部须命中）
└── …
```

## 驱动

```bash
# 全量跑（16 用例：母语断言 + 码命中断言），任一失败退出码非 0
python3 tools/diag_cases.py --zhc zhc/target/release/bin/main --lang-packs zhc --stats /tmp/s.txt

# acceptance 段 4 已接入（断言计数 1 项 + 警告场景块）；--stats 指向段 15 的
# ZHC_DIAG_STATS，命中码自动汇入 diag-stats.txt 参与触发率聚合
```

每个用例断言三件事：**zhc check 必须失败**（错误源码不应通过）；输出须含 `expect.txt` 每一行（防英文回退）；命中日志（`ZHC_DIAG_STATS`）须含目录码名（防码面漂移，与 `tools/diag_coverage.py` 同源）。

## 新增用例（三步）

1. **写错误源码并确认码**：把「学生最容易写出的错误」存成 `main.zc`，跑
   `ZHC_DIAG_STATS=/tmp/s.txt zhc check main.zc`，`cat /tmp/s.txt` 得到命中的稳定诊断码（如 `sema_mismatched_types`）；码不在 errors.toml 码面时先补语言包再建用例；
2. **建目录**：`mkdir tools/diag-cases/<码名>`，把源码与期望片段分别写入 `main.zc`、`expect.txt`（片段取错误主行的母语文本，如「类型不匹配」）；
3. **验证**：跑驱动脚本全量回归；`acceptance.sh` 段 4/段 15 自动覆盖。

## 现状（16 用例）

- **12 迁移**：原 acceptance 段 4 内嵌的 12 个高频场景（未声明标识符/类型不匹配/不可变赋值/缺右括号/找不到包/参数个数/未知类型/重复声明/泛型缺参/非法转义/数字溢出/主函数缺失）；
- **4 新增**（教学高价值，来自实测探测）：
  - `parse_unexpected_declaration_in_scope`：扩展不能加存储字段（第 20 章 §20.2 边界）；
  - `sema_invalid_binary_expr`：`!=` 不自动取反（第 20 章 §20.4.2）；
  - `parse_invalid_overloaded_operator`：`+=` 不可直接重载（第 20 章 §20.5.1）；
  - `chir_idx_out_of_bounds`：编译期可查出的常量索引越界（第 11 章）。

关联：码触发率聚合见 `tools/diag_coverage.py`；错误字典生成见 `tools/gen_error_dict.py`。
