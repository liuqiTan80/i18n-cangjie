<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/10-字符串与文本处理.md 基线: 7e379a4d3a738804 时间: 2026-09-06 -->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/10-字符串与文本处理.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 10 Strings and Text Processing

> **What you will learn in this chapter**: master string interpolation and the string method family, learn the import statement, and get a first taste of regular expressions.
> **After this chapter you can answer**: Why is a string's length different from its character count? What happens if you slice half a Chinese character? Why must `\d` be written as `\\d` inside a string?

---

## 10.1 Definition: What Is a String

**Definition**: a string (`String`) is an **immutable sequence of Unicode characters** — once created it cannot be modified; every "modifying" operation returns a new string. Underneath it is stored as **UTF-8 bytes**: one Chinese character = 3 bytes.

## 10.2 Interpolation: `${}` as a Template

**Definition**: `${expression}` embeds a variable or expression inside a string — the primary way to build strings in Cangjie.

**Syntax**:

```cangjie
main() {
    let name = "Cangjie"
    let version = 1
    println("${name} language, version ${version}.0")   // Cangjie language, version 1.0
    println("arithmetic: ${3 + 4 * 2}")                 // arithmetic: 11 (any expression works)
    println("nested: ${name.size}")                     // nested: 7 (method calls work too)
}
```

**Notes**:

- Interpolation segments are **transpiled twice**: dialect words inside `${}` are translated to official names just like outside;
- Put **only variables and expressions** inside interpolation — `"${func}"` would be treated as code and re-transpiled; stuffing a keyword there is a compile error;
- For small-scale concatenation use `+`; for bulk concatenation use `collectString` (10.5).

## 10.3 The String Method Family: Query / Trim / Transform / Split

**Definition**: text processing is the most frequent programming scenario, and the language pack puts every common method in your mother tongue, covering four categories.

```cangjie
import regex.*
main() {
    let text = "  Cangjie coding language  "
    // ① Query
    println(text.size)                    // 29 (bytes! each CJK char is 3 bytes in UTF-8)
    println(text.indexOf("coding"))       // byte index; -1 when not found
    println(text.startsWith("  Cangjie")) // true
    println(text.endsWith("language  "))  // true
    // ② Trim / slice (string slices are byte-based — 1 CJK char needs 3 bytes)
    println("Cangjie"[0..3])              // slice by bytes
    println("(${text.trimAscii()})")      // (Cangjie coding language) — trims both ends
    // ③ Transform
    println("abc".toAsciiUpper())         // ABC
    println("ABC".toAsciiLower())         // abc
    println("a-b".replace("-", "→"))      // a→b
    // ④ Split
    let parts = text.trimAscii().split(" ")
    println(parts.size)                   // 3 (split returns an array)
    // ⑤ Match (regular expressions)
    println(Regex("\\d+").matches("123")) // true
}
```

**Four truths (memorize them)**:

| Truth | Explanation |
|---|---|
| **`.size` is bytes** | `"café".size` is 5, not 4; to iterate by character use `runes()` |
| **Slices are byte-based** | `text[0..3]` on `"café"` gives `"caf"`; a boundary inside é (e.g. `[0..4]`) throws at runtime |
| **Case conversion is ASCII-only** | `toAsciiUpper()`/`toAsciiLower()` only transform English letters — é has no ASCII uppercase |
| **Regex uses `matches`** | = the official `matches`, returns a Bool; the `\\` in `Regex("\\d+")` is the escaped `\` |

## 10.4 The Import Statement

**Definition**: `import` "opens the door" to another module's names. Paths are separated by `.`.

**Syntax**:

```cangjie
import std.collection.{ArrayList, HashMap};   // precise import: only the names in braces
import std.collection.*                        // wildcard import: every name of the module
import regex.*                                 // std.regex: regex types and matching
import math.*                                  // std.math: square roots, absolute values…
import convert.*                               // std.convert: formatting, string conversion…
```

**Notes**:

- `std.collection` comes from the language pack's "module paths" table; the mother-tongue names inside the braces are each replaced;
- The trailing semicolon is optional (consistent with the official language);
- Importing a package that isn't installed → zhc reports a "package not found" dialect error; unused imports are a warning;
- Wildcard imports can cause name clashes (qualify with `package.name` when they do).

## 10.5 Concatenation and Collection: collectString

**Definition**: `collectString` joins elements **into one string** — the correct way to do bulk concatenation; string interpolation `${}` covers the "template" need.

```cangjie
import std.collection.*
main() {
    var roster = ArrayList<String>()
    roster.add("A"); roster.add("B"); roster.add("C")
    println(roster |> collectString(separator: ""))   // ABC (no separator)
    println("PI = ${3.14159}")                        // string interpolation prints the float
}
```

**Notes**:

- Official 1.0.5 has **no** `join` — for a separator, `map` first then collect, or handle it yourself;
- `separator` is a **named argument** (official: delimiter);
- `format` is a **member method of numbers** (`42.format("${0}")`, requires `import convert.*`) — there is **no** standalone `format` package, so don't write `import format.*`.

## 10.6 A First Taste of Regex

**Definition**: a regular expression is a little language describing "string patterns" — `\d` a digit, `+` one or more, `[0-9]` a range, `.` any character. Regex objects are constructed with `Regex("pattern")` (official `Regex`, requires `import regex.*`).

**Syntax**:

```cangjie
import regex.*
main() {
    println(Regex("\\d+").matches("123"))       // true (123 is all digits)
    println(Regex("\\d+").matches("12a"))       // true! it matched the substring "12" — a containment match
    println(Regex("^\\d+$").matches("12a"))     // false (^ start + $ end = full-string match)

    let phone = "138-1234-5678"
    println(Regex("\\d{3}-\\d{4}-\\d{4}").matches(phone))  // true ({3} means exactly 3)
}
```

**Notes**:

- **The escaping trap**: a regex `\d` must be written `\\d` inside a string (the string's `\\` is the real `\`) — the most common beginner error here;
- `matches` returns a **Bool** (whether it **matched at all** — note it's containment: `Regex("\\d+")` also returns true for `"12a"` because the substring `"12"` matched; to decide "the whole string is digits" you must anchor with `^` and `$`); extraction requires richer APIs (official docs);
- Regex fits "format decisions"; complex text parsing (nesting, recursion) does not suit regex — write a parser for that.

## ✳ Design Ideas

**① Encoding awareness: bytes ≠ characters**. Chinese takes 3 bytes in UTF-8, and "string length" counts bytes — the easiest beginner trap. A string is fundamentally a byte sequence; to process by character, go through `runes()`. Cangjie separates "text" (characters) from "bytes" (binary) — files, networks, and cryptography deal with byte streams, not characters. Conflating the two is a classic source of bugs.

**② Immutable strings**: strings cannot be modified; every operation produces a new value — this makes strings safe to share (no fear of mutation through arguments), at the cost of slow bulk concatenation (hence `collectString`).

**③ Declarative text processing**: a pipeline of `split` → `filter` → `collectString` reads better than hand-written loops — "split → pick → join" is the standard mental model of text processing.

## Exercises

1. Use interpolation to print: "My name is XX, I am X years old, and I have studied programming for X days";
2. Trim `"  Cangjie coding language  "`, split it by spaces, use `replace` to turn "coding" into "development", and print each part;
3. Use regex to check: does `"abc123"` start with a letter? Is `"2026-09-01"` in `\d{4}-\d{2}-\d{2}` format?
4. Use `collectString` to join an `ArrayList<String>` ("A","B","C") into `"ABC"`, then try with a separator `"A、B、C"` (hint: `map` each element to add "、" before collecting; watch the tail);
5. Challenge: count how many times each character appears in a sentence (hint: iterate with `runes()` + count in a HashMap — a preview of chapter 11's containers).

## Summary

- Interpolation `${}` takes variables and expressions and is transpiled twice; string `+` for small jobs, `collectString` for bulk;
- The method family in four groups: query (`indexOf`/`startsWith`/`endsWith`), trim (slices/`trimAscii`), transform (`toAsciiUpper`/`toAsciiLower`/`replace`), split (`split`);
- `.size` counts bytes (3 per CJK char), slices are byte-based, case conversion is ASCII-only;
- Two forms of `import`: precise (`{names}`) and wildcard (`*`); module paths come from the language pack;
- Regex: `Regex("pattern").matches(text)` returns a Bool; `\d` is written `\\d` inside strings.

## Questions to Think About

1. What does `"café"[4]` give you? Why? (Hint: bytes vs characters.)
2. Why are Cangjie strings immutable? If `replace` modified "in place", what problems would arise?
3. What do `"abc".toAsciiUpper()` and `"café".toAsciiUpper()` each output? Why is `é` left unchanged?
4. Regex `\d+` matches `"123"` and returns true — what about `"a1"`? Is `matches` "containment" or "full equality"? (Hint: try `"a1"` against `Regex("\\d+")`.)
