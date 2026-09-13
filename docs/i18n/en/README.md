<!-- zhc-i18n 源: README.md 基线: 55556d611cf2892b 时间: 2026-09-13 -->

# zhc — Write Cangjie in Your Native Language

Language / Language / Langue / Sprache / Idioma / 언어 / 言語 / Язык：[中文](../../../README.md) · **English** · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Español](../es/README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

**zhc** is a native-language teaching framework for the Cangjie programming
language: it transpiles dialect source code (e.g. Chinese `.zc`, Korean `.kc`,
French `.fc`) into standard Cangjie, and translates the compiler's English
diagnostics back into learner-friendly messages in the chosen language
(error code → message table → type localization → fix examples). The dialect
is selected with the `ZHCLANG` environment variable (default `zh`); everything
is driven by a **language pack**.

## Quick start (about 10 minutes)

**1. Install the Cangjie SDK** (the only external dependency): download
**1.0.5** from cangjie-lang.cn/download, unpack it and run the bundled
`envsetup.sh` so that `cjc` and `cjpm` are on your `PATH`. Verify:

```bash
cjc --version    # Cangjie Compiler: 1.0.5 (cjnative)
```

**2. Build zhc** (no network needed, zero third-party dependencies):

```bash
cd zhc
cjpm build       # produces target/release/bin/main
```

**3. Run your first program** (the English dialect example shipped in the
repo — the `en` pack is an identity mapping, so English dialect is exactly
official Cangjie):

```bash
export ZHC_LANG_PACKS=$PWD        # from the repo root: zhc/
zhc run examples/en-hello.en
# ✅ Compilation OK: replaced 4 dialect identifier(s).
# Hello, English!
```

## Write in your own language

Any language with a pack under `zhc/lang-packs/<code>/` works — 9 packs ship out of the box: `zh`/`en` (full tier), `ru`/`ja`/`ko`/`fr`/`es`/`de` (standard tier), and `ar` (RTL demo tier). For example, Korean
(`ZHCLANG=ko`, extension `.kc`):

```kc
메인() {
    두다 이름: 문자열 = "Cangjie"
    출력("안녕하세요, ${이름}!")
}
```

Run it with `ZHCLANG=ko zhc run hello.kc`. The French dialect works the same
way (`principal/soit/Chaine/afficher`, extension `.fc`).

## Translations for third-party libraries

Library API mappings live in the shared translation hub, not in your source
tree — download only the language and library you need:

```bash
zhc share list                     # browse the shared registry
zhc share fetch csv4cj --lang en   # download one mapping for your language
zhc share publish my_mapping.toml  # contribute your own translation
```

Downloaded mappings pass checksum + quality gates (format, official-name
checks, reserved-word collision) before being installed into
`~/.zhc/lang-packs/<lang>/crates/`. Missing translations gracefully fall back
to Chinese; your program keeps working either way.

## Terminology (used consistently across English docs)

| English | In code/docs | Notes |
|---|---|---|
| dialect | `.zc` `.kc` `.fc` … | Cangjie written in a native language |
| language pack | `lang-packs/<code>/` | keyword/alias tables + diagnostics + UI copy |
| mapping | `<lang>/crates/<lib>.toml` | native name = official API name |
| transpile | `zhc run` / `zhc check` | dialect → standard Cangjie |
| shared hub | `zhc share …` | centralized translation registry |
| baseline | `zh@<checksum>` | sync fingerprint of the zh source |

## Learn more

- Tutorial (canonical, in Chinese): [Designing Cangjie in Chinese — the canonical textbook](../../../docs/中文仓颉程序设计/README.md)
- Language packs & how to contribute one: [language-pack development](../../../docs/语言包开发.md)
- Localization scope & sync mechanism: [docs/i18n/README.md](../README.md)
- Tutorial guide in English: [Tutorial introduction (Lesson 0)](tutorial-00.md)
- Troubleshooting: run `zhc doctor` — a six-point environment self-check (compiler, build tool, language packs, writable directory, share source, cjlint) with localized fix guidance.
