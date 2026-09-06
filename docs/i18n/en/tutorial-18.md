<!-- zhc-i18n 源: docs/中文仓颉程序设计/第3卷-工程与思想/18-软件工程基础.md 基线: 2714ad3839278b09 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第3卷-工程与思想/18-软件工程基础.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 18 Software Engineering Foundations

> **What you will learn in this chapter**: level up from "writing code" to "building software" — requirements, structure, testing, debugging, versioning, and standards, all grounded in the zhc toolchain.
> **After this chapter you can answer**: Why do unit tests matter? What is the first principle of debugging? How do you read a semantic version?

---

## 18.1 Definition: What Is Software Engineering

**Definition**: writing code is "turning an idea into a program"; software engineering is the whole discipline of making programs **maintainable, verifiable, and collaborative**:

| Personal code | Engineering project |
|---|---|
| If it runs, it's fine | others can read and modify it |
| I remember what I changed | git records every change |
| Run it once and look | automated tests guard every feature |
| It works on my machine | documented + reproducible builds |

**Why it matters**: real software spends 90% of its life being **modified**, not written from scratch — reading code takes 5-10 times longer than writing it. Engineering discipline serves "the future reader" (including you, six months from now).

## 18.2 Requirements: Decide What to Build First

**The idea**: before writing code, answer three questions — **for whom** (the user), **solving what** (the problem), **what counts as done** (acceptance criteria):

1. **One-sentence requirement**: state the feature in one sentence ("a command-line tool that converts Celsius to Fahrenheit and prints it");
2. **Acceptance criteria**: write down "what counts as done" (input 25℃ → output 77℉; negatives supported too);
3. **Minimum viable**: build the single core path first, then iterate (temperature conversion first, then batches, then interactivity).

**In practice**: handling "the input might be invalid" with an `Option` is a direct product of requirements analysis — the requirement says "the input can be any text", so the design specifies a **parse function returning an `Option`**. **Requirements determine the error-handling strategy.**

## 18.3 Project Structure and Reproducible Builds

**Definition**: a project = declared configuration (`cjpm.toml`) + conventional directories (`src/`) + documented environment (chapter 1):

```toml
[package]
name = "my-program"
version = "0.1.0"
edition = "1.0.5"

[dependencies]
libdemo = { path = "../libdemo" }
```

**Three disciplines**:

- **Declare dependencies**: all external dependencies go into `[dependencies]` — anyone cloning the project installs everything with one `cjpm fetch`;
- **Document the environment**: SDK version, environment variables (`CANGJIE_HOME`/`LD_LIBRARY_PATH`), and build commands go into the README — reproducible on another machine (chapter 1);
- **Script the repetitive**: turn repeated actions into scripts — this project's `scripts/release.sh` (offline bundles) and `acceptance.sh` (52 acceptance checks) exemplify "turn the process into a command".

**Toolchain command quick reference**:

```bash
zhc init my-project        # create a project (src/main.zc)
zhc run src/main.zc      # transpile and run
zhc check src/main.zc    # check only, no run (common in CI)
zhc lint --fix src/main.zc   # style check + auto-fix
zhc test                 # run all dialect tests
zhc eject src/main.zc    # export official .cj source
```

**Package declarations in source**: the `cjpm.toml` `[package]` is the **project configuration**; each `.zc` source file can also declare its own **source package** on the **first line** with `package name.space` — once a project has many files, packages layer the code (e.g. `package library.management`, `package library.ui`), avoiding name collisions and enabling `internal` visibility control (appendix A):

```cangjie
package library.management

main() {
    println("files with a package declaration run directly with zhc run too")
}
```

Single-file exercises may skip the package declaration; multi-file projects should follow "package on the first line, filename matching the package's main type".

**The build pipeline** (understand this chain and you understand everything about zhc):

```
dialect source .zc → zhc transpile (word-table lookup) → official source .cj → cjc compile → binary
```

## 18.4 Unit Tests: Insurance for Your Code

**Definition**: a small piece of code verifying another piece of code's behavior — a program without tests is a car without brakes. The Cangjie standard library ships a testing framework, wrapped fully in the mother tongue by zhc:

```cangjie
import std.unittest.testmacro.*
import std.unittest.*

func grade(score: Int64): String {
    if (score >= 60) { return "pass" }
    return "fail"
}

@Test
func testGrade() {
    @Expect(grade(85), "pass")        // expect the expression to rate 85 as a pass
    @Expect(grade(40), "fail")      // test one boundary and one ordinary case
}
```

Run from the project root:

```bash
zhc test
```

```
[ PASSED ] CASE: testGrade
Summary: TOTAL: 1
    PASSED: 1, SKIPPED: 0, ERROR: 0
    FAILED: 0
```

**The three principles of testing**:

| Principle | Meaning | Counter-example |
|---|---|---|
| **Deterministic** | same input, same result, always | tests depending on the current time / random numbers |
| **Independent** | each test stands alone, runnable separately | test B requiring test A to run first |
| **Readable** | failure messages state which assumption broke | `assert(result == 5)` with no context |

**Why it's worth writing**:

- **Regression protection**: after changing code, run the tests and you instantly know whether something broke — the confidence to refactor;
- **Tests as documentation**: tests show "how this function should be used and what it returns" — more trustworthy than comments (comments go stale; stale tests go red);
- **Tests drive design**: writing tests forces you to clarify the "input/output contract" — which incidentally makes the function cleaner.

**Assertion choice**: `@Expect(expression, value)` (macro, diagnostics include the expression text) > `assertEqual(actual, expected)` (function) > `assert(condition, "message")` (Boolean).

## 18.5 Debugging Methodology: Errors Are Clues, Not Enemies

**The idea**: debugging = shrinking "the space of possible causes" until it's pinned down. zhc gives you three weapons: **teaching diagnostics** (chapter 14's error handling + the four-part format: level/location/💡hint/fix example), **lint static analysis**, and the **expand transpilation view**.

**The five-step debugging method**:

1. **Classify first**: is it a compile error (the diagnostic code prefix lex/parse/name/sema/pkg tells you the stage) or a runtime error (exception/logic bug)?;
2. **Minimize the reproduction**: shrink the failing code to the smallest form — a minimal reproduction often exposes the true culprit (delete everything unrelated);
3. **Read the whole error**: zhc diagnostics carry file:line:column + 💡 + fix examples — **follow the hint first, understand later**;
4. **Bisect**: insert `println` in the data flow to find where it goes wrong (print debugging); or comment out half the code and see in which half the error vanishes;
5. **Verify the fix**: after fixing, run the tests — and deliberately reintroduce the bug once to confirm your understanding.

**Common root causes** (self-check against chapter 16's ideas):

| Symptom | Root cause | Self-check |
|---|---|---|
| A value changed "silently" | mutability out of control | should this be `let`/a struct (copy semantics)? |
| Null-value crash | unwrapping too eagerly | should this be `match`/`getOrDefault` instead of `getOrThrow`? |
| Non-deterministic concurrent results | shared mutable state | add `synchronized` or switch to an immutable design (chapter 14)? |
| Behavior depends on order | hash container iteration | relying on HashMap/HashSet order (chapter 11)? |

## 18.6 Version Control and Releases

**Definition**: **version control (git)**: the bedrock of engineering collaboration — recording every change, supporting rollback and collaboration:

```bash
git init                # initialize the repository
git add file            # stage
git commit -m "message"    # commit (the message states what changed and why)
git log                 # view history
```

**Commit message standard**: a one-line title (start with a verb: `add`/`fix`/`refactor`/`docs`) plus a body explaining why when needed.

**Semantic versioning** (SemVer): `major.minor.patch` — the version number tells you compatibility:

| Version | Meaning |
|---|---|
| `0.1.0` | 0.x: unstable, anything may change |
| `1.0.0` | the first stable release |
| `1.2.0` | minor +1: new features (backward compatible) |
| `1.2.3` | patch +1: bug fixes (fully compatible) |
| `2.0.0` | major +1: **breaking changes** (code using `1.x` needs changes) |

**The release process** (this project as the example): full verification (every tutorial code block runs) → the 52-check acceptance script → build the release bundle (`scripts/release.sh`: compile + language packs + launcher) → write release notes → tag. **Always run tests before releasing; always record after.**

## 18.7 Code Standards and Readability

**Definition**: code is written for machines to execute and for humans to read. A uniform style keeps the team from arguing:

```bash
zhc lint src/main.zc          # style check (fullwidth punctuation/trailing whitespace/line length…)
zhc lint --fix src/main.zc    # auto-fix
```

**Five rules of readability** (dialect edition):

1. **Names state intent**: `var totalScore` beats `var s` — mother-tongue names make intent direct;
2. **Small, focused functions**: one function does one thing (split anything over 20 lines);
3. **Comments say why**: the code says "how"; the comment says "why this way";
4. **DRY**: Don't Repeat Yourself — extract repeated code into functions/generics/macros; but **don't rush to abstract at the second repetition** (wait for the third);
5. **Declarative first**: `filter`/`map` pipelines read better than hand-written loops (chapter 11).

**Code review**: showing your code to others (or reading theirs) — review is not fault-finding, it is the **four-eyes principle**: the writer has blind spots, and a second pair of eyes is a quality gate. Review focus: logical correctness, edge cases, naming, test coverage.

## 18.8 From Requirements to Delivery: A Complete Case

String together this chapter's six tools into one complete flow — the "temperature conversion CLI" (chapter 19 builds the full project; here is the minimal flow):

**① Requirements**: one sentence + acceptance criteria + minimum viable:

```
Requirement: a CLI that reads Celsius and prints Fahrenheit
Acceptance: input 25 → output 77.0; input abc → a "not a number" message, no crash
```

**② Design**: an `Option` handles parse failure (an expected failure, chapter 14); `main` reads input, parses, computes, prints:

```cangjie
import env.*
import convert.*
import regex.*

func toFahrenheit(celsius: Float64): Float64 {
    return celsius * 9.0 / 5.0 + 32.0
}

func parseCelsius(text: String): Option<Float64> {
    if (Regex("^\\d+(\\.\\d+)?$").matches(text)) {   // anchored: the whole string must be digits
        return Some(Float64.parse(text))                    // yes → success
    }
    return None                                        // no → failure (expected failures use Options)
}

main() {
    let input = readLine()
    match (parseCelsius(input)) {
        case Some(celsius) => println("${toFahrenheit(celsius)}")
        case None => println("not a number")
    }
}
```

**③ Tests**: write tests first (or alongside) the implementation:

```cangjie
import std.unittest.testmacro.*
import std.unittest.*

func toFahrenheit(celsius: Float64): Float64 {
    return celsius * 9.0 / 5.0 + 32.0
}

@Test
func testToFahrenheit() {
    @Expect(toFahrenheit(25.0), 77.0)
    @Expect(toFahrenheit(-40.0), -40.0)     // boundary: -40°C equals -40°F
}
```

**④ Run tests + manual verification**: `zhc test` all green; manually input `abc` to verify graceful handling.

**⑤ Commit**: `git add . && git commit -m "add: temperature conversion tool"`; tag `0.1.0`.

**⑥ Review** (optional): any untested edges (0 degrees, the maximum)? Should any function be split? — **small steps, each verifiable**.

## Exercises

1. Add a feature to the 18.8 temperature tool (e.g. "accept repeated input until 'quit'"), walking the full requirements → tests → implementation → commit flow;
2. Run `zhc lint` on your project, fix every style issue, and commit;
3. Add boundary tests to the `grade` function: `60` (the pass line), `59`, `100`, `0`;
4. Take a function you've already written, plant a bug in it, and locate and fix it with the five-step debugging method;
5. Read this project's `scripts/acceptance.sh` and name the "critical behaviors" it guards — if you were the author, which acceptance check would you add?

## Summary

- Software engineering = the discipline of maintainable, verifiable, collaborative programs; requirements before code, acceptance criteria before implementation;
- The project trio: declared configuration (cjpm.toml) + conventional directories (src/) + documented environment;
- Unit tests: `@Test` + `@Expect`, one-command `zhc test`; the three principles of determinism/independence/readability;
- Debugging in five steps: classify → minimize → read the whole error → bisect → verify the fix;
- git + semantic versioning + a release process make changes traceable; `zhc lint` makes style standards zero-cost.

## Questions to Think About

1. "Tests as documentation" — why are tests more trustworthy than comments? (Hint: comments go stale; stale tests go red.)
2. Why "don't rush to abstract at the second repetition"? (Hint: premature abstraction = guessing the wrong direction; the pattern is clear by the third.)
3. What is the difference between semantic versions `1.2.0` and `1.2.3`? Why be cautious about major version `2.0.0`?
4. In the five-step debugging method, why "minimize the reproduction" before "read the whole error"? (Hint: errors may be chain reactions.)
