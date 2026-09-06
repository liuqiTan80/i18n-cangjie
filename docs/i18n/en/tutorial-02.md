<!-- zhc-i18n 源: docs/中文仓颉程序设计/第1卷-启蒙与概念/02-第一个程序.md 基线: a41c6c44faab715e 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第1卷-启蒙与概念/02-第一个程序.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 2 Your First Program: Hello, World!

> **What you will learn in this chapter**
> - Create and run your very first program;
> - Meet the program's "entry point" — `main`;
> - Use `println` to make the computer talk.
>
> **After this chapter you can answer**: Where does a program start running? Why is it called print*line*? How does your code become something the computer understands?

---

## 2.1 The Traditional First Sentence

Every programmer's first program makes the computer say: "Hello, World!" It's a tradition in programming, like starting calligraphy with a single stroke — simple, but from that moment you are a programmer.

## 2.2 Create Your Project

Open a terminal and type:

```bash
zhc init my-first-program
```

This creates a folder called "my-first-program" containing a small program that already runs.

Then enter the folder and open `src/main.zc` (any text editor will do):

```cangjie
main() {
    println("Hello, World!")
}
```

Just three lines! Let's take it apart.

## 2.3 main: The Program's Entry Point

`main()` is the **entry point** of your program — when the computer runs it, execution starts here, like stepping through the front door of a house.

The `{` and `}` (braces) after it are the **door frame**: `{` means "the door is open, the code inside starts running", and `}` means "the door closes, execution ends here".

> 💡 Note: the entry is written `main()` — **without** the `func` keyword in front of it. Writing `func main()` is a mistake; the compiler will remind you.

## 2.4 println: Making the Computer Speak

`println("Hello, World!")` means: **make the computer show "Hello, World!" on the screen**.

- The `"` (double quotes) are the "packaging" for text — they tell the computer: what's inside is a sentence, not code;
- `println` has one more letter than `print` because after printing it also starts a **new line** — like pressing Enter after writing a line. The next output begins on a fresh line.

## 2.5 Run Your Program

In the terminal, type:

```bash
zhc run src/main.zc
```

You will see:

```
✅ Compile OK: replaced 2 dialect identifier(s).
Hello, World!
```

**It worked!** You just finished the first lesson of every programmer.

> Behind the scenes: `zhc run` does three things — ① it translates your dialect code into standard Cangjie (by looking up the language pack, hence "replaced 2 dialect identifier(s)"); ② it lets the compiler translate Cangjie into the `0`s and `1`s the machine understands; ③ it runs the result. The "translator team" you met in section 1.3 is now officially on duty.

> **Small experiment**: change the text inside the quotes to your own name and run it again — for example `println("I am Ada")`. The computer now says "I am Ada". **You can already modify programs!**

## 2.6 Hands-On Practice

1. Make the computer say three things in a row: your name, your age, and your favorite food (hint: write three `println` lines);
2. Guess: what happens if you remove the quotes and write `println(Hello)`? Try it! Read the error message — it is helping you find the problem, not punishing you;
3. Challenge: add `println("second line")` after the first `println` inside `main()`. Watch the output order — which comes out first?

## 2.7 Errors Are Not Scary: Reading Error Messages

When a program reports an error, the computer is not punishing you — it is **helping you find the problem**. zhc's nicest touch: **the error messages are in your mother tongue**, with a 💡 teaching hint and a repair example — where it's wrong, why it's wrong, and how to fix it.

Try it: deliberately change `println("Hello, World!")` to `println2("Hello, World!")` (the answer to exercise 2 in 2.6) and run `zhc run src/main.zc`. You will see something like:

```text
[error] undeclared identifier `println2`  main.zc:2:5
  💡 An undefined name was used: check the spelling; variables must be declared before use.
  Fix example (paste directly):
  ...
```

Take the message apart:

| Message part | Meaning |
|---|---|
| `[error]` | This is an error, not a warning (a warning means "better fix it, but it still runs") |
| undeclared identifier `println2` | The computer does not recognize the name `println2` |
| `main.zc:2:5` | **Location**: line 2, around character 5 |
| 💡 teaching hint | Why this error happens + how to fix it |
| Fix example | Correct code you can paste directly |

> Analogy: an error message is like a **doctor's report** — where it hurts (location), what the illness is (cause), and how to treat it (fix example), all written down.

The three most common beginner errors:

**1. A misspelled name** — `println` typed as `println2`, `score` typed as `scroe` → "undeclared identifier". Check the spelling.

**2. Type mismatch** — `let age: Int64 = "12"`: text placed into a number box → "type mismatch". The box's label must match what goes inside (you will meet this often after chapters 3 and 4).

**3. Unpaired brackets/quotes** — `println("Hello` missing a `)` → "unclosed delimiter". Count that every `(` has a `)` and every `"` has a closing `"`.

**The three-step debugging method**:

1. **Read the message**: start with the sentence after `[error]` — which name, which type, which symbol?
2. **Find the location**: go to `file:line:column`, jump to that line, look around.
3. **Fix it**: follow the 💡 hint and the fix example, then run again. **Change one thing at a time** and run immediately after each change.

> Tip: the *first* error is usually the real cause — later ones may be chain reactions. Fix the first one first.

## ✳ A Thought on Programming: Convention over Configuration

On your first day of programming you may not have noticed: **the first program everywhere in the world is "Hello, World!"**. That is not a coincidence — it is a *convention*.

Programming is full of conventions: the entry is called `main`, the file is called `main.zc`, the project layout is generated by the tool… Why does everyone follow them?

- **Saves thinking**: you don't wonder "what should the entry be called" — you just follow the convention;
- **Saves communication**: every programmer in the world knows `main.zc` is the entry file, no explanation needed;
- **Tools work better**: precisely because of conventions, `zhc init` can generate a whole project in one command — it knows what you need.

**Convention over Configuration**: making "the default way" the "good way" is one of the great ideas in software design. When you later meet a pattern that "everyone uses", follow it first, then figure out why.

## 🍳 An Everyday Algorithm: You Are Already a "Program"

Think about how your morning went:

```
1. Get up
2. Brush your teeth
3. Have breakfast
4. Leave for school
```

That is a "program" — executed from top to bottom, step by step. A computer works the same way: the code inside `main()` runs **in order**, one statement at a time.

Keep this picture in mind: **a program = a recipe executed step by step, in order**. From chapter 3 on, we start adding "memory boxes" (variables) to the recipe.

## Summary

- A first program is only three lines: `main()` wrapping `println("...")`;
- `main()` is the entry point (no `func` prefix), and the braces `{}` mark the program's extent;
- `println("text")` makes the computer show one line of text and start a new line; the text goes in double quotes;
- `zhc run src/main.zc` runs your program: translate → compile → execute;
- By convention, the first program is always "Hello, World!".

## Questions to Think About

1. If you delete the `{` and `}` around `main()`'s body, can the program still run? Why?
2. What is the difference between `println` and `print`? Does `print` exist? (Hint: look it up in `zhc/lang-packs/en/stdlib.toml`.)
3. Why does `"Hello"` need quotes while `main` does not? What is the difference between them?
4. Add `println("I am the first line")` before `println("Hello")`, predict the output order, then verify it.
