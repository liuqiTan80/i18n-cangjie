<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/14-错误处理与并发.md 基线: 77e55c8c056ca586 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/14-错误处理与并发.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 14 Error Handling and Concurrency

> **What you will learn in this chapter**: master Cangjie's twin mechanisms for **eliminating null pointers** — the `Option` null-safety pattern and the `try`/`catch` exception system — plus an introduction to concurrency: `spawn` tasks, `synchronized` critical sections, locks, and atomic operations.
> **After this chapter you can answer**: Which scenarios belong to Options and which to exceptions? Why does reading a missing key crash? What happens when two tasks modify the same variable?

---

## 14.1 Definition: Null Safety — A World Without null

**Definition**: Cangjie **has no `null`/`null pointer`**. Nullability lives inside the type system — an `Option<T>` is either `Some(x)` or `None`. When a function returns `Option<T>`, the compiler **forces** you to handle "it might not be there" — the null-pointer bug moves from "runtime crash" forward to "compile-time error".

**Syntax**:

```cangjie
func findName(id: Int64): Option<String> {
    if (id == 1) {
        return Some("Xiaoming")        // Some: wrap a value
    }
    return None                   // None: "not there"
}

main() {
    match (findName(1)) {
        case Some(name) => println("found: ${name}")
        case None => println("not found")
    }
}
```

**Notes**:

- `None` can be assigned to any `Option<T>` (the type is inferred from context);
- An `Option` value **cannot be used as an ordinary value**: `findName(1) + "!"` is a compile error — you must unwrap first;
- Three ways to construct an `Option`: `Some(x)`, `None`, `x.isSome()`.

## 14.2 The Three Unwrappers: match / getOrDefault / getOrThrow

**Definition**: an `Option` is useless if you can't get the value out. Three common ways:

```cangjie
func findName(id: Int64): Option<String> {
    if (id == 1) { return Some("Xiaoming") }
    return None
}

main() {
    // ① match: safe branching (recommended; exhaustiveness-checked)
    match (findName(1)) {
        case Some(name) => println("found: ${name}")
        case None => println("no such person")
    }
    // ② getOrDefault: a fallback when None (the argument is a lambda)
    println(findName(1).getOrDefault({ => "anonymous" }))
    // ③ getOrThrow: only when you're certain; None throws
    println(findName(1).getOrThrow())
}
```

**Reference table**:

| Method | Semantics | When None |
|---|---|---|
| `match` | branch on both cases | takes the `None` branch (safest) |
| `getOrDefault({ => fallback })` | value if Some, fallback if None | returns the fallback |
| `getOrThrow()` | you are certain | throws (program crashes) |

**Notes**: `getOrDefault`'s argument is a **lambda** (`{ => 0 }`), not a plain value; "prefer matching, use throwing sparingly" — misusing `getOrThrow` turns null safety right back into null pointers.

## 14.3 Expected Failures Use Options (There Is No Result Type)

**Definition**: official 1.0.5 has **no** `Result` type — "possible failure" is uniformly expressed with `Option<T>`: success is `Some(value)`, failure is `None`.

**Syntax**:

```cangjie
import convert.*
import regex.*

func parseScore(text: String): Option<Int64> {
    if (Regex("^\\d+$").matches(text)) {   // anchored ^...$: the whole string must be digits
        return Some(Int64.parse(text))     // digits → success
    }
    return None                           // not digits → failure
}

main() {
    match (parseScore("95")) {
        case Some(score) => println("score: ${score}")
        case None => println("not a number")
    }
}
```

**Notes**: failure is part of the return value, and the caller **must** handle it — more "functional" than exceptions, suited to **expected failures** (bad formats, no such person, out of range); `Int64.parse` requires `import convert.*`; to carry a **failure reason**, return an `Option<String>` or put a custom enum inside `Some` (chapter 13).

> ⚠️ Tested reminder: `matches` is a **containment match** — `Regex("\\d+")` also returns true for `"a1"` (the substring `1` matched)! Validate-before-parse must anchor with `^\\d+$`, otherwise `"a1"` slips straight into `Int64.parse` and throws (chapter 10, question 4; appendix C pitfall).

## 14.4 Exceptions: Unexpected Errors Propagate Automatically

**Definition**: unforeseeable errors (division by zero, out of bounds, protocol errors) don't suit return-value propagation layer by layer — exceptions **propagate up the call stack automatically**, and whoever can handle them catches them.

**Four keywords**:

| Keyword | Role |
|---|---|
| `throw` | raise an exception deliberately; the function ends immediately |
| `try` | mark the protected zone |
| `catch` | intercept exceptions of the given type; the program continues |
| `finally` | the closing act that runs either way (close files, release locks) |

**Syntax**:

```cangjie
func divide(a: Int64, b: Int64): Int64 {
    if (b == 0) {
        throw Exception("divisor must not be zero")       // raise deliberately
    }
    return a / b
}

main() {
    try {
        let result = divide(10, 0)
        println("result: ${result}")
    } catch (e: Exception) {
        println("error: ${e.message}")   // intercept the exception
    } finally {
        println("runs either way")       // unconditional cleanup
    }
}
```

**Notes**:

- Common exception subclasses: `ArithmeticException`, `IndexOutOfBoundsException`, `ClassCastException`, `NullPointerException`, `IllegalArgumentException` — catch specific types as needed; `catch` matches the **first compatible type top-down** (subclasses before parents);
- The expression after `throw` has type `Nothing` — it may appear anywhere a value is expected;
- A `try` needs `catch` or `finally`; `finally` runs **after** `return`; don't put throwable code inside `finally`;
- **Don't use exceptions as ordinary control flow** (poor performance and readability) — see the division of labor in 14.5.

## 14.5 Options vs Exceptions: The Division of Labor

**Definition**: there is exactly one criterion — **is this failure "expected" or "unexpected"?**

| Scenario | Choice | Reason |
|---|---|---|
| Parsing user input (might not be a number) | `Option` | weird input is the **norm**; the caller must handle it |
| Table lookup (key might not exist) | `Option` | "no such person" is not a program error |
| Division by zero, out-of-bounds index | early check + exception backstop | good code shouldn't get here; getting here is a bug |
| Corrupt file, out of memory | exception | unexpected; the caller usually can't prevent it |

**Rule of thumb**: return an `Option` whenever you can; leave exceptions for "this should never fail — if it did, it's a program bug". `getOrThrow` is the declaration "I am certain there's a value; if not, it's a bug".

## 14.6 Assertions and Precondition Checks

**Definition**: the programmer's self-check — "this cannot fail here". The official `assert` works only inside test macros (`@Test`/`@Expect`, chapter 15); invariant checks in ordinary code use a hand-written `if` + `throw`.

**Syntax**:

```cangjie
func middle(list: Array<Int64>): Int64 {
    if (list.size == 0) {
        throw Exception("an empty list has no middle")    // precondition: validate before working
    }
    return list[list.size / 2]
}

func setAge(age: Int64): Int64 {
    if (age < 0 || age > 150) {
        throw Exception("invalid age: ${age}")
    }
    return age
}

main() {
    println(setAge(30))
    println(middle([1, 2, 3]))
    // println(setAge(-5))   // would throw
}
```

**Notes**: precondition checks catch **logic errors early** (far better than errors spreading into strange symptoms); but **don't use assertions for input validation** — user input deserves an `Option` or friendly exceptions; an assertion signals "the program itself is wrong".

## 14.7 exit (退出 / exit)

**Definition**: terminate the process immediately: `exit(statusCode)` — 0 for success, non-zero for failure. The status code tells the caller (a script/CI) whether it worked.

**Syntax**:

```cangjie
import env.*

main() {
    let config = readLine()
    if (config == "") {
        println("missing configuration")
        exit(1)              // fatal error: terminate with status 1
    }
    println("config: ${config}")
}
```

**Notes**: `exit` returns `Nothing` (it never returns); a `finally` block **does not** run after `exit` (the process terminates directly) — do any cleanup manually first; `exit` is the last resort for "cannot continue" — don't overuse it.

## 14.8 Concurrency Basics: spawn

**Definition**: launch a **concurrent task**: `spawn { task code }` — "run this code in another execution context" packaged as a function call.

**Syntax**:

```cangjie
main() {
    spawn { println("task one") }
    spawn { println("task two") }
    println("main")
}
```

**Notes**: output order is **not deterministic** (three tasks run concurrently; any of them may print first); `spawn` returns a task handle (you can wait for completion); **concurrently shared mutable data must be synchronized** (see 14.9/14.10) — the number-one source of concurrency bugs.

## 14.9 synchronized: The Critical Section

**Definition**: multiple tasks modifying the same `var` data cause a **data race** (half-written values, lost updates). `synchronized(lockObject) { critical section }` locks the code block — only one execution context may enter at a time.

**Syntax**:

```cangjie
import std.sync.{Mutex}

var count = 0

main() {
    let lockObject = Mutex()
    synchronized(lockObject) {
        count += 1        // critical section: only one task modifies at a time
    }
    println(count)
}
```

**Notes**:

- `synchronized` **requires a lock object argument** (tested on 1.0.5 — you cannot write `synchronized { }`);
- **Keep locks small**: the shorter the critical section the better; **never nest synchronized blocks** (deadlock risk);
- **Immutable data (`let`) needs no synchronization** — the concurrency dividend of "immutable by default".

## 14.10 Locks and Atomics

**Definition**: finer-grained concurrency primitives: `AtomicInt64`, `AtomicReference`, `AtomicBool`, `Mutex`. Atomic operations are lock-free "safe increments" — faster than synchronized blocks.

**Syntax**:

```cangjie
import std.sync.*

main() {
    // Atomic counter: safe increments across tasks
    let atomicCount = AtomicInt64(0)
    spawn { atomicCount.fetchAdd(1) }        // fetchAdd
    spawn { atomicCount.fetchAdd(1) }
    println("atomic count: ${atomicCount.load()}")   // load

    // Explicit lock usage: lock / unlock (always in pairs)
    let mutex = Mutex()
    mutex.lock()
    mutex.unlock()
}
```

**Notes (tested truths on 1.0.5)**:

- The dialect module path: `import std.sync.*`;
- Only the **integer atomics** support arithmetic (`fetchAdd`); `AtomicReference`/`AtomicBool` only have read/write and swap (`load`/`store`/`swap`);
- `AtomicReference` **accepts only reference types** (class objects) — passing value types like `String` is a compile error;
- Forgetting `unlock()` after `Mutex().lock()` deadlocks — guarantee unlocking with `try/finally` (`try { mutex.lock(); ... } finally { mutex.unlock() }`);
- The official `ReentrantMutex` is deprecated — use `Mutex` uniformly (it is reentrant itself).

## ✳ Design Ideas

**① Error handling is a "design decision", not "syntax"**: classify every failure scenario first — expected failures (input, lookups) go through `Option`; unexpected errors (bugs, environment) go through exceptions. This classification shapes the API — a good API makes "the right usage easy and the wrong usage impossible".

**② Fail fast**: `getOrThrow()` and `throw Exception("...")` both "say it out loud the moment something goes wrong" — the earlier an error surfaces, the easier the fix. Swallowing errors (`catch` that does nothing) is the most dangerous code there is.

**③ Precondition checks: good functions validate before working**: the first thing a function does is check its arguments (defensive programming).

**④ Immutability by default is a concurrency dividend**: data bound with `let` cannot be modified concurrently — no locks, no races. In concurrent programs prefer `let`; only truly shared mutable state needs `synchronized`/atomics.

**⑤ Minimize critical sections**: the smaller the locked range, the higher the concurrency. Move "read-only computation" out of the critical section and lock only the few lines that truly modify shared state.

## Exercises

1. Use an `Option` to implement "get an array element by index": return `None` on out-of-bounds instead of throwing;
2. Wrap an integer division in `try`/`catch` and print a friendly message on division by zero;
3. Write a `parseInt` function: valid input returns `Some(n)`, invalid input returns `None` (hint: use `Regex("^\\d+$").matches` to decide — anchor it, `\\d+` alone is a containment match);
4. Use `spawn` to launch 3 tasks each printing 1..3, observe whether the output order is deterministic, then wrap the printing in `synchronized(lock)` and watch the order change;
5. Think: why can't an `Option` value be directly `+ 1`? What is that design protecting you from?

## Summary

- `Option<T>` + `Some`/`None` eliminate null pointers; `match` handles exhaustively, `getOrDefault` falls back, `getOrThrow` asserts certainty;
- Expected failures use `Option` (officially there is no Result); unexpected errors use `try`/`catch`/`finally`/`throw`; never use exceptions as control flow;
- `exit(status)` terminates the process (`finally` won't run); precondition checks use hand-written `if` + `throw`;
- Concurrency: `spawn` launches tasks, `synchronized(lock)` protects critical sections, `AtomicInt64` counts lock-free; `AtomicReference` accepts only reference types;
- Runtime output keeps the official format (`true` → `true`).

## Questions to Think About

1. What is the difference between `getOrThrow()` and "dereferencing a null pointer directly"? In which scenario is it right? (Hint: fail fast.)
2. Why is "swallowing an exception" the most dangerous code? (Hint: the error is hidden.)
3. Two tasks run `count += 1` at the same time — what happens? Why is `synchronized` needed? (Hint: read-modify-write is three steps, not one atomic step.)
4. Why does `AtomicReference` accept only reference types? Why not a String? (Hint: value-type copy semantics conflict with atomic operations.)
