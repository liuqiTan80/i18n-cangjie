#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check-libs.py —— zhc 翻译众包平台门禁（无 SDK 依赖，Python ≥3.8 即可跑）。

用法：
  python3 scripts/check-libs.py                    # 格式/撞词表/双目录一致性
  python3 scripts/check-libs.py --locked <base>    # 追加：git diff base...HEAD 触碰锁定区即失败

检查项（平台约定见 libs/README.md）：
  1. crates 全部 .toml 结构（含运行时镜像侧）：节名合法（标识符/模块路径/宏）、
     键值均带引号、文件内无重复键、值 = 官方原名（标识符节须匹配
     ^[A-Za-z_][A-Za-z0-9_]*$，模块路径节须为点分段）；注释用 #（禁行内尾
     注释，防解析歧义）。镜像侧与 libs 侧同名的孪生文件只检查一次。
  2. 撞词表：crates 的标识符/宏键不得出现在 zh 语言包（keywords/stdlib/
     module_paths 键集）——crates 最后加载会覆盖内置映射，撞词表 = 全局改义
     风险；跨库重复：同一节（标识符/模块路径/宏）的键不得出现在多个 .toml——
     运行时按文件名排序后载覆盖，同键 = 歧义（哪个库生效取决于文件名）。
     两项检查同时覆盖 libs/ 与 zhc/lang-packs/zh/crates/（直投镜像的文件
     以前完全绕过检查，审计修复）。
  3. 双目录一致性：libs/zh/crates/ 与 zhc/lang-packs/zh/crates/ 同路径文件
     内容必须一致（libs 为规范源，lang-packs 为运行时镜像，同步见
     scripts/sync-libs.sh）；lang-packs 侧多余文件仅提示（本地 zhc translate
     生成未上平台属正常），但会做 1+2 全量检查。
  4. --locked <base>：锁定区（zh 词表五件 + 术语表 + 教程目录，改动会牵动
     教程转译快照/错误字典）须先开 Issue 经维护者批准——PR 触碰即失败，
     请在 PR 描述附 Issue 链接后由维护者以 [LOCKED] 说明复核。
     PR 直投 zhc/lang-packs/zh/crates/*.toml 且 libs/ 侧无同名规范源，
     同样失败（绕过平台入口的提交不被接受）。

退出码：0 = 全部通过；1 = 有失败项（提示均输出到 stdout）。
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBS_CRATES = os.path.join(ROOT, "libs", "zh", "crates")
PACK_CRATES = os.path.join(ROOT, "zhc", "lang-packs", "zh", "crates")
ZH_PACK = os.path.join(ROOT, "zhc", "lang-packs", "zh")

# 锁定区：改动须先开 Issue（翻译资产，牵动教程/字典/全链路）
LOCKED_EXACT = {
    "docs/术语表.md",
    "docs/errors-dictionary.md",
}
LOCKED_PREFIX = (
    "docs/中文仓颉程序设计/",
)
LOCKED_PACK = True  # zhc/lang-packs/zh/ 顶层 *.toml（crates/ 见 check_locked 的直投拦截）

SECTION_RE = re.compile(r'^\["([^"]+)"\]\s*$')
KV_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
ID_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SEG_RE = re.compile(r"^[A-Za-z0-9_一-龥]+$")
BARE_COMMENT_RE = re.compile(r"^\s*#|^\s*$")
VALID_SECTIONS = ("标识符", "模块路径", "宏")


def parse_keys(path):
    """逐行解析 TOML 键值（平台文件禁止行内尾注释，键/值均须引号包裹）。

    返回 (节→[(键, 值, 行号)] 的有序列表, 错误列表)。"""
    items = []
    errors = []
    section = None
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as e:
        return None, ["读取失败：%s" % e]
    for i, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = SECTION_RE.match(line)
        if m:
            section = m.group(1)
            if section not in VALID_SECTIONS:
                errors.append("%s:%d 非法节名 [%s]（允许：标识符/模块路径/宏）"
                              % (path, i, section))
            continue
        m = KV_RE.match(line)
        if not m:
            errors.append("%s:%d 无法解析（键/值须引号包裹且无行内注释）：%s"
                          % (path, i, line[:60]))
            continue
        k, v = m.group(1), m.group(2)
        if section is None:
            errors.append("%s:%d 键值出现在节声明之前" % (path, i))
        items.append((section, k, v, i))
    return items, errors


def check_toml(path):
    """结构检查：返回 (键集, 错误列表)。"""
    items, errors = parse_keys(path)
    if items is None:
        return set(), errors
    keys = set()
    seen = {}
    for section, k, v, lineno in items:
        if not k:
            errors.append("%s:%d 空键" % (path, lineno))
            continue
        if k in seen:
            errors.append("%s:%d 重复键 [%s]（首次 %s:%d）"
                          % (path, lineno, k, path, seen[k]))
            continue
        seen[k] = lineno
        if section == "标识符":
            if not ID_RE.match(v):
                errors.append("%s:%d 键 [%s] 的值非官方标识符：%s"
                              % (path, lineno, k, v))
        elif section == "模块路径":
            for seg in v.split("."):
                if not SEG_RE.match(seg):
                    errors.append("%s:%d 键 [%s] 的模块路径段含非法字符：%s"
                                  % (path, lineno, k, v))
                    break
        keys.add(k)
    return keys, errors


def collect_pack_keys():
    """zh 语言包词表键集（keywords/stdlib/module_paths，含 [宏] 节）。"""
    keys = set()
    for name in ("keywords.toml", "stdlib.toml", "module_paths.toml"):
        items, _ = parse_keys(os.path.join(ZH_PACK, name))
        if items:
            for _, k, _, _ in items:
                keys.add(k)
    return keys


def collect_crate_tomls():
    """收集全部待检查 crates toml：libs 规范区 + lang-packs 运行时镜像。

    镜像侧与 libs 侧同名的孪生文件只保留 libs 侧一份（内容一致性由
    check_sync 保证）；镜像侧独有文件（直投绕过尝试）全量纳入检查。"""
    libs_tomls = []
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "libs")):
        for name in sorted(files):
            if name.endswith(".toml"):
                libs_tomls.append(os.path.join(dirpath, name))
    pack_tomls = []
    if os.path.isdir(PACK_CRATES):
        libs_names = {os.path.basename(p) for p in libs_tomls}
        for name in sorted(os.listdir(PACK_CRATES)):
            if name.endswith(".toml") and name not in libs_names:
                pack_tomls.append(os.path.join(PACK_CRATES, name))
    return sorted(libs_tomls) + sorted(pack_tomls)


def check_libs_dir():
    """检查 1+2：全部 crates toml（含镜像侧直投文件）的结构、撞词表与
    跨库重复。返回失败数。"""
    fails = 0
    pack_keys = collect_pack_keys()
    tomls = collect_crate_tomls()
    if not tomls:
        print("libs/ 与运行时镜像 crates/ 下无 .toml（平台目录为空？）")
        return 1
    owner = {}  # (节, 键) → 首个登记文件
    for path in sorted(tomls):
        rel = os.path.relpath(path, ROOT)
        keys, errors = check_toml(path)
        if errors:
            fails += 1
            print("【格式失败】%s" % rel)
            for e in errors:
                print("    " + e)
            continue
        hit = sorted(keys & pack_keys)
        if hit:
            fails += 1
            print("【撞词表失败】%s：以下键与 zh 语言包键集冲突（会覆盖内置映射）："
                  % rel)
            for k in hit:
                print("    " + k)
        # 跨库重复：与其余文件同节键冲突（运行时后载覆盖歧义）
        dup = []
        for section, k, _v, _ln in parse_keys(path)[0]:
            if k in pack_keys:
                continue  # 已按撞词表报过
            key = (section, k)
            if key in owner:
                dup.append((key, owner[key]))
            else:
                owner[key] = rel
        if dup:
            fails += 1
            print("【跨库重复失败】%s 与已有文件同节键冲突（运行时按文件名后载覆盖，"
                  "同键歧义）：" % rel)
            for (section, k), first in sorted(dup):
                print("    [%s] \"%s\"（已见于 %s）" % (section, k, first))
        if not errors and not hit and not dup:
            print("通过：%s（键 %d 个）" % (rel, len(keys)))
    return fails


def check_sync():
    """检查 3：libs 与 lang-packs crates 双目录一致性。返回 (失败数, 提示)。"""
    fails = 0
    warns = []
    if not os.path.isdir(LIBS_CRATES):
        print("缺少平台目录 libs/zh/crates/")
        return 1, warns
    for dirpath, _dirs, files in os.walk(LIBS_CRATES):
        for name in sorted(files):
            if not name.endswith(".toml"):
                continue
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, LIBS_CRATES)
            dst = os.path.join(PACK_CRATES, rel)
            with open(src, encoding="utf-8") as f:
                a = f.read()
            if not os.path.exists(dst):
                fails += 1
                print("【未同步失败】libs/zh/crates/%s 未安装到运行时镜像 "
                      "zhc/lang-packs/zh/crates/（跑 scripts/sync-libs.sh）" % rel)
                continue
            with open(dst, encoding="utf-8") as f:
                b = f.read()
            if a != b:
                fails += 1
                print("【漂移失败】libs/zh/crates/%s 与运行时镜像内容不一致（跑 "
                      "scripts/sync-libs.sh 后重新提交）" % rel)
    # lang-packs 侧多余文件：本地 zhc translate 生成未上平台 → 提示不失败
    if os.path.isdir(PACK_CRATES):
        extra = []
        for name in sorted(os.listdir(PACK_CRATES)):
            if not name.endswith(".toml"):
                continue
            if not os.path.exists(os.path.join(LIBS_CRATES, name)):
                extra.append(name)
        if extra:
            warns.append("lang-packs 侧未上平台：%s（本地 zhc translate/mapping "
                         "auto 生成属正常；想共享请复制到 libs/zh/crates/ 提 PR）"
                         % "、".join(extra))
    return fails, warns


def check_locked(base):
    """检查 4：git diff base...HEAD 是否触碰锁定区。返回失败数。"""
    try:
        out = subprocess.run(
            ["git", "diff", "--name-only", base + "...HEAD"],
            cwd=ROOT, capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError:
        print("--locked 需要可用的 git 基线：%s（先 git fetch 或换本地分支名）"
              % base)
        return 1
    touched = [ln.strip() for ln in out.splitlines() if ln.strip()]
    if not touched:
        print("锁定区检查：无差异文件（基线 %s）" % base)
        return 0
    bad = []
    for p in touched:
        if p in LOCKED_EXACT or p.startswith(LOCKED_PREFIX):
            bad.append(p)
        elif LOCKED_PACK and p.startswith("zhc/lang-packs/zh/") \
                and "/crates/" not in p:
            bad.append(p)
        elif p.startswith("zhc/lang-packs/zh/crates/") and p.endswith(".toml"):
            # 直投运行时镜像拦截（审计修复）：此前 crates/ 被 locked 检查显式
            # 排除、撞词表又只扫 libs/，绕过文件可覆盖内置关键字映射。
            # libs 侧已有同名规范源（PR 同时提交规范源 + 同步镜像）→ 放行。
            libs_counterpart = os.path.join(LIBS_CRATES, os.path.basename(p))
            if not os.path.exists(libs_counterpart):
                bad.append(p + "（libs/zh/crates/ 无同名规范源：请把翻译放到 "
                             "libs/zh/crates/ 走平台入口，镜像由 sync-libs.sh 同步）")
    if not bad:
        print("锁定区检查：通过（基线 %s，%d 个文件均不在锁定区）"
              % (base, len(touched)))
        return 0
    print("【锁定区失败】以下翻译资产改动须先开 Issue 经维护者批准（改动会牵动 "
          "教程转译快照/错误字典/全链路）：")
    for p in sorted(bad):
        print("    " + p)
    print("流程：Issue 说明动机 → 维护者批准 → PR 描述附 Issue 链接。")
    return 1


def main():
    args = sys.argv[1:]
    base = None
    if args and args[0] == "--locked":
        if len(args) < 2:
            print("用法：check-libs.py --locked <git 基线>")
            return 2
        base = args[1]
    total = 0
    total += check_libs_dir()
    f, warns = check_sync()
    total += f
    for w in warns:
        print("提示：" + w)
    if base is not None:
        total += check_locked(base)
    if total == 0:
        print("=== check-libs：全部通过 ===")
        return 0
    print("=== check-libs：%d 项失败 ===" % total)
    return 1


if __name__ == "__main__":
    sys.exit(main())
