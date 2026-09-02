#!/usr/bin/env python3
"""组合验证：19.3 核心逻辑 + 19.5 重构片段（环境变量 VERIFY_ROOT 指定工作目录）"""
import os
import pathlib

base = pathlib.Path(os.environ.get("VERIFY_ROOT", pathlib.Path(__file__).resolve().parent))
src_dir = base / "src"
exp_dir = base / "exp2"
exp_dir.mkdir(exist_ok=True)

p112 = sorted(src_dir.glob("*-complete-19-综合实战-1.zc"))
p114 = sorted(src_dir.glob("*-complete-19-综合实战-3.zc"))
if not p112 or not p114:
    raise SystemExit(f"找不到组合源文件：19-综合实战-1={p112}，19-综合实战-3={p114}")
p112 = p112[0].read_text(encoding="utf-8")
p114 = p114[0].read_text(encoding="utf-8")

# 19.3 完整代码自带主函数：剥离入口部分，由 19.5 重构版入口接管
p112 = p112.split("// —— 入口 ——")[0].rstrip()

combo = p112 + "\n" + p114
out = exp_dir / "combo.zc"
out.write_text(combo, encoding="utf-8")
print(f"已生成 {out}（{len(combo.splitlines())} 行）")
