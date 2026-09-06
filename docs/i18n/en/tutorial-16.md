<!-- zhc-i18n 源: docs/中文仓颉程序设计/第3卷-工程与思想/16-程序设计思想.md 基线: 4d80e2160b0cf964 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第3卷-工程与思想/16-程序设计思想.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 16 The Ideas Behind Program Design

> **What you will learn in this chapter**: gather the "design ideas" scattered across the earlier chapters into one system — syntax is the surface; the ideas are what's beneath. Once you understand *why* Cangjie is designed this way, the syntax no longer needs memorizing.
> **After this chapter you can answer**: Which three mechanisms does Cangjie use to eliminate memory disasters? Why is `let` the default? What does exhaustiveness checking protect you from?

---

## 16.1 What Is a Design Idea

**Definition**: a design idea = the **value trade-off** a language designer made behind the syntax. Every language feature answers one question: "what did we sacrifice, and what did we buy with it?"

| Language feature | Sacrificed | Gained |
|---|---|---|
| No `null` (Options) | one more layer of unwrapping | null-pointer bugs extinct |
| Immutable by default (`let`) | typing `var` one more time | accidental modification / data races greatly reduced |
| Explicit `open`/`override` | two more keywords | clear, controlled inheritance relationships |
| Exhaustiveness checking | matches must list every branch | missing branches surface at compile time |

**Why it matters**: beginners learn "how to use it"; veterans ask "why is it designed this way" — the latter is where transferable skill comes from. Once you understand the trade-offs, you can infer the design intent of a new language or API yourself instead of memorizing.

## 16.2 Memory Safety: A World Without null

**The idea**: C/C++ spent decades plagued by **null pointers** and **dangling references** (a huge share of security vulnerabilities). Cangjie chose "a stricter compiler, a little less programmer freedom" — errors are stopped at compile time instead of crashing at runtime.

**Where it shows**:

- **No `null` keyword**: nullability lives in the type system — an `Option<T>` is either `Some(x)` or `None` (chapter 14);
- **Dangling references**: reference lifetimes are managed by the compiler (ownership/borrowing); used memory never "dangles";
- **Diagnostics follow**: "cannot assign to immutable value" and "type mismatch" are this idea showing up in the error messages.

## 16.3 Value Types and Reference Types: The Division of Labor

**The idea**: types come in two kinds — **value types** (copy semantics: integers, structs, enums, tuples) and **reference types** (sharing semantics: classes, arrays, strings, interfaces). Each has its own territory, and **the data structure decides the semantics, not the caller**:

| | Value types | Reference types |
|---|---|---|
| Assignment | full copy (no aliasing) | shared reference (aliasing) |
| Strengths | predictable, thread-safe, no surprise mutation | no copying of large objects, required for polymorphism |
| Represented by | `struct`, enums, tuples | `class`, arrays, strings |

**Rule of thumb**: small and independent data → struct; polymorphism/sharing → class (chapter 12). Changing a copy never affects the original — "no aliasing" keeps reasoning simple: a variable is modified in exactly one place.

## 16.4 Immutable by Default (`let` First)

**The idea**: mutability is a leading source of bugs (accidental modification, concurrency races, hard reasoning). Cangjie sets "immutable" as the default — **mutability becomes a privilege you opt into**. One glance at the `var`s shows where change can happen:

```cangjie
main() {
    let config = "fixed value"       // immutable: no need to worry about it changing
    var count = 0            // mutable: the only place change can happen — watch this one
}
```

**Where it shows**: `let` is the default, parameters are read-only, struct fields need `mut` to change, strings are immutable (chapters 9/12).

**The concurrency dividend** (chapter 14): immutable data **needs no synchronization** — it cannot be modified concurrently and cannot race. In concurrent programs prefer `let`; only truly shared mutable state needs `synchronized`/atomics.

## 16.5 Type Inference with Strong Typing

**The idea**: the best of both schools — the **writing experience of a dynamic language** (fewer type annotations) plus the **safety of a static one** (everything checked at compile time). The rule: **omit where inferable, write it where it matters**:

```cangjie
main() {
    let x = 90                // inferred: Int64
}
func double(n: Int64): Int64 { return n * 2 }   // parameters must be annotated — the interface contract made explicit
```

**Where it shows**: local variables and return types can be inferred; **function parameters must be annotated** (they are part of the interface contract); generic calls instantiate automatically (chapter 15).

## 16.6 Multi-Paradigm Fusion: Expressions Have Values

**The idea**: no single paradigm solves every problem. Cangjie absorbs rather than excludes — logic in imperative style, data processing in functional style, system modeling in OO. Each does what it does best:

```cangjie
main() {
    let score = 85
    let grade = if (score >= 60) { "pass" } else { "fail" }   // if is an expression: it has a value
    println(grade)

    let description = match (score) {                                    // match is an expression too
        case x where (x >= 90) => "excellent"
        case _ => "other"
    }
    println(description)
}
```

**Where it shows**: `if`/`match` are expressions (functional) while also supporting statement style (imperative); match's exhaustiveness checking + `map`/`filter` chains (functional) + class hierarchies (OO) coexist. **"Expressions have values" makes code tighter**: assignment and branching merge into one, fewer temporaries.

## 16.7 Pattern Matching and Exhaustiveness Checking

**The idea**: an `if` chain is "manually managed branching" — forget an `else` and the compiler says nothing while the program quietly goes wrong. Exhaustiveness checking turns "branch completeness" into a **compile error** — one of the strongest safety designs Cangjie inherited from functional languages (chapter 13).

**Where it shows**: matching enums/options/tuples must be exhaustive (or end with `_`); `case Some(name)` tests and destructures at once; add a new enum member and every match point becomes a compile error — **forcing you to handle the new situation** (a safety net for extensibility).

## 16.8 Explicit over Implicit: Visible Interface Contracts

**The idea**: turn "every place a mistake can happen" into an **explicit compile-time check**. The cost is a few extra words; the gain is one whole class of bugs. Cangjie's explicitness checklist:

| Explicit marker | Error it prevents |
|---|---|
| `open` before inheritance | accidental inheritance breaking encapsulation |
| `override` before covering | a typo'd method name becoming a new method |
| `mut` before modifying a struct self | copies changing behind your back |
| `as` before downcasting | type mismatches |
| `where T <: Comparable` | generic code calling nonexistent methods |
| Typed parameters | vague interface contracts |

**The core**: **closed by default, immutable by default, explicit by default** — three "defaults" turn privileges into applications. Reading code, one glance at the explicit markers shows "where change is allowed, where extension is allowed".

## 16.9 Extensions: Open-World Design

**The idea**: classic OO "modifying a class" has two pains: no permission (standard library/third-party) and blast radius (fragile). `extend` turns "adding behavior" into a **bolt-on** operation — each module attaches methods to the types it cares about, without interference:

```cangjie
extend Int64 {
    public func doubled(): Int64 { return this * 2 }
}

main() {
    println(21.doubled())        // 42 (extension methods call like native methods)
}
```

**Where it shows**: the dialect method names on strings/collections (`trimAscii`/`split`, etc.) rely heavily on the extension mechanism; **composition over inheritance**: express "has-a" through composition rather than forcing inheritance.

## 16.10 The Philosophy of Error Handling

**The idea**: error handling is a **design decision**, not syntax — classify every failure scenario first (chapter 14):

- **Expected failures** (input, lookups, ranges) → `Option`: failure is part of the return value; the caller must handle it;
- **Unexpected errors** (bugs, environment) → exceptions: propagate up the call stack automatically; whoever can, catches;
- **Fail fast**: `getOrThrow()`, precondition checks — the earlier an error surfaces, the easier the fix; swallowing errors is the most dangerous code;
- **Never use exceptions as control flow**: poor performance and readability.

## 16.11 Declarative Data Processing

**The idea**: compress "traverse + condition + collect" into one step — **declarative** code states "what to do" (filter out the failing scores), **imperative** code states "how to do it" (build a list, loop, test, append). The intent is stated outright and the reader needn't translate:

```cangjie
import std.collection.*
main() {
    var scores = ArrayList<Int64>()
    scores.add(95); scores.add(45); scores.add(70)
    let passing = scores |> filter({ x => x >= 60 }) |> collectArray   // declarative
    println(passing.size)       // 2
}
```

**Companion ideas**: **lazy evaluation** — `map`/`filter` return iterators that compute only when consumed (`collectArray`); **the source container is untouched** — in functional style the original data is "input" and won't be quietly changed.

## 16.12 Metaprogramming: Compile-Time Evaluation

**The idea**: hoist "repetitive work done on every run" into "done once at compile time" — macros run at compile time, leaving only the expansion at runtime, **zero overhead**; a macro crash = a compile error (a good thing): errors surface at the earliest moment (chapter 15).

**Three safety designs** (contrast with C preprocessor text substitution):

- **Hygienic macros**: no accidental capture of the caller's variables;
- **Typed**: inputs and outputs are `Tokens`;
- **No IO**: macros cannot read files or access the network — the build stays reproducible.

**The timing judgment**: 90% of "duplicated code" dissolves with functions/generics; only when you need to **operate on code itself** do macros come into play — the last resort, not the first choice.

## 16.13 The Design Ideas Behind the zhc Dialect

**① Native-language terminology (Chinese IS the code)**: the dialect is not "a translated document" — it is the language itself translated into Chinese: keywords, standard library, error messages, all Chinese. The cognitive load of programming has two layers: **algorithmic thinking** (already in your mother tongue) and the **language barrier** (English keywords). The dialect removes the second layer — "think in your language, express in your language".

**② Diagnostics as pedagogy**: compiler errors are the primary site of learning — a beginner spends 70% of their time in dialogue with the compiler. Chinese diagnostics turn "error messages" into "teaching material": telling you how you erred (💡) and how to fix it (repair examples) — this is zhc's **value-added layer** over the official compiler.

**③ Transpilation as table lookup**: the dialect is not a new language — it is a "table-driven rewriting system": table lookup + context protection (strings untouched, declared names exempt, interpolation protected). Understanding this design explains why swapping a word table creates a new dialect.

**④ Extensible language packs (dialect as configuration)**: the entire dialect is a set of **data files** (word tables/message tables), not hard-coded logic — **the transpilation engine and the language packs are decoupled**: packs evolve independently, can be validated (`mapping check`), can be extended (custom error codes). One word-table swap and it's a new dialect — this is the foundation of language-neutrality.

## Exercises

1. Pick 3 of this chapter's 12 ideas and write a counterfactual for each: "what if Cangjie didn't do this?";
2. Review code you've written for one "used `let` but wanted to change it" error — which idea does it correspond to?;
3. Rewrite an `if/else if/else` chain with `match` and feel the difference of "expressions have values";
4. Think: why must function parameters be typed while local variables can be inferred? How does this relate to "interface contracts"?;
5. Design a new idea for zhc: if you could add one feature to the dialect, what would it be? Which design trade-off does it fit?

## Summary

- Design ideas = the value trade-offs behind the syntax: sacrifice a little convenience, eliminate a whole class of bugs;
- Cangjie's four cornerstones: memory safety (no null), immutable by default, explicit contracts, exhaustiveness checking;
- Multi-paradigm fusion: imperative for logic, functional for data, OO for systems — each where it's strongest;
- Error-handling philosophy: expected failures via Options, unexpected via exceptions, fail fast;
- zhc's four ideas: mother-language-first, diagnostics as pedagogy, transpilation as table lookup, extensible language packs.

## Questions to Think About

1. "Sacrifice a little convenience, eliminate a class of bugs" — can you name other examples in the language? (Hint: think `enum`, `Option`, `where`.)
2. Why does "swallowing an error" violate the fail-fast principle? What happens after an error is swallowed?
3. Which scenarios suit declarative vs imperative? (Hint: data processing vs flow control.)
4. If zhc swapped its word table (say Russian) it would become Russian Cangjie — what else does "dialect as configuration" imply? (Hint: the relationship between language packs, UI copy, and error translation.)
