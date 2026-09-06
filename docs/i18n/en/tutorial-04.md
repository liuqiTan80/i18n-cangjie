<!-- zhc-i18n 源: docs/中文仓颉程序设计/第1卷-启蒙与概念/04-数字与文字.md 基线: 0a09182365926f5a 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第1卷-启蒙与概念/04-数字与文字.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 4 Numbers and Text

> **What you will learn in this chapter**
> - Meet the four basic "materials": Int64, Float64, String, Bool;
> - Make the computer add, subtract, multiply, and divide;
> - Use interpolation `${}` to combine text and numbers into a sentence.
>
> **After this chapter you can answer**: What is the difference between `12` and `"12"`? Why does `7 / 2` equal 3? How does the computer assemble "Xiaoming scored 95 points" into one sentence?

---

## 4.1 What Can Go in a Box?

So far we have stored numbers and text. In fact there are four basic "materials":

| Material | Name | Examples |
|---|---|---|
| Whole numbers (no decimal point) | `Int64` | `12`, `-3`, `0` |
| Decimals (floating point) | `Float64` | `3.14`, `-0.5` |
| Text (string) | `String` | `"hello"`, `"abc"` |
| True/false (Boolean) | `Bool` | `true`, `false` |

The computer keeps these perfectly separate: `12` is a number, `"12"` is text — try adding them and you get an error! Because "12 apples + 12 characters" is meaningless. This is a **type**: each material has its own rules, and if you put the wrong material in a box, the computer stops you immediately (there's an experiment at the end of this chapter).

## 4.2 The Computer Is a Calculator

```cangjie
main() {
    let applePrice = 3
    let pearPrice = 4
    let total = applePrice + pearPrice
    println("the total is ${total}")
    println("three apples cost ${applePrice * 3}")
    println("pears cost ${pearPrice - applePrice} more")
}
```

The operators: `+` add, `-` subtract, `*` multiply, `/` divide.

Just like in math, **multiply and divide come before add and subtract**; use parentheses to change the order: `(applePrice + pearPrice) * 2`.

## 4.3 The Integer Division Trap

```cangjie
main() {
    println(7 / 2)          // prints 3, not 3.5!
    println(7.0 / 2.0)      // prints 3.5
    println(7 % 2)          // prints 1 (% is the remainder)
}
```

**Integer divided by integer is still an integer** (the extra part is simply dropped). `7 / 2` gives `3`, not `3.5`! For `3.5`, use floats: `7.0 / 2`.

`%` is the **remainder**: `7 % 2` is 1. Odd or even, last digit of a number — everything uses it. You will need it in chapter 5.

## 4.4 Gluing Text Together: Interpolation

To combine text and numbers, `${}` blanks are the most convenient:

```cangjie
main() {
    let name = "Xiaoming"
    let score = 95
    println("${name} scored ${score}")
}
```

Output: `Xiaoming scored 95`. Inside `${}` you can put variables — even whole calculations:

```cangjie
main() {
    let apples = 3
    let pears = 4
    println("the total is ${apples + pears} fruits")   // the total is 7 fruits
}
```

> Want a line break in the output? Use `\n`: `println("first line\nsecond line")` prints two lines. `\n` is read as "the newline character".

## 4.5 Hands-On Practice

1. Calculate: if your pocket money grew by 2 per day, how much more would you have in a year (365 days)? Compute it with a program;
2. Print a sentence: "My height is" + your height (use interpolation `${}`);
3. Try `println(1 + "2")` and read the error message — notice how the 💡 hint explains the "type mismatch";
4. Challenge: upgrade the chapter 3 "pocket-money ledger" — store the money as a float (say 100.5), spend 25.3, and print what's left (look at the decimal places in the output).

## ✳ A Thought on Programming: Types Are "Category Labels"

Why is the computer so rigid about telling `12` and `"12"` apart?

Because **values of different types can do different things**: numbers can be added, subtracted, multiplied, divided; text can be concatenated and searched; true/false is used for decisions (chapter 5). If the computer allowed "number + text", what would `1 + "2"` be — `3` or `"12"`? Every programmer would invent their own answer, and programs would descend into chaos.

So programming languages use **types** to label every value: **the type decides which operations a value supports**. It is like classifying kitchen tools: the knife cuts, the pan fries — you don't fry vegetables with the knife.

> This is also a design philosophy of Cangjie: **eliminate implicit conversions** — the computer is never allowed to "cleverly" turn a number into text on its own. Every conversion must be written explicitly by the programmer (chapter 9 shows how). The rigidity exists to keep you safe.

## 🍳 An Everyday Algorithm: Making Change

You buy something for 7 and pay with 20. How does the shopkeeper compute the change?

```cangjie
main() {
    let paid = 20
    let price = 7
    let change = paid - price
    println("change due: ${change}")

    // Upgrade: if only 1, 5, and 10 bills exist, how do we make it?
    let tens = change / 10          // 20 - 7 = 13, 13 / 10 = 1 bill
    let rest = change % 10          // 3 left
    let fives = rest / 5            // 3 / 5 = 0 bills
    let ones = rest % 5             // 3 left
    println("${tens} ten(s), ${fives} five(s), ${ones} one(s)")
}
```

This example hides two algorithmic ideas:
- **`/` and `%` are a natural pair**: division gives "how many bills", remainder gives "what's left" — together they form the "make change" algorithm;
- This "divide first, take the remainder second" pattern is the seed of the **greedy algorithm**: always take the largest denomination first (chapter 17 goes deeper).

## Summary

- Four basic materials: `Int64`, `Float64`, `String`, `Bool` (`true`/`false`);
- Operators: `+ - * / %`; multiply/divide before add/subtract; parentheses first;
- **Integer divided by integer stays an integer** (`7 / 2` = 3); for decimals use floats (`7.0 / 2`);
- `%` takes the remainder: parity checks, making change — it powers them all;
- Interpolation `${}`: drop a variable or a calculation into a string, `"${name} scored ${score}"`;
- Types are category labels: `12` and `"12"` are two different things, and the computer refuses "implicit conversion".

## Questions to Think About

1. What does `println(10 / 3)` print? And `println(10 % 3)`? Guess first, then verify;
2. Why does `1 + "2"` produce an error? What would the world look like if it were allowed? (Hint: `"1" + "2"` is `"12"` — so what should `1 + "2"` be?)
3. Can you put `println("...")` inside `${}`? Why not? (Hint: interpolation needs a "value"; println is an "action".)
4. Use `%` to write a program that decides whether 123 is even. (Hint: divisible by 2 means even.)
