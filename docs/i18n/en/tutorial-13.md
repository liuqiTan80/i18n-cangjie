<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/13-枚举与模式匹配.md 基线: c784f342d9b0e2da 时间: 2026-09-06 -->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/13-枚举与模式匹配.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 13 Enums and Pattern Matching

> **What you will learn in this chapter**: master enums (a finite set of values + carried data) and pattern matching (exhaustiveness checking, destructuring, guards), and understand why "match is safer than an if-chain".
> **After this chapter you can answer**: What is the core value of an enum? What happens if one `case` is missing? How is `match` different from an `if` chain?

---

## 13.1 Definition: What Is an Enum

**Definition**: an `enum` = a **finite set of values** — list "all possible situations". Far safer than "magic numbers": the compiler's exhaustiveness check guarantees every value gets handled.

**Syntax**:

```cangjie
enum Direction { Up | Down | Left | Right }

main() {
    let facing = Direction.Up
    match (facing) {
        case Direction.Up => println("up")
        case Direction.Down => println("down")
        case Direction.Left => println("left")
        case Direction.Right => println("right")
    }
}
```

**Notes**:

- Values are written `EnumName.member` (`Direction.Up`);
- Members are separated by `|`;
- Matching an enum is **forced exhaustive** (unless a `_` fallback exists) — a missing branch is a compile error. That is the enum's core value.

## 13.2 Carrying Data: Tagged Unions

**Definition**: enum members can also **carry data** — each shape carries its own payload, the classic modeling of "data with multiple shapes" (officially a tagged union).

**Syntax**:

```cangjie
enum Message {
    Text(String) | Number(Int64) | End
}

main() {
    let content = Message.Text("hello")
    match (content) {
        case Message.Text(text) => println("text: ${text}")
        case Message.Number(n) => println("number: ${n}")
        case Message.End => println("end")
    }
}
```

**Notes**: data-carrying members look like constructors (`Message.Text("hello")`); when matching, `case Message.Text(text)` **tests and destructures at once** — pulling the data out.

## 13.3 match: Pattern Matching + Exhaustiveness Checking

**Definition**: `match (value) { case pattern => ... }` — a more structured branch than an `if` chain. An `if` chain is "manually managed branching" — forget an `else` and the compiler says nothing, and at runtime the program quietly takes the wrong path; **exhaustiveness checking** turns "branch completeness" into a **compile error**.

**Syntax**:

```cangjie
func weekdayName(n: Int64): String {
    match (n) {
        case 1 => return "Monday"
        case 2 => return "Tuesday"
        case 3 => return "Wednesday"
        case _ => return "unknown"     // the _ wildcard: matches anything
    }
}

main() {
    for (i in 1..4) {              // 1..4 is a half-open range: 1, 2, 3
        println("day ${i}: ${weekdayName(i)}")
    }
}
```

**Notes**:

- The `_` wildcard matches any value — integers have no exhaustiveness checking, so a fallback is mandatory;
- `match` is an **expression** (it has a value): `let description = match (direction) { ... }`;
- Matching enums/options/tuples must be exhaustive (or end with `_`) — the compiler checks "are all cases handled" for you.

## 13.4 Tuple Patterns: Test + Destructure at Once

**Definition**: matching a tuple takes it apart by shape — (0, 0) the origin, (x, 0) the x-axis… every pattern performs the test and the destructuring in one step.

**Syntax**:

```cangjie
main() {
    let point = (3, 4)
    match (point) {
        case (0, 0) => println("origin")
        case (x, 0) => println("on the x-axis: ${x}")
        case (0, y) => println("on the y-axis: ${y}")
        case (x, y) => println("an ordinary point (${x}, ${y})")
    }
}
```

**Notes**: the `x` and `y` in a pattern are **newly bound names** (automatic destructuring), not the variables outside; tuple pattern exhaustiveness is checked by the compiler (the 4 branches above cover every possibility).

## 13.5 Match Guards: Shape + Condition

**Definition**: `case pattern where (condition)` — "shape match + condition filter" in two steps.

**Syntax**:

```cangjie
main() {
    let score = 95
    match (score) {
        case x where (x >= 90) => println("Excellent")
        case x where (x >= 60) => println("Pass")
        case _ => println("Keep trying")
    }
}
```

**Notes**: the `x` in a guard is the matched value (here the score itself); when a guard condition is false, the next branch is tried; integer matches require a `_` fallback.

## 13.6 Practicum: Rewriting an "If Chain" as a "Match"

Compare the two styles on the same logic ("grade rating"):

```cangjie
// Style 1: if chain (imperative)
func rate1(score: Int64): String {
    if (score >= 90) { return "Excellent" }
    else if (score >= 60) { return "Pass" }
    return "Keep trying"
}

// Style 2: match with guards (declarative)
func rate2(score: Int64): String {
    match (score) {
        case x where (x >= 90) => return "Excellent"
        case x where (x >= 60) => return "Pass"
        case _ => return "Keep trying"
    }
}

main() {
    println(rate1(95))    // Excellent
    println(rate2(95))    // Excellent
}
```

**Notes**: the two are equivalent — `match`'s advantage shows in **pattern** scenarios (enums, tuples, destructuring). When branching is not just "compare sizes" but "distinguish by shape", match is the only clean answer.

## ✳ Design Ideas

**① Exhaustiveness checking: turning "a missing branch" into a compile error**. A missing branch in an `if` chain = quietly taking the wrong path at runtime; a missing branch in a `match` = a loud compile error. Add a new enum member and every match point becomes a compile error — **forcing you to handle the new situation** (a safety net for extensibility).

**② Model with types, not numbers**: `Direction.Up` is safer than the number `1` — the compiler can check it, the code documents itself, and a wrong type is an immediate error. "Magic numbers" are a code smell; enums are the antidote.

**③ Expressions have values**: `match` is an expression — "every branch must yield a value" eliminates "forgot to initialize" at the source; functional style seeps into imperative structure.

**④ Match the shape first, then the condition**: patterns answer "what is it", guards answer "does it qualify" — separating the two makes every branch's intent clear.

## Exercises

1. Define `enum Weather { Sunny | Rainy | Snowy }` and write `whatToBring(w: Weather): String` returning advice (Sunny → sunscreen, Rainy → umbrella, Snowy → warm coat) — then **deliberately delete one branch** and observe the exhaustiveness error;
2. Define `enum Shape { Circle(Float64) | Rectangle(Float64, Float64) }` and write an `area()` function that computes each with a match;
3. Rewrite the "amusement park rules" (age 8-18 && height 130+) as a multi-branch version using `match` + guards;
4. Challenge: use a tuple pattern to "decide which quadrant a point is in": `(pos, pos)` quadrant 1, `(neg, pos)` quadrant 2… hint: `case (x, y) where (x > 0 && y > 0)`.

## Summary

- `enum Name { member1 | member2 }`; values via `EnumName.member`; members can **carry data**;
- `match (value) { case pattern => ... }`: pattern matching + exhaustiveness checking (enums/options/tuples must be exhaustive or end with `_`);
- Tuple patterns `case (x, 0) =>`: test + destructure at once; guards `case x where (cond)`: shape + condition;
- The `_` wildcard as fallback; `match` is an expression (it has a value);
- Core value: a missing branch goes from "a runtime bug" to "a compile-time error".

## Questions to Think About

1. Why does a missing enum branch fail compilation while an integer match needs a `_` fallback? (Hint: the compiler knows all of an enum's values but not an integer's.)
2. Where does the `text` in `case Message.Text(text)` come from? (Hint: destructuring.)
3. Why are "magic numbers" a smell? What does replacing the numbers 1/2/3 with an enum buy you?
4. The guard `case x where (x >= 90)` is essentially the same as `if (score >= 90)` — so where does match's "extra value" lie? (Hint: patterns, destructuring, exhaustiveness.)
