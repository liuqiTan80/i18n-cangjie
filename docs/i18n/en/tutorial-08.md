<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/08-函数深入.md 基线: 549ee8440629a748 时间: 2026-09-06 -->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/08-函数深入.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 8 Functions in Depth

> **What you will learn in this chapter**: use functions to their full potential — return details, multiple return values, named parameters, overloading, lambdas, and closures.
> **After this chapter you can answer**: Why must parameters be typed? How do lambdas relate to ordinary functions? What does a "closure" capture?

---

## 8.1 Definition: The Full Syntax of a Function

**Definition**: a reusable, named, callable block of code. The complete form:

```
func name(param1: Type, param2: Type): ReturnType {
    function body
    ...
    return result
}
```

**Syntax essentials**:

| Part | Form | Notes |
|---|---|---|
| Keyword | `func` | the reserved word for declaring a function |
| Entry | `main()` | **without** the `func` prefix — `func main` is a syntax error (the entry is already called `main`; no need to declare it a "function" again) |
| Parameters | `(score: Int64)` | **types must be explicit** (no inference) — parameters are the interface contract |
| Return type | `: String` | omit when there is no return value (implicitly returns `Unit`) |
| Return value | `return value` | hands over the result and **immediately ends** the function |

**Examples**:

```cangjie
func double(n: Int64): Int64 {
    return n * 2
}

func area(width: Float64, height: Float64): Float64 {
    return width * height
}

main() {
    println(double(21))          // 42
    println(area(3.0, 4.0))      // 12.0
}
```

**Notes**:

- Parameters are **read-only bindings** — you cannot reassign a parameter;
- Once you declare `: String`, **every path** must return — miss one and the compiler reports "function lacks a return";
- Function names use the "verb + object" style (`computeTotal`, `readFile`).

## 8.2 Returns and Early Returns

**Definition**: `return value` hands over the result and ends the function immediately; the value of the body's **last expression** is also automatically the return value (the trailing expression) — but an explicit `return` is recommended for clarity.

```cangjie
func absolute(n: Int64): Int64 {
    if (n < 0) {
        return -n        // early return: negatives end right here
    }
    return n             // reaching this line means n >= 0
}

main() {
    println(absolute(-5))   // 5
    println(absolute(3))    // 3
}
```

**Notes**:

- No statements may follow a `return` (unreachable-code warning);
- **The fallback return** is the idiomatic pattern: earlier `return`s end the function immediately, so the last `return` needs no `else` around it;
- Functions with no return value can omit `return`.

## 8.3 Multiple Return Values: Tuples + Destructuring

**Definition**: a function returns only one value — but it can be a **tuple** packing several. The caller uses **destructuring** to unpack them in one go.

```cangjie
func extremes(list: Array<Int64>): (Int64, Int64) {
    return (list[0], list[list.size - 1])
}

main() {
    let (smallest, largest) = extremes([3, 7, 2, 9])
    println("min ${smallest} max ${largest}")   // min 3 max 9
}
```

**Notes**:

- Tuples are accessed with `[index]` (`student[0]`), destructured with `let (a, b) = tuple`;
- `(1)` is an ordinary number, not a tuple — a one-element tuple must be written `(1,)`;
- Beyond 12 elements, consider a struct/class (chapter 12).

## 8.4 Named Parameters: No Fear of Wrong Order

**Definition**: with many parameters, positional passing invites order mistakes. Add `!` after a parameter name at declaration, and pass `name: value` at the call site.

**Syntax**:

```cangjie
func configure(age: Int64, name!: String, className!: String) {
    println("${name}, ${age} years old, ${className}")
}

main() {
    configure(12, name: "Xiaoming", className: "Class 2-1")
}
```

**Notes**:

- **Unnamed parameters must come first** (`configure(12, ...)`); named parameters follow;
- A misspelled parameter name reports "parameter not found";
- Named parameters make interfaces **self-documenting** — the call site shows "this name gets this value" directly.

## 8.5 Overloading: One Name, Several Meanings

**Definition**: same-named functions with **different parameters** (count or type); the compiler picks a version from the arguments.

```cangjie
func describe(x: Int64): String { return "integer: ${x}" }
func describe(x: String): String { return "text: ${x}" }

main() {
    println(describe(1))        // integer: 1
    println(describe("hi"))     // text: hi
}
```

**Notes**:

- **Differing only in return type is not overloading** (it conflicts);
- When overload resolution is ambiguous, the compiler prefers the exact match.

## 8.6 Lambdas: Functions Without Names

**Definition**: a function literal — `{ x => x * 2 }`: braces wrap the whole thing, `parameters => expression`. Lambdas are **first-class citizens**: assignable, passable, returnable.

```cangjie
import std.collection.*
func applyTwice(f: (Int64) -> Int64, x: Int64): Int64 {
    return f(f(x))
}

main() {
    let double = { x => x * 2 }
    println(applyTwice(double, 3))      // 12 (functions can be assigned and passed)

    var roster = ArrayList<Int64>()
    roster.add(1); roster.add(2); roster.add(3)
    let doubled = roster |> map({ x => x * 2 }) |> collectArray
    println(doubled)                   // [2, 4, 6]
}
```

**Notes**:

- Multiple parameters: `{ x, y => x + y }`;
- Lambda parameter types are usually inferred from context;
- Function types are written `(Int64) -> Int64`;
- `\x => ...` is other languages' syntax — Cangjie does **not** accept it.

## 8.7 Closures: Functions That Remember

**Definition**: a lambda can **capture** variables from the scope where it was defined — the function "remembers" its birth environment even after that variable has left its original scope.

```cangjie
func makeAdder(increment: Int64): (Int64) -> Int64 {
    return { x => x + increment }       // captures increment
}

main() {
    let add5 = makeAdder(5)
    println(add5(10))              // 15
}
```

**Notes**:

- What is captured is **the variable itself** (not a snapshot) — if the captured variable changes before the lambda runs, the lambda sees the new value;
- A closure is the combination "function + environment" — the bedrock of callbacks and event handling.

## 8.8 Default Parameters: Callable Even When Omitted

**Definition**: a parameter declared with a default value can be omitted at the call site — the official 1.0.5 form is `param: Type = default`. **Tested: the zhc dialect checker does not yet support this form** (it reports "expected `,`, got `)`"), so while teaching we achieve the same effect with **overloading** (when you later write official Cangjie, defaults switch over naturally):

```cangjie
func greet(): String {
    return greet("friend")      // overload: the no-arg version reuses the one-arg version
}

func greet(name: String): String {
    return "Hello, ${name}!"
}

main() {
    println(greet())           // Hello, friend! (the default value)
    println(greet("Xiaoming"))     // Hello, Xiaoming!
}
```

**Notes**:

- Official default parameters go at the **end** of the parameter list (no required parameter may follow one with a default); overloads are distinguished by count/type — make sure the two versions aren't ambiguous;
- It combines nicely with named parameters (`!`).

## ✳ Design Ideas

1. **Explicit interface contracts**: function parameters must be typed — every detail of the interface is out in the open, and the caller and the compiler read the same contract;
2. **First-class functions**: functions can be passed around like values (lambdas) — the foundation of functional style (`map`/`filter`, chapter 11);
3. **Closures are deferred execution**: `makeAdder(5)` does not compute a result immediately — it stores "the recipe for the computation" until called. "Store an action, execute it later" is the prototype of every asynchronous design: callbacks, timers, and beyond;
4. **Less is more**: overloading, named parameters, and default parameters all serve one goal — **readable call sites**. The first principle of interface design: the caller's experience comes first.

## Exercises

1. Write a `factorial` function (recursion or loop), then one returning `(quotient, remainder)` and receive it via destructuring;
2. Use a lambda + `map` to add 10 to every element of an `ArrayList<Int64>` and collect into an array;
3. Write a closure factory `multiplierOf(factor: Int64): (Int64) -> Int64` that produces "×2" and "×3" functions, and call each once;
4. Rewrite "rate" as an **overloaded** version: `func rate(): String` (internally calling `rate(60)`) + `func rate(score: Int64): String`, calling each with 0 and 1 arguments;
5. Think: can both overloading and default parameters "pass fewer arguments"? When is overloading mandatory? (Hint: when the parameter **types** differ.)

## Summary

- `func name(param: Type): Type { return ... }`; parameters must be typed and are read-only; every path must return;
- Multiple return values = a tuple + destructuring, `let (a, b) = ...`;
- Named parameters: add `!` at declaration, pass `name: value` at the call; unnamed parameters come first;
- Overloads are distinguished by parameters (count/type); differing only in return type does not count;
- The lambda `{ x => x * 2 }` is a first-class citizen; closures capture their defining environment; "callable even when omitted" is done via overloading (official default parameters `= default` go at the end; zhc does not support them yet).

## Questions to Think About

1. Why must function parameters be typed while local variables can be inferred? (Hint: interface contract vs implementation detail.)
2. The lambda returned by `makeAdder` can still use `increment` after the function ended — why hasn't it vanished? (Hint: closure capture.)
3. Why does overload resolution pick the integer version of `describe(1)` over the string version? (Hint: exact match.)
4. Can you use `return` inside a lambda? Try it — and think about how a lambda's "return" relates to a function's "return".
