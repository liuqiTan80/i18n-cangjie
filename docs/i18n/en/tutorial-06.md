<!-- zhc-i18n 源: docs/中文仓颉程序设计/第1卷-启蒙与概念/06-循环.md 基线: 3ba2d2589f14369c 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第1卷-启蒙与概念/06-循环.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 6 Doing the Work Repeatedly: Loops

> **What you will learn in this chapter**
> - Use `for` to repeat work a counted number of times;
> - Use `while` to keep going until a condition fails;
> - Control loops with `break` and `continue`.
>
> **After this chapter you can answer**: Does `1..5` include 5? How do you stop an infinite loop? How did Gauss add 1 to 100 in seconds?

---

## 6.1 Hand Repetition to the Computer

Make the computer add 1 to 100? Write 100 lines by hand? **Loops** exist for exactly this — running the same code over and over. Computers excel at repetitive work: they never tire, never get bored, never miscount.

## 6.2 for: Counting Your Way Through

```cangjie
main() {
    for (i in 1..5) {
        println("round ${i}")
    }
}
```

- `1..5` is a **range**: from 1 up to 5 (note: it stops at 5 — **5 is not included**);
- `for (i in 1..5)`: `i` becomes 1, 2, 3, 4 in turn, and the code inside the braces runs once for each;
- Output: `round 1`, `round 2`, `round 3`, `round 4` (no round 5!).

> Ranges also have a closed form, `1..=5` (5 included). The "half-open interval `1..5`" is the mainstream convention in programming, because its length is exactly `5 - 1` — no ambiguity.

### A Legend: Gauss Adds 1 to 100 in Seconds

When the mathematician Gauss was 8, his teacher asked the class to add 1 to 100. While the other kids ground away, Gauss finished in seconds — he noticed `1+100=101`, `2+99=101`… 50 pairs in total, so the answer is `50 × 101 = 5050`.

Let's write it with a loop — Gauss used cleverness, we use brute force (and the computer doesn't mind brute force):

```cangjie
main() {
    var total = 0
    for (i in 1..101) {
        total = total + i
    }
    println("1 plus 2 … plus 100 equals ${total}")
}
```

Output: `1 plus 2 … plus 100 equals 5050`. Look at the "soul" of this program: `var total` is like a piggy bank — each lap drops one more number into it. **Modifying a `var` variable inside a loop** is the most common pairing in programming.

## 6.3 while: Keep Going Until It Fails

`for` suits "counted repetition"; `while` suits "do it until a condition stops holding" — **as long as the condition is true, keep going**:

```cangjie
main() {
    var noodlesLeft = 10
    while (noodlesLeft > 0) {
        println("${noodlesLeft} noodles left")
        noodlesLeft = noodlesLeft - 1
    }
    println("All eaten!")
}
```

> ⚠️ **Danger warning**: if you forget `noodlesLeft = noodlesLeft - 1`, the condition stays true forever and the program loops forever — an **infinite loop**. When the screen keeps scrolling, press **Ctrl+C** to force-stop.

## 6.4 break and continue

- `break`: end the entire loop immediately (done counting — walk away);
- `continue`: skip this round, move to the next one.

```cangjie
main() {
    for (i in 1..10) {
        if (i == 3) { continue }      // skip 3
        if (i == 7) { break }         // stop at 7
        println("counted to ${i}")
    }
}
// output: counted to 1, counted to 2, counted to 4, counted to 5, counted to 6
```

## 6.5 Hands-On Practice

1. Use `for` to print one column of the times table: `1×7=7`, `2×7=14` … `9×7=63`;
2. Use `while` to count down from 10 to 1, then print "Liftoff!";
3. Change "1 to 100" into "1 to 1000" and check the answer against the formula n×(n+1)/2;
4. Challenge: use `for` to print every even number from 1 to 50 (hint: `i % 2 == 0` means even).

## ✳ A Thought on Programming: The Three Elements of a Loop

Before writing any loop, answer three questions (the **three elements of a loop**):

1. **Where does it start?** (the starting point: `i = 1` or `noodlesLeft = 10`)
2. **When does it stop?** (the condition: `i < 5` or `noodlesLeft > 0`)
3. **How does it change each lap?** (the step: `i` grows by 1 automatically, or `noodlesLeft = noodlesLeft - 1`)

Any loop, once these three are clear, cannot become an infinite loop. The essence of an infinite loop is: **"when to stop" never becomes true** — check the three elements and you find the disease instantly.

> This is another victory of "decomposition" (chapter 1): loops look scary, but split into three questions each one is simple.

## 🍳 An Everyday Algorithm: The Times Table

Print the times table with "a loop inside a loop" — the initiation ritual of every programmer:

```cangjie
main() {
    for (row in 1..10) {
        var line = ""
        for (col in 1..=row) {
            line = line + "${col}×${row}=${col * row} "
        }
        println(line)
    }
}
```

- The outer loop manages the "rows" (1 to 9); the inner loop manages the "columns" (1 to the current row);
- **A loop inside a loop** is called a "nested loop" — each time the outer loop takes one step, the inner loop runs a complete lap;
- The inner loop's bound `1..=row` uses the outer loop's variable — the inner lap count changes with the outer one. That is the essence of nesting.

> What does the output look like? First row: `1×1=1 `; second row: `1×2=2 2×2=4 `… Run it and see for yourself!

## Summary

- `for (i in range)`: counted repetition; `1..5` is half-open and **excludes 5**, `1..=5` includes it;
- `while (condition)`: runs as long as the condition is true — **beware infinite loops** (Ctrl+C saves you);
- `break` ends the whole loop; `continue` skips to the next round;
- The three elements: start, stop condition, per-lap change;
- Pair loops with a `var` variable for accumulation (the piggy-bank pattern);
- Nesting: the outer loop takes a step, the inner loop runs a full lap.

## Questions to Think About

1. How many times does `for (i in 1..5)` loop? And `for (i in 1..=5)`?
2. What is the correct way to write an infinite loop with `while`? (Hint: a condition that is always true. When would you use it? The number-guessing game in chapter 11 does.)
3. Why do we say "the computer isn't afraid of dumb methods"? In the Gauss story, what are the strengths and weaknesses of the computer's way versus the mathematical way?
4. Challenge: use a loop to print a triangle — 1 `*` in the first row, 2 in the second … 5 rows total. (Hint: think through the three elements first.)
