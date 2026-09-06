<!-- zhc-i18n 源: docs/中文仓颉程序设计/README.md 基线: b336d790600ad489 时间: 2026-09-06 -->

# Tutorial guide — Lesson 0 (English)

Language nav：[中文教程正本](../../中文仓颉程序设计/README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Español](../es/README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md)

The canonical tutorial **《中文仓颉程序设计》** (Designing Cangjie in Chinese) is a
thorough, handbook-style course: **3 volumes, 20 chapters + 3 appendices + an
answer key**, with **150+ code blocks all verified against official
`cjc 1.0.5`**. This page is your Lesson 0 in English; the canonical text is in
Chinese — read it alongside this guide, or start with the dialect examples below.

## Three volumes

| Volume | For you if… | Contents |
|---|---|---|
| Vol. 1 First steps | complete beginner | setup, first program, variables, numbers, decisions, loops, functions |
| Vol. 2 Core & beyond | systematic grammar | functions, type system, strings, collections, OOP, enums, errors, generics & macros |
| Vol. 3 Craft & thinking | quality-focused developers | design thinking, algorithms & data structures, software engineering, capstone project |

## Lesson 1: your first program

Write it in the English dialect (= official Cangjie, identity mapping):

```en
main() {
    let greeting: String = "Hello, Cangjie!"
    println(greeting)
}
```

Save as `hello.en`, then run `ZHCLANG=en zhc run hello.en`. Every dialect
transpiles to exactly this standard code — for example the Chinese dialect
writes `main` as `主函数`, `let` as `让`, `println` as `打印行`. Language packs
included today: `en`/`ru`/`ja`/`ko`/`fr`/`es`/`de` (see each pack's quick start).

## Where to look (quick reference)

- Zero-based start → Vol. 1, chapters 01–07 (≈10–20 min each, exercises included)
- Systematic grammar → Vol. 2, chapters 08–15 (definition → syntax → example → notes)
- Quality & engineering → Vol. 3, chapters 16–19
- Keywords / stdlib lookup, error decoding → Appendices A/B/C

Open the canonical tutorial: [docs/中文仓颉程序设计/README.md](../../中文仓颉程序设计/README.md)
