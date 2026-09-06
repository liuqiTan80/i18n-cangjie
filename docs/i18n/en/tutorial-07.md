<!-- zhc-i18n 源: docs/中文仓颉程序设计/第1卷-启蒙与概念/07-函数.md 基线: f630f8b072e5244a 时间: 2026-09-06 -->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第1卷-启蒙与概念/07-函数.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 7 First Taste of Functions

> **What you will learn in this chapter**
> - Understand that a "function" packs code into a named box, ready for use anytime;
> - Learn to define functions: parameters (the ingredients) and returns (the product);
> - See why functions make code non-repetitive, easy to change, and easy to read.
>
> **After this chapter you can answer**: How is a function different from a variable box? What are parameters and return values? What happens when a function is called?

---

## 7.1 Code You Repeat, Wrap into a Function

You have noticed that the "grade rating" decision will be needed three times. Copy-paste it three times? The code becomes long and smelly, one change means three edits, and a missed edit breeds a bug.

A **function** is the solution: pack a piece of code into a "toolbox", give it a name, and use it anytime.

## 7.2 Defining a Function

```cangjie
func rate(score: Int64): String {
    if (score >= 90) { return "Excellent" }
    else if (score >= 60) { return "Pass" }
    else { return "Keep trying" }
}

main() {
    println("Xiaoming's grade: ${rate(85)}")
    println("Xiaohong's grade: ${rate(95)}")
}
```

Take it apart:

- `func rate`: defines a function named "rate";
- `(score: Int64)`: the **parameters** — the "ingredients" the function needs to work. Here it takes one whole number, called `score`;
- `: String`: the **return type** — the "product" the function hands back is text;
- `return "Excellent"`: hand the product over, and the function **ends immediately** (the code after it no longer runs);
- `rate(85)`: **calls** (uses) the function, handing it 85.

> Analogy: a function is like a vending machine — insert a coin (parameters), get a product (return). Different coins, different products.

## 7.3 Parameters and Returns: Ingredients and Product

One more example — the area of a rectangle:

```cangjie
func area(width: Float64, height: Float64): Float64 {
    return width * height
}

main() {
    println("area of 3 by 4: ${area(3.0, 4.0)}")
    println("area of 5 by 6: ${area(5.0, 6.0)}")
}
```

A few details:

- **Parameters must have types** (`: Float64`) — this is the function's "contract" with the outside world: you give this, I produce that, written clearly so neither side is vague;
- Parameters are **read-only** (you cannot reassign a parameter) — they are like ingredients handed in at the door; you can't send one back and swap it;
- A function can have several parameters (separated by commas), or none at all.

## 7.4 No Ingredients, No Product — Also Fine

When you need no parameters and no return value, just leave them empty:

```cangjie
func greet() {
    println("Hello there!")
}

main() {
    greet()
    greet()
}
```

- `func greet()`: empty parentheses = no ingredients needed;
- No `: return type` = no product (technically it returns an empty value called "Unit", which you need not care about);
- Calling it twice prints twice — **write once, use many times**.

## 7.5 Why Use Functions?

1. **No repetition**: the same logic is written once (change the grading rule in one place only);
2. **Easy to change**: edit one spot, and every usage updates;
3. **Easy to read**: `rate(85)` is understandable at a glance — far cleaner than a wall of `if`s;
4. **Easy to test**: small functions are easy to verify on their own — give it a number, check what comes back (chapter 18 is all about testing).

> A small naming rule: use "verb + object" — `computeTotal`, `readFile`, `area`. One glance and you know what it does.

## 7.6 Hands-On Practice

1. Write `sumUp(max: Int64): Int64` that uses a loop to compute `1+2+…+max`, then call it for 100 and 1000;
2. Write `parity(n: Int64): String` that returns "even" or "odd" (hint: `n % 2 == 0` means divisible by 2; `%` is the remainder);
3. Think: is the 85 in `rate(85)` the same box as the `score` inside the function? — **No!** At call time the computer creates a fresh `score` box, puts 85 in it, and the box vanishes when the function ends;
4. Challenge: write `stars(count: Int64)` that prints one line of `count` stars, then call it 3 times (with 1, 2, and 3).

## ✳ A Thought on Programming: Abstraction — Hiding the Details

A function's greatest value is not "less typing" — it is **abstraction**:

- Someone using `rate(85)` **does not need to know** how the rating is decided inside (no need to read that wall of `if`s);
- Like a washing machine: you don't need to know how the motor spins — you only know "put clothes in, press the button, take clothes out".

That is the power of abstraction: **hide the "how" inside, expose only the "what" outside**. Every layer of a program builds on this kind of hiding:

- Functions hide logic → main only cares about the calls;
- Classes hide data (chapter 12) → the outside sees only methods;
- Language packs hide word tables (chapter 1) → you just write your mother tongue.

**A person who can program is a person who knows how to layer and hide details.**

## 🍳 An Everyday Algorithm: The Vending Machine

Turn the "rating" metaphor into real code — a vending machine with four buttons:

```cangjie
func vend(button: Int64): String {
    if (button == 1) { return "cola" }
    else if (button == 2) { return "orange juice" }
    else if (button == 3) { return "mineral water" }
    return "no such product"      // every other button is invalid
}

main() {
    println("press 1: ${vend(1)}")
    println("press 2: ${vend(2)}")
    println("press 9: ${vend(9)}")
}
```

Two small techniques live in this example:

- **The "fallback return"**: the last `return` needs no `else` — because the earlier `return`s already ended the function. Reaching the last line means none of the earlier conditions held. This is a habitual pattern of function-style writing;
- **A function is a "black box"**: main only knows "which button yields which product" and cares nothing for how the machine decides — that is abstraction.

## Summary

- `func name(parameter: Type): ReturnType { ... }`: defines a function;
- Parameters are ingredients (**types required**, read-only); `return` hands back the product and ends the function immediately;
- Calling: `name(arguments)`; write once, use many times;
- Functions without parameters/returns: empty parentheses, no return type;
- Four benefits of functions: no repetition, easy to change, easy to read, easy to test;
- The idea: **abstraction** — hide the "how", expose the "what".

## Questions to Think About

1. Does code after a `return` execute? Try writing `return 1` followed by `println("still here")` and look at the output — then think about why the compiler warns you;
2. Which is valid, `func rate(85)` or `func rate(85.5)`? Why? (Hint: the parameter type is `Int64`.)
3. When a function is called, is the parameter box the same box as the variable outside? (Question 3 in 7.6.) What does that protect?
4. Challenge: write `maxOf(a: Int64, b: Int64): Int64` that returns the larger number — then think: how would you compare three?
