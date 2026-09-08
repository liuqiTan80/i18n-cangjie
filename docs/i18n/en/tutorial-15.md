<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/15-泛型接口与宏.md 基线: dcaca5575eb38ebc 时间: 2026-09-08-->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/15-泛型接口与宏.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 15 Generics, Interfaces, and Macros

> **What you will learn in this chapter**: master the two mechanisms for "writing generic code" — generics (type parameterization + constraints) and macros (compile-time code transformation); write unit tests with `@Test`/`@Expect`, and observe macro expansion with `zhc expand`.
> **After this chapter you can answer**: What problems do generics and macros each solve? How do `$(...)` and `${...}` differ? Why is compilation two-step?

---

## 15.1 Generic Functions: One Function, Every Type

**Definition**: generics = **type parameterization** — write one function that works for any type (no copying per type). `<T>` is the type parameter, instantiated automatically at call time.

**Syntax**:

```cangjie
func firstOf<T>(list: Array<T>): T {
    return list[0]
}

main() {
    println(firstOf([1, 2, 3]))          // 1 (T inferred as Int64)
    println(firstOf(["a", "b"]))       // a (T inferred as String)
}
```

**Notes**:

- The type parameter goes after the function name, `<T>`; **capitalized** is the convention (`T`, `K`, `V`);
- At call sites you usually omit the type argument — the compiler **infers** it from the arguments (`firstOf([1,2,3])`);
- Generics are a **compile-time** mechanism: at runtime there are no generics (one copy of the code per concrete type) — zero runtime overhead.

## 15.2 Generic Types: The Foundation of Containers

**Definition**: generics aren't just for functions — **types** can be parameterized too: `ArrayList<T>`, `HashMap<K, V>`, `Option<T>` are all generic types. You've been using them already!

**Syntax**:

```cangjie
import std.collection.{ArrayList}

struct Box<T> {
    public var content: T
    init(content: T) { this.content = content }
}

main() {
    let intBox = Box<Int64>(42)
    let textBox = Box<String>("Cangjie")
    println(intBox.content)    // 42
    println(textBox.content)    // Cangjie

    var roster = ArrayList<String>()
    roster.add("A")
    println(roster[0])        // A
}
```

**Notes**: empty containers **must declare their type argument** (`ArrayList<String>()` — without it the compiler can't know what goes inside).

## 15.3 Constraints: The Boundaries of Generics

**Definition**: unbounded generics are too free — calling `.compare` on a `<T>` won't compile (T could be anything). A **constraint** states what T must satisfy: `where T <: Comparable<T>`.

**Syntax**:

```cangjie
func maxOf<T>(list: Array<T>): T where T <: Comparable<T> {
    var largest = list[0]
    for (item in list) {
        if (item > largest) { largest = item }
    }
    return largest
}

main() {
    println(maxOf([3, 7, 2, 9]))          // 9
    println(maxOf(["a", "b", "c"]))    // c (strings are comparable too)
}
```

**Notes**:

- `where T <: Comparable<T>` — T must be a type implementing the `Comparable` interface; **a generic interface used as a constraint carries its type argument** (write `Comparable<T>`, not bare `Comparable`);
- The constraint goes **after the return type, before the body**: `func name<T>(params): ReturnType where T <: Comparable { ... }` — return type first;
- An unconstrained generic can only "store and retrieve" — to call methods you need a constraint (a constraint is a "capability list": the interface idea of chapter 12 extended into generics).

> 💡 Tested tip: the constraint clause looks like `where T <: Comparable<T>`; `Comparable` must be written in the `Comparable<T>` form for the constraint to take effect and permit the `>` comparison operators.

## 15.4 What Is a Macro: A Compile-Time Code Transformer

**Definition**: a macro is a **compile-time code transformer** — it eats code tokens and produces code tokens. Calls are written `@macroName(args)`. Ordinary functions operate on **values** (runtime); macros operate on **code itself** (compile time).

**Three things macros can do that functions cannot**:

1. **Rebuild syntax sugar**: package repeated patterns (logging, timing) into a macro call;
2. **Compile-time validation**: verify patterns at compile time (e.g. DSL syntax checking);
3. **Performance**: expansion completes at compile time — **zero runtime overhead**.

**Notes**: Cangjie's macros are **hygienic** (they won't accidentally capture the caller's variables) and **typed** (inputs and outputs are code token streams) — far safer than C preprocessor text substitution; macro calls start with `@`; macro names may be any identifier (including non-ASCII); macro expansion errors are reported at compile time.

## 15.5 Macro Packages and Macro Definitions

> ⚠️ **The only official-syntax zone in this book**: macro package source code (the `macro package` code in this section and 15.6-15.8) **must be written in official Cangjie syntax** — macro package `.cj` files are not dialect-transpiled; this is a hard constraint of the Cangjie compiler, and the English words there (`macro package`/`import`/`Tokens`) are not oversights. **Dialect-side (`.zc`) code remains fully in your mother tongue throughout the book** — the macro package is the single exception.

**Definition**: macros must be defined in a **macro package** — the **first line** is `macro package <name>`. A macro package exposes only macros. Inside, write **official Cangjie syntax** (`.cj` files are not dialect-transpiled).

**Syntax** (macro package file `define/define.cj`):

```cangjie
// define/define.cj — macro package source (official Cangjie syntax; not dialect-transpiled)
macro package define
import std.ast.*

public macro DebugLog(input: Tokens): Tokens {
    let name = input.toString()
    return quote(
        println($(name))
    )
}
```

**Essentials (Cangjie 1.0 macro rules, tested on 1.0.5)**:

- First line `macro package <name>` (**official syntax** — macro `.cj` files are not dialect-transpiled; writing dialect words there fails to compile);
- `import std.ast.*` is required — the `Tokens` type comes from `std.ast` (there is no `std.macro`);
- `public macro name(input: Tokens): Tokens` — both parameter and return must be `Tokens`; macro names may be any identifier (including non-ASCII);
- A macro package is an **independent compilation unit**: it is compiled into a macro library first, and expanded while the main program compiles — macros can be distributed across projects.

## 15.6 quote and Interpolation: Writing Code by Writing Code

**Definition**: `quote(...)` lets you **write code by writing code**; `$(expression)` is **interpolation at the code position** — embedding variable values or sub-code tokens into the template.

**The two interpolations have completely different effects**:

| Form | Effect | Example |
|---|---|---|
| `$(input.toString())` | inserts a **string literal** | `println("x + 1")` — prints the expression's **text** |
| `$(input)` | embeds the **code tokens** directly | `if ($(input) == 0)` — stays an **expression** |

**Notes**: `$()` only works at **code positions** — inside string literals nothing is substituted; `$(input.toString())` inserted into a string literal also does not substitute — interpolation happens only at code positions. Keep them apart: **`$()` is code interpolation (macros), `${}` is string interpolation (chapter 10)** — two different things.

## 15.7 Two-Step Compilation and zhc expand

**Definition**: macro package and main program compile in two steps — the build-time face of the macro package's "independent compilation unit" design.

**The two-step flow (tested on 1.0.5)**:

```bash
zhc eject main.en                           # ① dialect → official source (main.cj)
cjc define/define.cj --compile-macro       # ② compile the macro package → define.cjo + lib-macro_define.so
cjc main.cj -o main                        # ③ compile the main program (import define.* expands macros automatically)
./main                                     # run
```

> Tested (1.0.5): `zhc run` **does not support** macro packages — for everyday expansion checks use `zhc expand main.en --macro-pkg define/` (which performs the two-step compilation for you, see 15.8), or compile manually with the three commands above.

## 15.8 The Macro Expansion Teaching View: zhc expand

**Definition**: `zhc expand` shows the before/after comparison (official view + reverse mother-tongue view, with positions mapped back to dialect coordinates) — the best tool for learning macro behavior: **guess the expansion first, then verify in the view**.

**Usage** (run it inside `zhc/examples/macro-demo/`, which ships both the
Chinese-dialect `hello.zc` and its English-dialect twin `hello.en`):

```bash
zhc expand hello.en --macro-pkg define
```

```
=== zhc expand: macro expansion teaching view ===
macro pack: define (define)

[before expansion] hello.en:6
      @dprint(x + y)
[after expansion] official (main.cj)
      /* 6.1 */print("x + y" + " = ")
      /* 6.2 */println(x + y)

[after expansion] dialect (reverse-translated)
      /* 6.1 */print("x + y" + " = ")
      /* 6.2 */println(x + y)
```

With the `en` pack (an identity mapping), the reverse-translated view equals
the official view. Run `zhc expand hello.zc --macro-pkg define` instead to see
the teaching view in a real mother-tongue dialect: keywords come back restored
from the Chinese pack, and the line-number comments (`/* 6.1 */`) still
correspond to **dialect source coordinates**.

**Notes**: the line-number comments (`/* 6.1 */`) correspond to **dialect source coordinates**; error positions after macro expansion are mapped back to the macro call site through the source map.

## 15.9 Derive Macros: Auto-Generating Boilerplate

**Definition**: annotate a type with `@Derive(Equals, Comparable)` and the compiler generates `equals`/`compare`/`hash` methods automatically — these struct implementations are **mechanically repetitive** (field-by-field comparison); hand-writing them is smelly and error-prone. The derive macro is "convention over configuration" exemplified.

**Syntax**:

```cangjie
// syntax sketch (@Derive is a system macro; the macro library must be compiled first)
struct Student @Derive(Equals) {
    public var name: String
}
```

**Notes**: the derive precondition — field types must support the derived operation (deriving `Comparable` requires all fields comparable); a derive macro and a hand-written implementation are **either/or** (both together is a conflict); derive macros require the macro library to be compiled first (two-step compilation).

## 15.10 System Macros: @Test and @Expect

**Definition**: the Cangjie standard library ships a testing framework (`std.unittest`) — `@Test` marks test functions, `@Expect` asserts.

**Syntax**:

```cangjie
import std.unittest.testmacro.*
import std.unittest.*

func add(a: Int64, b: Int64): Int64 { return a + b }

@Test
public func addWorks() {
    @Expect(add(2, 3), 5)   // expect the expression's result to be 5
}
```

**Essentials (tested on 1.0.5)**:

- **Both wildcard imports are required**: `std.unittest.testmacro` (the test framework's macros themselves) and `std.unittest` (assertions and other runtime types) — neither can be omitted;
- `@Expect(actual, expected)` expands into a full assertion, reporting both sides on failure;
- Functions marked `@Test` are collected and executed by the framework automatically — no manual invocation.

One command runs all dialect tests from the project root:

```bash
zhc test
```

```
[ PASSED ] CASE: addWorks
Summary: TOTAL: 1
    PASSED: 1, SKIPPED: 0, ERROR: 0
    FAILED: 0
```

## ✳ Design Ideas

**① The timing of metaprogramming: functions first, generics second, macros last**. 90% of "duplicated code" dissolves with functions/generics; only when you need to **operate on code itself** (grab an expression's text, generate syntax structures) do macros come into play. Macros are the last resort, not the first choice — they trade readability for expressive power.

**② Compile time vs runtime**: macros hoist "repetitive work done on every run" into "done once at compile time" — zero runtime overhead. Whatever can be decided at compile time should never wait for runtime; a macro crash = a compile error (a good thing) — errors surface at the earliest possible moment.

**③ Constraints are contracts**: `where T <: Comparable` is the generic's "capability list" — which methods generic code may call is decided by the constraint. This is the same idea as interfaces (chapter 12) seen from the other side: **program against abstractions, keep boundaries explicit**.

**④ Convention over configuration**: one line of `@Derive(Equals)` replaces dozens of hand-written boilerplate lines — "if a machine can generate it mechanically, don't make a human write it"; `@Test`/`@Expect` make testing zero-friction.

## Exercises

1. Write a generic function `swap<T>(a: T, b: T): (T, T)` returning the swapped tuple; call it with integers and with strings;
2. Write a generic `indexOf<T>(list: Array<T>, target: T) where T <: Equals` — return the index if found, -1 otherwise;
3. Write a `@PrintExpr` macro that expands to `println("<expression text> = " + <expression value>)` (hint: use `$(input.toString())` and `$(input)` once each);
4. Use `zhc expand` to inspect your macro's expansion view and confirm the position mapping;
5. Derive `Equals` for `struct Student` and verify that two field-identical instances compare `==` as true.

## Summary

- Generics: `func name<T>(...)` / `Type<T>`; type arguments inferred at call sites; `where T <: Comparable` bounds capabilities;
- Macro packages start with `macro package <name>` (official syntax + `import std.ast.*`); macro signatures are `(Tokens) -> Tokens`; calls are `@macroName(...)`; macro names may be any identifier;
- Two-step compilation: `cjc macro-package --compile-macro` → `cjc main-program`; `zhc run` does not support macro packages — verify with `zhc expand --macro-pkg`;
- `quote()` constructs code; `$(...)` interpolates only at **code positions** (`$(input)` embeds code, `$(input.toString())` inserts text) — distinct from string interpolation `${...}`;
- `@Derive(Equals)` auto-generates boilerplate; `@Test`/`@Expect` are the built-in test framework (both imports required).

## Questions to Think About

1. Generics and macros both "eliminate duplication" — what is the difference between them? (Hint: types vs code itself.)
2. Why can't macros do IO (read files, access the network)? What property of the build does that protect? (Hint: reproducible builds.)
3. What do `$(input)` and `$(input.toString())` each expand into? Why is `0.."3"` a type error? (Hint: tokens vs string literals.)
4. Why does `@Test` need two imports (`std.unittest.testmacro` and `std.unittest`)? (Hint: the macros themselves vs the runtime types.)
