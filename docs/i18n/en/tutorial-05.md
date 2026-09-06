<!-- zhc-i18n 源: docs/中文仓颉程序设计/第1卷-启蒙与概念/05-判断.md 基线: f41c5de423f366d6 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第1卷-启蒙与概念/05-判断.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 5 The Computer Thinks: Decisions

> **What you will learn in this chapter**
> - Use `if` / `else if` / `else` to make the program "take a fork in the road";
> - Meet the comparison operators (`==`, `>`, `>=` …) and Booleans (`true`/`false`);
> - Learn to combine conditions (AND, OR, NOT).
>
> **After this chapter you can answer**: How does a chain of decisions execute, top to bottom? What is the difference between `=` and `==`? Can you put a plain number in a condition?

---

## 5.1 If … Then …

One of the computer's greatest powers is **making decisions**. The syntax reads like speech:

```cangjie
main() {
    let score = 85
    if (score >= 60) {
        println("You passed!")
    }
}
```

- `if (condition)`: **if the condition holds**, the code inside the braces runs;
- `>=` means "greater than or equal". The comparison operators are: `==` (equal), `!=` (not equal), `>` (greater), `<` (less), `>=` (greater or equal), `<=` (less or equal).

> Remember: comparing for equality takes **two** equal signs `==`. A single `=` means "put it in the box" (assignment); two equal signs mean "compare". This is one of the most common beginner mistakes — fortunately Cangjie reports it and stops you.

## 5.2 else if, else: Multi-Way Decisions

```cangjie
main() {
    let score = 85
    if (score >= 90) {
        println("Excellent!")
    } else if (score >= 60) {
        println("Pass")
    } else {
        println("Keep going — don't give up")
    }
}
```

Like a multiple-choice question: if the first condition fails, try the second; if none holds, take the `else`. **Top to bottom, only one road is taken** — whichever condition "holds" first wins, and everything after is ignored.

## 5.3 True and False

A decision has only two outcomes: `true` (it holds) and `false` (it doesn't). This is the `Bool` type from chapter 4:

```cangjie
main() {
    let raining = true
    if (raining) {
        println("Take an umbrella!")
    }
}
```

`true` and `false` can be stored in variables directly, and they can also be produced by comparisons: the "expression" `85 >= 60` evaluates to `true`. See — `if (score >= 60)` is really just asking: is the result of this comparison `true` or `false`?

> Note: you **cannot put a plain number in a condition**. `if (1)` is an error — the condition must be a real true/false decision. This eliminates the classic bug of writing assignment where comparison was meant (think about what `if (x = 1)` would do).

## 5.4 Combining Conditions: AND, OR, NOT

One condition not enough? Combine them with the logical operators:

```cangjie
main() {
    let age = 15
    let hasTicket = true
    if (age >= 12 && hasTicket) { println("You may enter") }
    if (age < 6 || age > 80) { println("Free entry") }
    if (!hasTicket) { println("Please buy a ticket") }
}
```

| Operator | Meaning | Example |
|---|---|---|
| `&&` | both conditions must hold (AND) | `raining && hasUmbrella` |
| `\|\|` | one condition is enough (OR) | `raining \|\| snowing` |
| `!` | negate it (NOT) | `!raining` = not raining |

> **A little secret (short-circuit)**: `false && anything` is immediately `false` — the computer doesn't even look at the right side; `true || anything` is immediately `true`. This guarantees a safe pattern: `list.size > 0 && list[0] > 1` — when the first condition fails, the out-of-bounds access on the right never executes (you will use this in chapter 11).

## 5.5 Hands-On Practice

1. Write a program: your height (say 155) — if it's over 150 print "You can ride the roller coaster", otherwise print "Grow a little more";
2. Grade scores: `>=90` excellent, `>=80` good, `>=60` pass, otherwise keep trying — use `else if`;
3. Think: of `if (5 > 3)` and `if (3 > 5)`, which one runs its body?
4. Challenge: write "amusement park rules" — age between 8 and 18 `&&` height over 130 to play; otherwise print the reason (hint: `age >= 8 && age <= 18`).

## ✳ A Thought on Programming: Decisions = Forks in the Road

`if` is where a program "thinks" for the first time — the code is no longer a straight line; it **takes forks**.

The idea behind it: **program = sequence + branching + loops**. Every program you have ever written is assembled from these three:

- **Sequence** (chapter 2): do things step by step;
- **Branching** (this chapter): choose a road based on the situation;
- **Loops** (chapter 6): repeat in circles.

**Any complex program, decomposed all the way down, is these three structures.** This is the famous "structured programming" idea of computer science — like Lego, which has only a few basic bricks yet builds everything. When you see a complex program, don't panic: find its sequence, its branches, its loops.

## 🍳 An Everyday Algorithm: The Grade Rater

A teacher grading a whole class is a classic multi-way decision:

```cangjie
main() {
    let score = 85
    if (score >= 90) {
        println("Excellent")
    } else if (score >= 80) {
        println("Good")
    } else if (score >= 60) {
        println("Pass")
    } else {
        println("Keep trying")
    }
}
```

Watch the **order** of the decisions: from high to low (90 → 80 → 60). If you wrote `if (score >= 60)` first, a score of 85 would never reach "Good" — the 60 condition holds first and the program walks away. **Branch order is priority** — the easiest trap in multi-way decisions.

> Try it: change the score to 95, 70, and 40, run once each, and see what each prints.

## Summary

- `if (condition) { ... }`: runs only when the condition holds;
- `else if`, `else`: multi-way decisions — **top to bottom, the first road that holds wins**;
- Comparison operators: `== != > < >= <=`; use `==` to compare, `=` only to assign;
- Booleans: `true`/`false`; conditions must be real Boolean decisions — no plain numbers;
- Combining: `&&` (both), `||` (either), `!` (negate);
- Branch order = priority: grade from the highest threshold downward.

## Questions to Think About

1. If the grader in 5.2 checked `score >= 60` first, what would 85 print? Why?
2. Does `if (score = 85)` produce an error? Try it — what does this protect you from?
3. Use `&&` to write a decision: if tomorrow it "rains && the temperature is below 10 degrees", remind yourself to take an umbrella and a coat;
4. Guess: are `!(age < 18)` and `age >= 18` the same thing? Why?
