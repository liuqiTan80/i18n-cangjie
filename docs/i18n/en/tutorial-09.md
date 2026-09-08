<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/09-类型系统.md 基线: 6be459ff5f147ce4 时间: 2026-09-08-->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/09-类型系统.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 9 The Type System

> **What you will learn in this chapter**: master all the fundamentals of "storing data" — the three bindings (`let`/`var`/`const`), the type system from integers to tuples, type inference and explicit conversion.
> **After this chapter you can answer**: Why is `let` the default? Why does Cangjie refuse implicit type conversion? When is a type annotation mandatory?

---

## 9.1 Definition: Types Are Category Labels for Data

**Definition**: a type decides what data can **store** (range), **which operations it supports** (methods), and **how much space it takes** (bit width). Cangjie is **strongly and statically typed**: every value has a definite type at compile time, and the wrong type in a box is an immediate error.

**Overview of the basic types**:

| Dialect type | Official type | Description | Example |
|---|---|---|---|
| `Int64` | `Int64` | 64-bit signed integer (default) | `42` |
| `Int32` | `Int32` | 32-bit integer | `42` (annotated) |
| `UInt64` | `UInt64` | non-negative integer | `7u64` |
| `Float64` | `Float64` | 64-bit float (default) | `3.14` |
| `Float32` | `Float32` | 32-bit float | `1.75f32` |
| `String` | `String` | immutable Unicode text | `"Cangjie"` |
| `Bool` | `Bool` | true/false | `true`, `false` |
| `Rune` | `Rune` | a single Unicode character | `'é'` |
| `Unit` | `Unit` | the type of "no return value" | `()` |
| `Nothing` | `Nothing` | the type with no values | the return of `exit(1)` |

**Note**: don't confuse the three "empties" — `Nothing` (no value at all), `Unit` (whose only value is `()`), and `None` (the Option family's "absent", chapter 14).

## 9.2 Three Bindings: let / var / const

**Definition**: three ways to bind a name to a value, in increasing mutability:

| Binding | Semantics | Use for |
|---|---|---|
| `let` | **immutable after creation** (the default) | the vast majority of declarations |
| `var` | reassignable (a privilege you opt into) | counters, accumulators, state |
| `const` | fixed at **compile time**, zero runtime cost | values that never change, like PI |

**Syntax**:

```cangjie
const PI = 3.14159

main() {
    let birthYear = 2000          // type inferred as Int64
    // birthYear = 2001          // ❌ cannot assign to immutable value

    var count = 0
    count += 1                  // compound assignment: count = count + 1
    println("count = ${count}")   // count = 1
    println("PI ≈ ${PI}")
}
```

**Notes**:

- `let` is a binding, not a "variable" — the *binding* is immutable; but if the bound **object** is a reference type (a class), its insides can still change (chapter 12);
- A `const` value must be computable at compile time (literals, other const expressions);
- When the compiler says "cannot assign to immutable value" → change `let` to `var`; conversely, if a `var` is never modified → change it back to `let` (lint will remind you).

## 9.3 The Integer Family and Bit Widths

**Definition**: integers come in widths — `Int64` (the 64-bit default), `Int32`, `Int8`… Bit width = storage size and value range. The 64-bit default is "the general choice least likely to overflow".

```cangjie
main() {
    let a: Int64 = 100          // 64-bit (default)
    let b: Int32 = 100        // 32-bit
    let c: UInt64 = 100    // non-negative
    println(a + Int64(b))        // different widths cannot be added directly: convert to Int64 explicitly (see 9.10)
}
```

**Notes**:

- `Int32`/`Float32` and the default-width types **cannot be mixed directly** (the official language does not auto-promote; it reports "invalid binary expression" — convert explicitly);
- `-1` as an unsigned number is a compile error (range check);
- The full suffix table: integers `i8/i16/i32/i64/u8/u16/u32/u64`, floats `f16/f32/f64`; **suffixes must be lowercase** (`42U8` is a syntax error).

## 9.4 The Float Family

**Definition**: decimals use floats — `Float64` (the default) and `Float32`. Floats are **approximations** (binary cannot represent every decimal exactly), so never compare floats with `==`.

```cangjie
import math.*
main() {
    let height: Float32 = 1.75f32
    let weight: Float32 = 65.5f32
    println(height * weight)        // same type (Float32 × Float32) computes directly

    // The right way to compare floats: an error margin
    let a = 0.1 + 0.2
    println(abs(a - 0.3) < 0.0001)   // true (abs lives in the math module)
}
```

**Notes**: float literals default to `Float64`; the suffixes `f32`/`f64` force the width; `abs` lives in the `math` module (`import math.*`).

## 9.5 Booleans

**Definition**: only two values — `true`, `false`. Conditions **must be** Boolean expressions (no plain numbers).

```cangjie
func isAdult(years: Int64): Bool { return years >= 18 }

main() {
    let adult = true
    println(adult && isAdult(18))   // true
    // if (1) { }                 // ❌ no plain numbers in conditions
}
```

**Notes**: the dialect aliases are `true`/`false`; **runtime output keeps the official format** — `println(true)` prints `true` (the dialect only transpiles code; it does not translate runtime output).

## 9.6 Characters and Strings

**Definition**: `Rune` = a single Unicode character (single quotes); `String` = an immutable sequence of Unicode characters (double quotes).

```cangjie
import std.collection.*
main() {
    let c = 'é'                    // one Rune — é takes 2 bytes in UTF-8
    println(c)                     // é
    println("café".size)           // 5 — a byte count, not a character count
    println("café"[0..3])          // caf (slices cut by bytes; index 3 lands just before é)
    println("café".runes() |> first()) // Some(c) — one Rune at a time
}
```

**Notes (two traps every beginner hits)**:

- **Trap 1**: `string[i]` returns a **byte** (UInt8), not a character — `"café"[4]` is é's *first byte* (195), not `'é'`. In a 3-bytes-per-character script such as Chinese or Japanese the trap bites even harder; iterate with `runes()`.
- **Trap 2**: the slice `s[start..end]` cuts by bytes — start and end must land on character boundaries, otherwise it **throws at runtime**;
- For per-character processing use `runes()` (a lazy iterator); for strings use `+` in small doses, and `collectString` for bulk (chapter 10).

## 9.7 Arrays and Tuples

**Definition**: `Array<T>`: fixed length, contiguous memory, O(1) indexing; a tuple `(T1, T2, ...)` packs **different types** into one value.

```cangjie
main() {
    // Array: fixed length
    let fixed = [10, 20, 30]
    println(fixed[1])              // 20
    let empty: Array<Int64> = []   // an empty array must be annotated

    // Tuple: mixed types allowed
    let student = (1, "Xiaoming", true)
    println(student[0])            // 1 (tuples are indexed with [i])
    let (id, name, active) = student   // destructuring: unpack in one go
    println(name)               // Xiaoming
}
```

**Notes**: arrays **cannot change length** (for dynamic add/remove use `ArrayList`, chapter 11); out-of-bounds indexing throws at runtime; `(1)` is a number, not a tuple. ⚠️ Tested (official 1.0.5): **the one-element tuple `(1,)` trailing-comma form fails to compile** (expects an expression) — to wrap a single value use a 1-element array `[1]`; tuples need at least two elements.

## 9.8 Ranges

**Definition**: `start..end` (half-open, end excluded) and `start..=end` (closed, end included) — the universal abstraction behind loops, slices, and membership tests.

```cangjie
import std.collection.*
main() {
    for (i in 1..5) { println(i) }     // 1 2 3 4 (half-open, end excluded)
    for (i in 1..=5) { println(i) }    // 1 2 3 4 5 (closed)
    println((1..10) |> contains(3))         // true (membership test; note the parentheses around the range)
}
```

**Notes**: ranges are ascending by default; `5..1` is an empty range (not an error); membership uses the pipe: `(1..10) |> contains(3)`.

## 9.9 Inference and Annotation

**Definition**: local variables can omit types — the compiler infers from the initializer. "Write like a dynamic language, check like a static one." **Omit where it can be inferred; write it where it matters.**

```cangjie
main() {
    let score = 90              // inferred as Int64
    let name = "Xiaoming"          // inferred as String
    let list = [1, 2, 3]       // inferred as Array<Int64>
    let age: Int32 = 12      // forced 32-bit (annotation required)
}
```

**Where annotation is mandatory**:

- Empty containers/arrays (`[]`, `ArrayList<Int64>()` cannot be inferred);
- A specific bit width is needed (`Int32`, `Float32`);
- **Function parameters** (no inference — parameters are part of the interface contract).

**Note**: when annotation and inference conflict, the annotation wins (`let x: Float64 = 1` is legal; the literal adapts to 1.0).

## 9.10 Conversion: Everything Explicit

**Definition**: Cangjie **never converts implicitly** — every conversion point must be written out. Implicit conversion is a breeding ground for bugs (what even is `"1" + 1`?); explicit conversions make every conversion point visible, controllable, and auditable.

**Syntax**:

```cangjie
import convert.*
main() {
    let score = 95
    println(score.toString())        // "95" (toString)

    let ratio: Float64 = Float64(score)       // Int64 → Float64 (constructor)
    let whole = Int64(3.9)                // 3 (truncates toward zero: Int64(-3.9) → -3)
    println(whole)

    println(Int64.parse("12"))         // 12 (parse returns Int64; invalid input throws — validate first for safety, chapter 14)
}
```

**Conversion reference**:

| Scenario | Form |
|---|---|
| Among numeric types | constructors: `Int64(x)`, `Float64(x)`, `Int32(x)` |
| Number → string | `score.toString()` (requires `import convert.*`) |
| String → number | `Int64.parse("42")` (invalid input throws — validate or catch first) |
| Type hierarchy | `as` — only for class hierarchies, **never** for numbers (chapter 12) |

**Notes**: `as` and the numeric constructors are two different things — `Int64(3.9)` is a numeric conversion; `(pet as Dog)` is a type-hierarchy conversion (chapter 12).

## ✳ Design Ideas

1. **Immutability by default (`let` first)**: mutability = accidental modification + concurrency races + hard-to-reason code. Making "immutable" the default turns `var` into a privilege you opt into — one glance at the `var`s shows where change can happen;
2. **Strong typing + full inference**: the best of both schools — the writing experience of a dynamic language with the safety of a static one. The rule: omit where inferable, write it where it matters (parameters, boundaries, contracts);
3. **Eliminate implicit conversion**: implicit conversions strip "type" of its meaning (the compiler doesn't know, the reader doesn't know, only the runtime finds out). Explicit conversion is the "catch errors at compile time" philosophy made concrete;
4. **Value types vs reference types** (expanded in chapter 12): value types have copy semantics (predictable, thread-safe); reference types have sharing semantics (efficient, polymorphic). The type's author decides the semantics, not the caller;
5. **Literal polymorphism**: `42` has no fixed type — it takes its type from context. But **variables** never convert implicitly: a literal is a value "without a past"; a variable has one.

## Exercises

1. Declare one `let` and one `var`, change the `var` to `let`, deliberately modify it, and read the diagnosis;
2. Write a type-mismatch assignment (`let x: Int64 = "text"`) and read the teaching hint and fix example;
3. Use `const` for PI and compute a circle's area; write one each of `Int32`/`UInt64`/`Float32` using suffixes;
4. Iterate your name with `runes()` printing each character; try `"café"[4]` and see which byte comes out;
5. Use a tuple + destructuring to return a student's (id, name, score) and print it.

## Summary

- Three bindings: `let` (default, immutable) / `var` (an opted-in privilege) / `const` (compile time);
- The type system: the integer family / float family / String / Bool / Rune / Unit / Nothing; suffixes are lowercase (i64/u64/f32/u8);
- Strings count and slice by **bytes** — use `runes()` for characters; arrays are fixed-length, tuples pack mixed types, ranges are half-open;
- Inference can omit annotations, but empty containers, specific widths, and parameters require them;
- All conversion is explicit: constructors (among numbers), `toString`/`parse` (string ↔ number), `as` (class hierarchy).

## Questions to Think About

1. Why is `let x: Float64 = 1` legal while `let x: Int64 = 1.5` is not? (Hint: literal polymorphism vs numeric truncation.)
2. What does the "string length is bytes" design protect? (Hint: files and networks deal with byte streams.)
3. If Cangjie allowed implicit `Int64 + String` conversion, what bugs would follow? (Give an example.)
4. What is the difference between `(1,)` and `(1)`? Why must a one-element tuple carry the comma?
