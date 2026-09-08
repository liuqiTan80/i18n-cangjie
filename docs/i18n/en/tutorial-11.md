<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/11-集合与容器.md 基线: efb02e72ee1e5f8d 时间: 2026-09-08-->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/11-集合与容器.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 11 Collections and Containers

> **What you will learn in this chapter**: master the three containers — ArrayList (dynamic list), HashMap (key-value pairs), HashSet (dedup) — and learn declarative data processing with `map`/`filter`/`fold`/`sort`.
> **After this chapter you can answer**: When do you use an ArrayList versus a HashMap? What happens when you read a missing key? Why doesn't `map` produce results immediately?

---

## Opening Story: What If One Box Isn't Enough?

The scores of 45 classmates — surely not 45 variables? An **ArrayList** (a dynamic list) is the "backpack" built for carrying a long string of things:

```cangjie
import std.collection.{ArrayList}

main() {
    var scores = ArrayList<Int64>()
    scores.add(95)
    scores.add(88)
    scores.add(76)
    println("there are ${scores.size} scores")
    println("the first score: ${scores[0]}")
}
```

- `ArrayList<Int64>()`: an empty backpack dedicated to holding integers;
- `scores.add(95)`: drop one into the backpack;
- `scores.size`: count how many there are (read directly as a property — no parentheses);
- `scores[0]`: take the first one (**counting starts at 0** — 0 is the first, 1 is the second; that's the programming convention).

But "find by position" is sometimes not enough: you want to type "Wangcai" and instantly know its age — looking up by name is more natural. A **HashMap** (a dictionary) is the roll-call book — one slot for the **key** (the name), one for the **value** (the information):

```cangjie
import std.collection.{HashMap}

main() {
    var petAges = HashMap<String, Int64>()
    petAges["Wangcai"] = 3
    petAges["Mimi"] = 5
    let wangcaiAge = petAges["Wangcai"]
    println("Wangcai is ${wangcaiAge}")
    println("the household has ${petAges.size} pets")
}
```

> Analogy: an ArrayList is like **a queue** (the 0th, the 1st… found by order); a HashMap is like a **roll-call book** (found by name, no queue needed).

These two intuitions are the heart of this chapter: first decide "what am I looking up, and by what", then pick the container. What happens when you read a missing key? Section 11.3 answers it.

## 11.1 Definition: Three Containers, Three Questions

**Definition**: a container = a "backpack" for a long run of data. Decide "what am I looking up, by what" first, then pick the container — that matters far more than memorizing APIs:

| Container | Official | Question it answers | Cost |
|---|---|---|---|
| `Array`/`ArrayList` | Array/ArrayList | "what do I store, in order" | lookup requires O(n) traversal |
| `HashMap` | HashMap | "what does this key map to" | unordered; keys must be hashable |
| `HashSet` | HashSet | "is this value present" | unordered; no duplicates |

- **Array** (chapter 9): fixed length, cannot grow or shrink;
- **ArrayList**: a list that grows and shrinks dynamically — use it when you don't know how many elements are coming (**the default choice for dynamic lists**);
- **HashMap**: a `key → value` table, look up data by name, O(1) on average;
- **HashSet**: you only care "is it there", elements are unique, `contains` is O(1).

## 11.2 ArrayList: The Dynamic List

**Syntax**:

```cangjie
import std.collection.{ArrayList}
main() {
    var scores = ArrayList<Int64>()
    scores.add(95)               // append = add
    scores.add(88)
    scores.add(76)
    println(scores.size)           // 3 (size is a property — no parentheses)
    println(scores[0])             // 95 (index access)
    scores.remove(1..2)             // remove takes a range only: removes index 1 (88)
    println(scores.size)           // 2
    for (score in scores) {
        println("score: ${score}")   // iterate
    }
}
```

**Notes (error-prone)**:

- `size` is a **property**, not a method (`.size` — no parentheses; `.length` on strings/arrays is a property too);
- Out-of-bounds indexing **throws at runtime** (e.g. `scores[9]`) — check `size` before indexing;
- **ArrayList `remove` accepts a range only** (official remove(Range)): `remove(1..2)` removes 1 element, `remove(1..3)` removes 2; there is no remove-by-value — find the index first, then remove;
- Array ↔ ArrayList conversion: `ArrayList.from(array)`;
- Officially there is **no** `reversed` method — reverse by indexing backwards:

```cangjie
import std.collection.{ArrayList}
main() {
    let original = [1, 2, 3]
    var reversed = ArrayList<Int64>()
    for (i in 0..original.size) {
        reversed.add(original[original.size - 1 - i])   // from the last to the first
    }
    println(reversed[0])                      // 3 (the original container is untouched)
}
```

## 11.3 HashMap: Key-Value Pairs

**Syntax**:

```cangjie
import std.collection.{HashMap}
main() {
    var petAges = HashMap<String, Int64>()
    petAges["Wangcai"] = 3               // store: map[key] = value
    petAges["Mimi"] = 5
    println(petAges["Wangcai"])           // 3 (read: map[key])
    println(petAges.size)              // 2
    for (name in petAges.keys()) {      // keys() returns all keys — the standard way to walk a map
        println("${name} is ${petAges[name]}")
    }
}
```

**Notes (error-prone)**:

- **Reading a missing key throws at runtime** (`petAges["nobody"]` crashes) — check with `contains` first, or fall back with `getOrDefault`;
- Keys must be hashable: strings and integers naturally are; custom types must implement `Hashable` (chapter 12);
- **Iteration order is not guaranteed** (hashing is unordered): two walks of the same map may differ — never rely on order;
- To change a value: `map[key] = newValue`; to delete: `map.remove(key)` (by key — different from the ArrayList's range remove);
- `keys()` is a method (with parentheses) and returns a **view** — don't add or remove entries while iterating.

**Practicum: grouped counting** (officially there is no groupBy — hand-write it with a HashMap; "group name → count" is the standard pattern):

```cangjie
import std.collection.{ArrayList, HashMap}
main() {
    var scores = ArrayList<Int64>()
    scores.add(95); scores.add(45); scores.add(70)
    var groups = HashMap<String, Int64>()
    for (s in scores) {
        let group = if (s >= 60) { "pass" } else { "fail" }
        groups[group] = groups.get(group).getOrDefault({ => 0 }) + 1
    }
    println(groups.size)       // 2
    println(groups["pass"])    // 2
}
```

> `get(key)` returns an `Option`, and `.getOrDefault({ => 0 })` starts from 0 when the key is absent — the standard idiom for counting (`Option` in full in chapter 14).

## 11.4 HashSet: A Collection Without Duplicates

**Syntax**:

```cangjie
import std.collection.{HashSet}
main() {
    var read = HashSet<Int64>()
    read.add(1)
    read.add(1)            // duplicate — ignored
    read.add(2)
    println(read.size)       // 2
    println(read.contains(2))    // true
}
```

**Typical use: deduplication** (officially there is no distinct method — a HashSet dedupes naturally):

```cangjie
import std.collection.{ArrayList, HashSet}
main() {
    var roster = ArrayList<Int64>()
    roster.add(1); roster.add(2); roster.add(1)
    var unique = HashSet<Int64>()
    for (n in roster) { unique.add(n) }   // the duplicate 1 is ignored
    println(unique.size)       // 2
}
```

**Notes**: a HashSet is **unordered** (original order not preserved); for "order-preserving dedup" hand-write a loop with a `contains` check (`if (!result.contains(n)) { result.add(n) }`).

## 11.5 Higher-Order Functions: map / filter / forEach

**Definition**: three high-frequency "declarative" operations, written with the pipe `container |> function`:

| Operation | Effect | Returns |
|---|---|---|
| `map({ x => ... })` | transform every element | a lazy iterator |
| `filter({ x => ... })` | keep the elements that satisfy the condition | a lazy iterator |
| `forEach({ x => ... })` | perform an action on each element (printing etc.) | Unit |

```cangjie
import std.collection.*
main() {
    var roster = ArrayList<Int64>()
    roster.add(1); roster.add(2); roster.add(3)
    // map: every element ×2
    let doubled = roster |> map({ x => x * 2 }) |> collectArray
    println(doubled[0])                // 2
    // filter: keep those ≥60
    var scores = ArrayList<Int64>()
    scores.add(95); scores.add(45); scores.add(70)
    let passing = scores |> filter({ x => x >= 60 }) |> collectArray
    println(passing.size)              // 2
    // forEach: action only, no result
    var names = ArrayList<String>()
    names.add("A"); names.add("B")
    names |> forEach({ name => println("hello, ${name}") })
}
```

**Three truths**:

- **Lazy**: `map`/`filter` return **iterators** — nothing is computed yet; `|> collectArray` consumes them and computes one by one (memory-efficient, chains compose infinitely);
- **The original container is untouched**: they produce new sequences without modifying the source;
- `forEach` returns Unit and is equivalent to a `for` loop (pure preference); lambdas **cannot use** `break`/`continue` (they are not loops) — when you need early exit, use `for`.

## 11.6 fold / reduce / sort

**Definition**: `fold`: accumulate from an initial value, one element at a time; `reduce`: no initial value — start from the first element (an empty container returns an `Option`); `sort`: **in-place** (it modifies the original array directly).

**Syntax**:

```cangjie
import std.collection.*
import std.sort.*
main() {
    // fold: the initial value 0 decides the return type
    var scores = ArrayList<Int64>()
    scores.add(95); scores.add(85)
    let total = scores |> fold(0, { acc, s => acc + s })
    println(total)                   // 180

    // reduce: no initial value, returns an Option (empty container → None)
    let total2 = scores |> reduce({ acc, s => acc + s })
    println(total2.getOrThrow())     // 180

    // sort: modifies the array in place; a top-level function
    var scores2 = [88, 95, 70]
    sort(scores2)                       // in-place ascending
    println(scores2[0])                  // 70
    sort(scores2, descending: true)             // in-place descending (descending is a named argument)
    println(scores2[0])                  // 95
}
```

**Notes**:

- `sort` accepts an **Array** and requires comparable elements; an ArrayList must be `collectArray`-ed first (or converted the other way with `ArrayList.from(array)`);
- The older official API `stableSort` is deprecated — express "equal elements keep their original order" with `sort(data, stable: true)`;
- Want to keep the original data? Copy it before sorting.

## ✳ Design Ideas

**① Choosing a container is a "data structure" decision**: decide "what am I looking up, by what" first, then choose — by order → ArrayList; by name → HashMap; only presence → HashSet.

**② Mutability discipline: in-place vs new containers**: `sort` modifies in place (no new value produced), while `map`/`filter` produce new sequences (the source untouched). Functional style prefers the latter — the original data is "input" and won't be silently changed, which keeps debugging light.

**③ Declarative > imperative**: `scores |> filter({ x => x >= 60 }) |> collectArray` reads exactly as "filter out the failing scores, collect into an array" — the intent is stated outright; a hand-written loop makes the reader "translate" the intent themselves. Declarative code separates "what" from "how".

**④ Lazy evaluation: compute as much as consumed**: iterators don't compute everything up front; in a chain, each element passes through the pipeline once — that is the answer to "why doesn't map produce a result": it hasn't been consumed yet.

## Exercises

1. Implement a small "word → definition" dictionary with `HashMap` (at least 3 entries), and use `keys()` to iterate and print all of them;
2. Collect the even numbers from 1..100 into an `ArrayList`, then `fold` their total (hint: `filter({ x => x % 2 == 0 })`);
3. Store 3 students' scores in an `ArrayList`, `sort` them, and print from high to low (hint: `descending: true`);
4. Think: why must the result of `map` go through `collectArray` before reuse? What would printing the iterator directly show?
5. Challenge: turn the 11.3 grouping into four buckets by score band (excellent/good/pass/fail).

## Summary

- Three containers: ArrayList (dynamic list — `remove` takes a range only), HashMap (key-value pairs — a missing key **throws**), HashSet (dedup);
- The higher-order pipeline: `container |> map/filter/forEach/fold/reduce |> collectArray` — lazy, source untouched;
- `sort` is a top-level function (`import std.sort.*`), in-place, with `descending`/`stable` named arguments;
- Runtime output keeps the official format (`true` → `true`).

## Questions to Think About

1. Looking up a value: an array takes O(n) traversal, a HashMap O(1) — why is the HashMap faster, and what does it cost? (Hint: unordered + keys must be hashable.)
2. How many elements does `scores.remove(1..2)` remove? And `remove(1..3)`? (Hint: half-open range.)
3. HashMap iteration order can differ every run — how do you avoid order-dependent bugs?
4. Why can't a lambda use `break`/`continue`? What do you do when you need early exit?
