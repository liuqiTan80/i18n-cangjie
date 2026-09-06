<!-- zhc-i18n 源: docs/中文仓颉程序设计/第1卷-启蒙与概念/03-变量.md 基线: ef382aa3c51e8e80 时间: 2026-09-06 -->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第1卷-启蒙与概念/03-变量.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 3 Memory Boxes: Variables

> **What you will learn in this chapter**
> - Understand that a "variable" is a box with a name label on it;
> - Tell apart `let` (immutable) and `var` (mutable) boxes;
> - Learn how to give variables good names.
>
> **After this chapter you can answer**: What is the difference between `let` and `var`? Why does programming encourage using `let` by default? What does `=` mean in a program?

---

## 3.1 Let the Computer Remember Things for You

When solving a problem on paper, you write "given: x = 5" first. A **variable** is the computer's scratch paper: a box with a name label on it — you can put things in and take them out whenever you need.

## 3.2 let: A Box That Cannot Change

```cangjie
main() {
    let myAge = 12
    println("My age is ${myAge}")
}
```

- `let myAge = 12`: take a box, stick the label "myAge" on it, and put the number `12` inside;
- `"My age is ${myAge}"`: `${}` is **interpolation** — like filling in a blank, it drops the box's value into the sentence.

Run result: `My age is 12`.

`let` means "**decided, not changing**" — once something goes into the box, it stays. If you try to write `myAge = 13` afterwards, the compiler will stop you without mercy: "cannot assign to immutable value".

> Analogy: `let` is a word carved in stone (it cannot be changed).

## 3.3 var: A Box You Can Change

Sometimes we really do need to change things — for example, counting:

```cangjie
main() {
    var count = 0
    count = count + 1      // take 0 out of the box, add 1, put back 1
    count = count + 1      // take it again — now it's 2
    println("counted twice: ${count}")
}
```

- `var`: the contents of the box can be **replaced at any time**;
- `=` is **assignment**: put the thing on the right into the box named on the left. Note that it is not the mathematical "equals" — it means "put … into …". So `count = count + 1` means: take the current `count`, add 1, and put it back.

> Analogy: `var` is a word on a blackboard (it can be erased and rewritten).
>
> How to choose? **Default to `let`** — if it's enough, lock it down. Only use `var` when the value truly must change (counting, accumulating, countdowns). That way anyone reading the code sees at a glance: the places marked `var` are the ones that change.

## 3.4 Rules for Naming Boxes

- Descriptive names win: `totalScore` is a hundred times better than `a` — in two days you won't remember what `a` was;
- Names cannot start with a digit (`123abc` is invalid) and cannot contain spaces;
- You can add a type annotation to tell the computer what material the box holds:

```cangjie
main() {
    let name: String = "Xiaoming"   // this box holds text only
    let score: Int64 = 95           // this box holds whole numbers only
    println("${name} scored ${score}")
}
```

The annotation is optional — the computer is smart and can guess the box type from what you put in (this is called **type inference**). But writing the annotation is safer: if the label says "whole numbers only" and you try to stuff text in, the computer stops you immediately.

## 3.5 const: Words Carved in Stone

There is an even "harder" kind of box — `const`:

```cangjie
const PI = 3.14159
const schoolName = "No.1 Middle School"

main() {
    println("${schoolName}, PI ≈ ${PI}")
}
```

Both `const` and `let` are immutable. The difference: `const` is fixed at **compile time** (written in stone before the program even runs) — faster and safer. **Whenever you can use `const`, use `const`** — values that never change, like PI or a school name, belong in a `const`.

## 3.6 Hands-On Practice

1. Store your birthday with `let` and your pocket money with `var`, then print them;
2. Guess: after `let score = 90`, what happens if you write `score = 95`? Try it! The error message will tell you;
3. Use `const` for the distance from your home to school, and print "My home is X km from school";
4. Challenge: use `var` to keep a "pocket-money ledger" — start with 100, spend 25 on stationery and 10 on snacks, then print what's left.

## ✳ A Thought on Programming: Naming Is Documentation

"Naming a box" is a small thing — and one of the biggest things in programming.

- Programmers read code 5-10 times more than they write it;
- The code you write is mostly read by **your future self** and by **other people**;
- A variable named `totalScore` needs no comment; one named `a` is forgotten by tomorrow.

**Naming is documentation**: a good name is its own manual. Ten extra seconds choosing a name saves hours of puzzling later. This is called "self-documenting code" — the code speaks for itself.

## 🍳 An Everyday Algorithm: Swapping Two Boxes

Xiaoming has two boxes: one holds cola, the other orange juice. He wants to swap the contents — but note: **you cannot pour both boxes at the same time** (it would spill).

The programmer's solution: grab a third, **empty box** (a temporary variable):

```
1. Pour the cola into the empty box     // temp = cola
2. Pour the orange juice into the cola box   // cola = juice
3. Pour the temp box into the juice box     // juice = temp
```

In code:

```cangjie
main() {
    var cola = "cola"
    var juice = "orange juice"
    var temp = cola        // 1. save it first
    cola = juice           // 2. juice moves into the cola box
    juice = temp           // 3. the original cola moves into the juice box
    println("the cola box now holds: ${cola}")
    println("the juice box now holds: ${juice}")
}
```

This is the classic pattern every programmer meets — **swapping two values**. The core idea: swapping directly loses something, so borrow a "temporary box" first. You will meet it again when you write sorting algorithms (chapter 17).

## Summary

- A variable = a box with a name label; `=` means "put it in", not mathematical equality;
- `let`: immutable (the default); `var`: mutable (only when needed); `const`: fixed at compile time (for values that never change);
- Naming rules: descriptive, readable at a glance, no leading digits, no spaces;
- Type annotations are optional: `let name: String = "Xiaoming"` — with an annotation, the wrong material is caught instantly;
- Swapping two values: borrow a temporary box first.

## Questions to Think About

1. Why is `let` the default instead of `var`? (Hint: a box that cannot change secretly makes code easier to trust.)
2. `count = count + 1` is absurd in mathematics (x = x + 1 has no solution). Why is it legal in a program?
3. Find real-life examples of `let` and `var`: what, once decided, never changes (like an ID number)? What changes every day (like pocket money)?
4. Try it: skip the box entirely and write `println("${12}")` — will `12` print? What does that tell you?
