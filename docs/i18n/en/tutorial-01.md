<!-- zhc-i18n 源: docs/中文仓颉程序设计/第1卷-启蒙与概念/01-编程是什么.md 基线: c47da624afc0b383 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第1卷-启蒙与概念/01-编程是什么.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 1 What Is Programming?

> **What you will learn in this chapter**
> - What "programming" actually is — writing a recipe;
> - Meeting your tools: Cangjie + zhc, and how code in your mother tongue becomes something the machine understands;
> - Setting up your environment hands-on: install the SDK, configure variables, build zhc — and **verify that it works**.
>
> **After this chapter you can answer**: Why are computers "dumb"? What is a program? Who is the translator? How did my zhc get installed, step by step?

---

## 1.1 Computers Are Brilliant — and Dumb

A computer can do hundreds of millions of additions in a blink, but it **does not understand human language**. Say "make me a game" and it stares blankly.

A computer understands only one extremely simple language with two symbols: `0` and `1`. It is like ancient signal beacons — **lit (1)** or **unlit (0)** — and messages travel through these two states alone.

So here is the question: how do we give instructions to something this dumb?

## 1.2 Programming = Writing a Recipe

Imagine teaching a friend who has never cooked how to make scrambled eggs with tomatoes. What would you write?

```
Step 1: Crack two eggs into a bowl and whisk
Step 2: Cut the tomatoes into chunks
Step 3: Heat oil in a pan
Step 4: Pour in the eggs, scramble, remove
Step 5: Add tomatoes, cook until juicy, return the eggs, add salt
Step 6: Serve
```

**That is programming**: writing down, step by step, what you want the computer to do — as a "recipe" it can follow. This recipe is called a **program**. The person who writes it is a **programmer** — yes, you.

## 1.3 A Programming Language = A Translator

Computers only understand `0` and `1`. Should we write programs in `0`s and `1`s directly? That would be like writing an essay in Morse code — agony.

So clever people invented **programming languages**: a middle language close to human language. A **compiler** (the translator) converts the programming language into `0`s and `1`s.

There are many programming languages in the world — and zhc adds a twist of its own:

## 1.4 Your Mother Tongue Counts Too

**Cangjie** is a new-generation, all-scenario smart programming language developed by **Huawei**. And **zhc** (the Cangjie dialect framework) pushes it further: **eight mother tongues** — Chinese, English, Japanese, Korean, Russian, French, Spanish, German — with more coming via language packs. Keyword, function names, and error messages, all in the language you choose:

| The usual way | The zhc way |
|---|---|
| Memorize the entry-point keyword | `main()` (or `メイン()`, `Haupt()`, `principal()`) |
| Memorize the print function | `println("Hello")` (or `打印行`, `ひょうじ`, `Zeige`) |
| Declare an immutable value | `let x = 1` (or `让`, `пусть`) |
| Branch | `if ... else ...` (or `如果 ... 否则 ...`, `если ... иначе ...`) |

**You never reach for a dictionary mid-thought.** And for learners whose mother tongue is *not* English — the language every other programming language assumes — this removes the biggest hidden tax in programming education: you learn programming concepts in the language you think in, then cross the bridge to official Cangjie when ready. The compiler's messages come back in your language too, with 💡 hints and fix examples. That is this book's foundation.

> **Mini glossary**
> - **Program**: the "recipe" written for a computer
> - **Code**: another name for a program (like "essay" vs "composition")
> - **Run**: make the computer execute your program
> - **Compiler**: the translator that turns code into the `0`s and `1`s a machine understands
> - **zhc**: our dialect framework — it translates your dialect code into standard Cangjie (for the compiler), and translates the compiler's diagnostics back into your language (for you)

## 1.5 Install Your Tools

We install two things:

1. **The official Cangjie SDK**: it ships the compiler `cjc` and the package manager `cjpm` (the translator itself);
2. **zhc**: the dialect framework (it handles the round trip between your language and Cangjie).

The steps below were verified on a real machine; each one includes **how to verify it** (what you should see when done).

> Requirements: Linux x86_64 (64-bit) with internet access. On Windows, use the troubleshooting table after step 7 in section 1.5, or the offline release bundle (no SDK needed).

### Step 0: Check the environment (3 minutes)

Open a **terminal** and check, line by line:

```bash
uname -m          # expected: x86_64
git --version     # expected: git version 2.x (if missing: sudo apt install -y git)
```

> Never used a "terminal"? It is the computer's "command window" — a window where you type and the computer acts. Everything that follows happens here.

### Step 1: Install the official Cangjie SDK (10 minutes)

Download the Linux x86_64 SDK archive from the official Cangjie channel (it bundles the compiler, runtime, and standard library).

Unpack it to `~/tools` and rename the folder to `cangjie` (everything later depends on this path — keeping the name consistent saves pain):

```bash
mkdir -p ~/tools
tar -xzf cangjie-sdk-linux-x64-1.0.5.tar.gz -C ~/tools
mv ~/tools/<unpacked-folder-name> ~/tools/cangjie    # rename to cangjie
```

After unpacking, the SDK should look like this (**every later path depends on it**):

```
~/tools/cangjie/
├── bin/
│   └── cjc                     # the compiler (the translator)
├── tools/bin/
│   └── cjpm                    # the package manager (deps, builds)
├── runtime/lib/linux_x86_64_cjnative/
│   └── libcangjie-runtime.so   # the runtime (needed to run any Cangjie program)
└── tools/lib/                  # build-time libraries
```

> ⚠️ Common mistake: `cjc` lives in `bin/` and `cjpm` lives in `tools/bin/` — **both** must go on your PATH (next step handles them together).

### Step 2: Configure environment variables (3 minutes)

Environment variables are the computer's "address book" — they tell it where to find tools. Append these three lines to `~/.bashrc` (the file your terminal reads on every launch):

```bash
cat >> ~/.bashrc <<'EOF'

# ---- Cangjie SDK ----
export CANGJIE_HOME="$HOME/tools/cangjie"
export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$PATH"
export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
EOF
source ~/.bashrc
```

What each line does (**and what breaks without it**):

| Variable | Purpose | If missing |
|---|---|---|
| `CANGJIE_HOME` | remembers where the SDK lives (other tools ask it) | some tools cannot find the SDK |
| `PATH` | lets you type `cjc` and `cjpm` directly | `cjc: command not found` |
| `LD_LIBRARY_PATH` | lets programs find the runtime `.so` files | `error while loading shared libraries` |

### Step 3: Verify the SDK (1 minute)

```bash
cjc --version
# expected: Cangjie Compiler: 1.0.5 (cjnative)

cjpm --version
# expected: Cangjie Package Manager: 1.0.5
```

Seeing version numbers means the SDK is installed! (Version 1.0.5 or newer.)

### Step 4: Get the zhc source code (2 minutes)

zhc is open source — use `git` to download it:

```bash
git clone <this-repository-url> ~/code/zwCangjie
cd ~/code/zwCangjie/zhc
```

Inside the source lives a magical directory called `lang-packs/` — **the word tables themselves**:

```
zhc/lang-packs/zh/
├── keywords.toml        # keyword table: one "dialect word → official word" per line
├── stdlib.toml          # standard-library aliases: dialect API name → official API name
├── module_paths.toml    # module path mapping: dialect path → official path
├── errors.toml          # error messages: Chinese templates for 645 diagnostic codes
└── ui.toml              # tool UI copy
```

> 💡 **A little secret**: zhc's "Chinese ability" lives entirely in these **data files**, not hard-coded. Swap in another word table and you get another dialect — the Russian table writes Russian Cangjie (a demo pack ships in the repo). Each pack is a doorway.

### Step 5: Build zhc (3-10 minutes)

In the `zhc/` directory (the first build compiles dependencies — be patient):

```bash
cjpm build
```

Success looks like this — the artifact exists and is executable:

```bash
ls -l target/release/bin/main
# expected: -rwxr-xr-x ... target/release/bin/main
```

The build artifact is called `main` — that IS zhc. Copy it to `~/.local/bin` under its proper name and put it on your PATH:

```bash
mkdir -p ~/.local/bin
cp target/release/bin/main ~/.local/bin/zhc
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Step 6: Let zhc find the language packs (2 minutes)

zhc searches for language packs in order (any one match is enough): the `ZHC_LANG_PACKS` variable → `./lang-packs/` in the current directory → `lang-packs/` next to the executable → `~/.zhc/lang-packs/`.

For a source build, option 1 is recommended (explicit, independent of your working directory):

```bash
echo 'export ZHC_LANG_PACKS="$HOME/code/zwCangjie/zhc"' >> ~/.bashrc
source ~/.bashrc
```

### Step 7: Verify the installation (1 minute)

```bash
zhc --help
```

When you see the help text (`zhc init 生成项目骨架`… — the tool's own messages follow your `ZHCLANG` language), you are done! Then run a real program:

```bash
cd ~/code/zwCangjie/zhc/examples
zhc run hello.zc
```

Expected output:

```
✅ Compile OK: replaced 2 dialect identifier(s).
你好，仓颉！
```

🎉 **Congratulations — your Cangjie environment is ready!** Starting with chapter 2, we write real programs.

> **Stuck? A mini troubleshooting table** (check in order)
>
> | Symptom | Cause | Fix |
> |---|---|---|
> | `cjc: command not found` | PATH not configured | redo step 2; confirm `source ~/.bashrc` ran |
> | `error while loading shared libraries` | LD_LIBRARY_PATH not configured | check line 3 of step 2 and the SDK path |
> | `uname -m` is not x86_64 | unsupported architecture | switch to a 64-bit system, or use the offline release bundle |
> | `zhc` cannot find a language pack | ZHC_LANG_PACKS not set | redo step 6; make sure the path contains `lang-packs/` |
>
> And remember the fastest first aid: **`zhc doctor`** — a one-shot environment self-check with localized fix guidance.

## 1.6 Hands-On Practice

1. Open a terminal and type `zhc --help`; write down the subcommands you recognize (e.g. `run`, `check`);
2. Open `~/code/zwCangjie/zhc/lang-packs/en/keywords.toml` (or any pack) and read a few "dialect word → official word" mappings to see what a word table looks like;
3. Run `zhc run hello.zc` in `examples` again — but first edit `hello.zc` (change the greeting to your own name) and run it once more. **You have just modified a program — you are a programmer.**

## ✳ A Thought on Programming: Break Big Problems into Small Steps

Behind the "programming = writing a recipe" metaphor hides the most important idea in programming: **decomposition**.

- Can't make scrambled eggs? Fine — break it into 6 steps, each trivial;
- Can't write a game? Fine — break it into "draw the screen → read the keys → compute → update the screen", then break each of those down again.

**Any complex problem, decomposed until every step is too simple to get wrong, can be finished.** This is a programmer's first move for every hard problem — when you get stuck later, ask yourself: can this be split smaller?

## 🍳 An Everyday Algorithm: Your Morning = Sequential Execution

The most basic structure in a program is **sequential execution**: top to bottom, one step at a time. Your every morning is a program:

```
1. Get up
2. Brush your teeth
3. Have breakfast
4. Pack your bag
5. Leave for school
```

This "recipe" has a few properties — the steps have an order, the order cannot be shuffled, and each step does one thing. **Computers execute programs exactly like this: one line at a time, faithfully.** Chapter 2 shows what sequential execution looks like inside a real program.

## Summary

- Computers are brilliant and dumb: they only understand `0` and `1`, and they need a "recipe" to do anything;
- Program = a recipe for the computer; a programming language plus a compiler (the translator) makes writing the recipe feel human;
- Cangjie was created by Chinese engineers — **zhc extends it to eight mother tongues**: keywords, function names, and error messages in the language you choose;
- Environment setup in 7 steps: check the environment → install the SDK → configure variables → verify the SDK → get the source → build zhc → verify it runs;
- The first idea of programming: **break big problems into small steps** (decomposition).

## Questions to Think About

1. In your own words: why can't a computer directly understand "make me a game"?
2. What role does each play: the compiler, zhc, the language pack? (Hint: translator, translator's assistant, word table.)
3. If you had to write "brew a cup of tea" as a recipe, what is the minimum number of steps? Try to make each step simple enough for a computer to follow.
4. Why write the environment variables into `~/.bashrc` instead of typing them every time? (Hint: recipes get re-executed.)
