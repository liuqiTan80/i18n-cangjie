<!-- zhc-i18n 源: docs/中文仓颉程序设计/第3卷-工程与思想/19-综合实战.md 基线: 54164402c004a26c 时间: 2026-09-06 -->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第3卷-工程与思想/19-综合实战.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 19 The Capstone: A Complete Project

> **What you will learn in this chapter**: string the whole book's knowledge into **one complete real project** — requirements → design → test-first → implementation → debugging → refactoring → commit → release, walking the entire software engineering workflow (chapter 18's methodology put into practice).
> **After this chapter you can answer**: How does a "working" program grow from a one-sentence requirement? Why does test-first make code cleaner?

---

## 19.1 Project Choice: The Number-Guessing Game

**Requirement (one sentence)**: the computer thinks of an integer from 1 to 100; you guess, and it tells you "too low", "too high", or "correct", counting your attempts.

**Acceptance criteria**:

- Each game picks a random number in 1..100 (different every run);
- Invalid input (not a number) prompts and re-asks, **without crashing**;
- A correct guess shows the attempt count and asks "Play again?";
- Typing "quit" ends the game at any time.

**Design decisions** (each maps to a knowledge point of this book):

| Requirement | Design | Knowledge point |
|---|---|---|
| Random number | the random module | imports and module paths (chapter 10) |
| Input may be invalid | an `Option` parse function | expected failures use Options (chapter 14) |
| Loop until guessed | `while (true)` + `break` | loop control (chapter 6) |
| High/low comparison | `if/else if` | branching (chapter 5) |
| Play again | an outer loop + a Boolean state | nested loops (chapter 6) |

## 19.2 Test First: Write the Tests Before the Code

**The idea**: write the tests describing "how this function should behave" before the implementation — tests are the executable form of the requirements. The core logic is split into **pure functions** (no I/O dependencies, easy to test):

```cangjie
import std.unittest.testmacro.*
import std.unittest.*
import regex.*
import convert.*

// —— The functions under test (formally implemented in 19.3; behavior defined here) ——

func checkGuess(secret: Int64, guess: Int64): String {
    if (guess < secret) { return "too low" }
    else if (guess > secret) { return "too high" }
    return "correct"
}

func parseNumber(text: String): Option<Int64> {
    if (Regex("^\\d+$").matches(text)) {   // anchored ^...$: the whole string must be digits (\d+ alone is containment)
        return Some(Int64.parse(text))
    }
    return None
}

@Test
func testCheckGuess() {
    @Expect(checkGuess(50, 30), "too low")     // guessed low
    @Expect(checkGuess(50, 70), "too high")     // guessed high
    @Expect(checkGuess(50, 50), "correct")     // correct
    @Expect(checkGuess(1, 1), "correct")       // boundary: the minimum
    @Expect(checkGuess(100, 100), "correct")   // boundary: the maximum
}

@Test
func testParseNumber() {
    @Expect(parseNumber("42").getOrThrow(), 42)   // valid input
    @Expect(parseNumber("abc").getOrDefault({ => 0 }), 0)   // invalid input → fallback 0
    @Expect(parseNumber("").getOrDefault({ => 0 }), 0)      // empty input → fallback 0
    @Expect(parseNumber("a1").getOrDefault({ => 0 }), 0)    // boundary: contains digits but not all (slips through unanchored!)
    @Expect(parseNumber("1a").getOrDefault({ => 0 }), 0)    // boundary: trailing letters
}
```

**Note**: when testing first, functions **start as declarations** (even a fake implementation) — run the tests and watch them fail (red), then implement to make them pass (green). This is the "red-green-refactor" rhythm. The code above shows the finished implementation; in real practice, delete the bodies first and watch a failure.

## 19.3 Implementation: The Complete Game

**Project layout** (created with `zhc init`):

```
guess-the-number/
├── cjpm.toml
└── src/
    └── main.zc
```

**The complete code** (`src/main.zc`):

```cangjie
import env.*
import convert.*
import regex.*
import random.*
import std.unittest.testmacro.*
import std.unittest.*

// —— Core logic: pure functions (testable) ——

func checkGuess(secret: Int64, guess: Int64): String {
    if (guess < secret) { return "too low" }
    else if (guess > secret) { return "too high" }
    return "correct"
}

func parseNumber(text: String): Option<Int64> {
    if (Regex("^\\d+$").matches(text)) {   // anchored: the whole string must be digits
        return Some(Int64.parse(text))
    }
    return None
}

// —— Interaction logic: one game round ——

func playOneRound() {
    let generator = Random()                    // the random generator (official class name; not yet in the dialect word table)
    let secret = generator.nextInt64(100) + 1   // 1..100 (nextInt64(100) gives 0..99)
    var attempts = 0
    println("I'm thinking of an integer from 1 to 100. Guess!")
    while (true) {
        attempts += 1
        println("guess ${attempts}:")
        let input = readLine()
        if (input == "quit") { return }          // quit anytime
        let number = parseNumber(input).getOrDefault({ => -1 })   // invalid input falls back to -1
        if (number == -1) {
            println("please enter a number (or type \"quit\")")
            attempts -= 1                       // invalid input doesn't count
        } else {
            let result = checkGuess(secret, number)
            if (result == "correct") {
                println("🎉 Correct! The answer was ${secret}, in ${attempts} attempt(s).")
                return
            } else {
                println("${result}, try again!")
            }
        }
    }
}

// —— Entry ——

main() {
    println("== Number Guessing Game ==")
    while (true) {
        playOneRound()
        println("Play again? (type quit to end, anything else to continue)")
        if (readLine() == "quit") { break }
    }
    println("Goodbye!")
}
```

> 💡 Why no `match` here? Tested on official 1.0.5: `match` branch bodies must be **expressions** (`case X => expression`); multi-statement branches as blocks report "expected `=>`". So multi-statement branches use `getOrDefault` fallback + `if/else` instead — the same effect, and plainer (the chapter 13 expression-form match is practiced in challenge 5 of 19.7).

**Running**:

```bash
zhc run src/main.zc
```

**A verified session**:

```
== Number Guessing Game ==
I'm thinking of an integer from 1 to 100. Guess!
guess 1:
50
too low, try again!
guess 2:
75
too high, try again!
guess 3:
62
🎉 Correct! The answer was 62, in 3 attempt(s).
Play again? (type quit to end, anything else to continue)
quit
Goodbye!
```

**Block-by-block dissection** (everything this project uses):

| Code | Purpose | Knowledge point |
|---|---|---|
| `generator.nextInt64(100) + 1` | generates a random 1..100 | module imports (chapter 10); `Random`/`nextInt64` are official names not yet in the zh word table — usable directly |
| `parseNumber` returns an `Option` | invalid input doesn't crash | expected failures use Options (chapter 14) |
| `parseNumber(input).getOrDefault({ => -1 })` | invalid input falls back to -1, no crash | Option fallback (chapter 14) |
| `while (true)` + `break`/`return` | an endless loop until a condition is met | loop control (chapter 6) |
| `attempts -= 1` | invalid input doesn't count | compound assignment (chapter 9) |
| `checkGuess` as a pure function | core logic independently testable | function design (chapters 7/8) |

## 19.4 Testing and Debugging

**Running the tests**:

```bash
zhc test
```

```
[ PASSED ] CASE: testCheckGuess
[ PASSED ] CASE: testParseNumber
Summary: TOTAL: 2
    PASSED: 2, SKIPPED: 0, ERROR: 0
    FAILED: 0
```

**Deliberately plant a bug to practice debugging**: change `guess < secret` to `guess <= secret` in `checkGuess` — run the tests and `@Expect(checkGuess(50, 50), "correct")` goes **red** (it becomes "too low"). That is the value of regression testing: whatever you break appears instantly.

**The debugging flow** (the five steps of chapter 18):

1. Classify: a logic error (it compiles; the behavior is wrong);
2. Minimal reproduction: one line, `checkGuess(50, 50)`;
3. Read the output: a failed `@Expect` shows the actual value ("too low") versus the expected ("correct");
4. Bisect: is it `<=` versus `<`? Compare the boundary;
5. Verify the fix: change it back to `<` and `zhc test` goes all green.

## 19.5 Refactoring: Making the Code Cleaner

**Definition**: refactoring = changing the structure without changing the behavior (the tests guarantee nothing broke). Refactorings this project invites:

**① Extract constants** (the magic numbers 1 and 100 are a smell):

```cangjie
import random.*
const MIN = 1
const MAX = 100

func playOneRound() {
    let generator = Random()
    let secret = generator.nextInt64(MAX) + MIN
    // ...the rest unchanged (combine with the full code of 19.3)
}
```

**② Extract "play again?" into a function** (main keeps only the flow):

```cangjie
func wantsAnotherRound(): Bool {
    println("Play again? (type quit to end, anything else to continue)")
    return readLine() != "quit"
}

main() {
    println("== Number Guessing Game ==")
    while (true) {
        playOneRound()          // combine with the full code of 19.3 (a fragment)
        if (!wantsAnotherRound()) { break }
    }
    println("Goodbye!")
}
```

**③ Extract the invalid-input message into a constant** (centralized copy management).

> The iron rule of refactoring: **run the tests after every refactor**. All green = the behavior didn't change = the refactor succeeded.

## 19.6 Commit and Release

**git commits** (small steps, each verifiable):

```bash
git init
git add .
git commit -m "add: number-guessing game (random, Option parsing, game loop)"
git log --oneline        # view history
```

**Tag the version** (semantic versioning, chapter 18):

```bash
git tag v0.1.0
```

**The release checklist** (against chapter 18):

- [x] Full test run passes (`zhc test` all green);
- [x] Acceptance criteria verified manually (invalid input, boundaries, quit);
- [x] README written: how to run, environment requirements, acceptance criteria;
- [x] Lint cleanup (`zhc lint --fix`);
- [x] Tag the version.

## 19.7 Extension Challenges

1. **Difficulty levels**: change the guess range to "1 to 1000" — how many attempts does it take at most? (Hint: binary search, 2¹⁰=1024);
2. **Track your record**: record the attempt count of each round in an `ArrayList` and print "average X attempts per win" at the end;
3. **Role reversal — the computer guesses your number**: hint: `while (true)` + `readLine` answering too high/too low/correct — binary search in action (chapter 17);
4. **Limited attempts**: 10 wrong guesses loses the game (hint: `break` when `attempts >= 10` and reveal the answer);
5. **The ultimate challenge**: change `checkGuess`'s return from `String` to `enum Result { TooLow | TooHigh | Correct }` and refactor the whole project — feel how enums + exhaustiveness checking make the code safer (chapter 13).

## 19.8 A Project Variant: Role Reversal — Now the Computer Guesses

19.1's main line was "the computer sets, the human guesses". What about the reverse? — **Think of an integer from 1 to 100 (don't say it), and the computer guesses**, while you tell it "too high", "too low", or "correct".

The computer doesn't guess blindly — it uses **binary search**: guessing the middle number each time halves the possibilities — it guesses 50, you say "too low", the answer lies in 51..100, and 50 possibilities become 25; it guesses 75, you say "too high", the range shrinks to 51..74… each guess halves the space, and 100 numbers lock in within 7 guesses (2⁷ = 128 ≥ 100). This is chapter 17's binary search put into practice (the full implementation of challenge 3 in 19.7):

```cangjie
main() {
    var low = 1
    var high = 100
    var attempts = 0
    println("Think of an integer from 1 to 100. I'll guess it!")
    while (true) {
        attempts = attempts + 1
        let guess = (low + high) / 2
        println("guess ${attempts}: is it ${guess}? Too high, too low, or correct?")
        let answer = readLine()
        if (answer == "too high") {
            high = guess - 1
        } else if (answer == "too low") {
            low = guess + 1
        } else if (answer == "correct") {
            println("Haha, got it in ${attempts}!")
            break
        } else if (answer == "quit") {
            println("Fine, quitting!")
            break
        } else {
            println("please answer: too high / too low / correct (or type quit to end)")
            attempts = attempts - 1    // invalid answers don't count
        }
    }
}
```

A session after `zhc run` (you answer "too low / too high / correct"):

```text
Think of an integer from 1 to 100. I'll guess it!
guess 1: is it 50? Too high, too low, or correct?
too low
guess 2: is it 75? Too high, too low, or correct?
too high
guess 3: is it 62? Too high, too low, or correct?
correct
Haha, got it in 3!
```

**What this variant uses**: `var` (low/high/attempts change constantly), `while (true)` + `break` (an endless loop until correct or quit), `if/else if` (narrowing by your answers), `readLine` (reading your answers), and math (binary search `(low + high) / 2`). Compared with 19.1-19.6's main line it has no randomness and no replay loop, but it adds a **strategy** — the program doesn't just follow a script, it "works out a plan". (Acceptance criteria consistent with 19.1: typing "quit" ends it anytime.)

**Variant challenges**:

1. Change the range to 1 to 1000: at most how many guesses to lock in? (Hint: 2¹⁰ = 1024.)
2. What if the computer gets "led astray": print "honesty only, please" before each guess — what happens to the attempt count? How would you fix it? (Hint: print the reminder before the first guess only, not every time.)
3. The ultimate variant: the program becomes the **setter** and **randomly picks a number** (the random module from 19.3) while you are the **guesser** — merge the 19.1-19.6 version with this variant into a "two-player game": you guess one round, the computer guesses the next, and the lower count wins!

## Summary

- The complete project flow: requirements (one sentence + acceptance criteria) → design (each requirement mapped to a knowledge point) → test-first (red-green-refactor) → implementation → debugging (the five steps) → refactoring (tests as the safety net) → commit and release;
- The number-guessing game uses: randomness, `Option` parsing with fallbacks, `while (true)` + `break`, pure functions, nested loops — **the first full mobilization of the whole book's knowledge**;
- Test-first made the design cleaner: the core logic as pure functions, interaction and logic separated;
- The iron rule of refactoring: change no behavior, only structure, running the tests every time;
- The release checklist: tests green → acceptance verified manually → documentation → lint → tag.

## Questions to Think About

1. Why does `parseNumber` return an `Option` instead of calling `Int64.parse` directly and catching the exception? (Hint: expected vs unexpected, chapter 14.)
2. In main's `while (true)` loop, `playOneRound` runs its own `while (true)` — what is the exit of each nested loop?
3. If `checkGuess` were changed from a pure function to "print the result directly", would testing get harder or easier? Why? (Hint: tests would need to capture the output.)
4. Why must refactoring have tests as the safety net? What happens when refactoring without tests? (Hint: nobody notices a breakage.)
5. The ultimate challenge's enum version: if a `match (result)` is missing one branch, what happens? (Hint: exhaustiveness checking, chapter 13.)
