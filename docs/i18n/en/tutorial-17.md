<!-- zhc-i18n 源: docs/中文仓颉程序设计/第3卷-工程与思想/17-算法与数据结构.md 基线: ef5b71f9a299dd34 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第3卷-工程与思想/17-算法与数据结构.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 17 Algorithms and Data Structures

> **What you will learn in this chapter**: build algorithmic thinking — Big-O complexity, searching, sorting, stacks and queues, recursion and divide-and-conquer, hashing — all implemented in Cangjie and verified by running.
> **After this chapter you can answer**: Why is hash lookup O(1)? What is the precondition of binary search? Why must recursion have an "exit"?

---

## 17.1 Definition: Algorithms and Complexity (Big O)

**Definition**: an algorithm = a **step list** for solving a problem (the formal version of chapter 1's "recipe"); a data structure = an **organization form** for storing data (the containers of chapter 11 are ready-made). Complexity (Big O) measures how a algorithm's **time/space consumption grows** with data size:

| Big O | Name | Example | Feel at 10,000 items |
|---|---|---|---|
| O(1) | constant | hash lookup, array index | instant |
| O(log n) | logarithmic | binary search | 14 steps |
| O(n) | linear | sequential search, traversal | 10,000 steps |
| O(n log n) | linearithmic | quicksort | 130,000 steps |
| O(n²) | quadratic | bubble/selection sort | 100 million steps (getting slow) |

**Why it matters**: the same problem, different algorithms, runtimes differing by **orders of magnitude** — that is the value of studying algorithms. Estimating complexity before writing code is the first step of "performance awareness".

**Example: sequential search (O(n))**:

```cangjie
func linearSearch(list: Array<Int64>, target: Int64): Int64 {
    for (i in 0..list.size) {
        if (list[i] == target) { return i }
    }
    return -1        // not found
}

main() {
    println(linearSearch([3, 7, 2, 9, 5], 9))    // 3 (counting from 0)
    println(linearSearch([3, 7, 2, 9, 5], 8))    // -1
}
```

## 17.2 Binary Search: The O(log n) "Guess the Number" Strategy

**Definition**: in a **sorted** array, compare with the middle each time — too big, go left; too small, go right; each step halves the space. This is the principle of chapter 11's number-guessing game (2¹⁰ = 1024; 10 steps to guess 1..1000).

**Precondition**: **the array must be sorted** — binary search on an unsorted array is meaningless.

**Syntax**:

```cangjie
func binarySearch(list: Array<Int64>, target: Int64): Int64 {
    var low = 0
    var high = list.size - 1
    while (low <= high) {
        let mid = (low + high) / 2
        if (list[mid] == target) { return mid }
        else if (list[mid] < target) {
            low = mid + 1        // the target is in the right half
        } else {
            high = mid - 1        // the target is in the left half
        }
    }
    return -1
}

main() {
    let sorted = [1, 3, 5, 7, 9, 11, 13]
    println(binarySearch(sorted, 7))      // 3
    println(binarySearch(sorted, 2))      // -1 (not found)
}
```

**Notes**: `low <= high` is the loop condition (don't drop the equals); `mid = (low + high) / 2` uses integer division; every round must update `low` or `high` — otherwise it's an infinite loop. n items take at most `log₂(n)+1` steps.

## 17.3 Selection Sort: O(n²) "Pick the Smallest"

**Definition**: each round, **select the smallest** of the unsorted part and move it to the end of the sorted part — like picking the smallest card from your hand one at a time.

**Syntax**:

```cangjie
import std.collection.*
func selectionSort(list: Array<Int64>): Array<Int64> {
    var result = list |> collectArray      // copy (don't modify the original)
    for (i in 0..result.size) {
        var smallest = i
        for (j in i + 1..result.size) {
            if (result[j] < result[smallest]) { smallest = j }
        }
        if (smallest != i) {      // swap (the temp-box pattern from chapter 3)
            let temp = result[i]
            result[i] = result[smallest]
            result[smallest] = temp
        }
    }
    return result
}

main() {
    println(selectionSort([5, 2, 9, 1, 7]))    // [1, 2, 5, 7, 9]
}
```

**Notes**: two nested loops = O(n²); "pick the smallest + swap" is the core; `list |> collectArray` copies (consuming the iterator into a new array, chapter 11), keeping the original intact (functional discipline). **In daily work just use `sort` (chapter 11)** — writing your own sort is for understanding the principle.

## 17.4 Bubble Sort: O(n²) "Adjacent Swaps"

**Definition**: each round **compares neighbors** left to right, bubbling the large ones upward — like bubbles rising. Same O(n²) as selection sort but swaps more often (slightly slower; high teaching value).

**Syntax**:

```cangjie
import std.collection.*
func bubbleSort(list: Array<Int64>): Array<Int64> {
    var result = list |> collectArray      // copy (don't modify the original)
    for (i in 0..result.size) {
        for (j in 0..result.size - 1 - i) {
            if (result[j] > result[j + 1]) {
                let temp = result[j]
                result[j] = result[j + 1]
                result[j + 1] = temp
            }
        }
    }
    return result
}

main() {
    println(bubbleSort([5, 2, 9, 1, 7]))    // [1, 2, 5, 7, 9]
}
```

**Notes**: the inner bound `0..size-1-i` — the tail is already sorted each round, no need to re-compare (an optimization point); you can add a "no swap this round → end early" flag (best case O(n)).

## 17.5 Quicksort: O(n log n) Divide-and-Conquer

**Definition**: the **divide-and-conquer** idea — pick a "pivot", split the array into "smaller than pivot" and "greater or equal", recursively sort both halves. O(n log n) on average — the most widely used sort in practice.

**Syntax**:

```cangjie
import std.collection.*
func quickSort(list: Array<Int64>): Array<Int64> {
    if (list.size <= 1) { return list }       // exit: empty or single element is already sorted
    var less = ArrayList<Int64>()
    var greaterOrEqual = ArrayList<Int64>()
    for (i in 1..list.size) {                // the pivot is the first element
        if (list[i] < list[0]) {
            less.add(list[i])
        } else {
            greaterOrEqual.add(list[i])
        }
    }
    var result = ArrayList<Int64>()                    // the result accumulates in an ArrayList (arrays are fixed-length)
    for (item in quickSort(less |> collectArray)) { result.add(item) }
    result.add(list[0])
    for (item in quickSort(greaterOrEqual |> collectArray)) { result.add(item) }
    return result |> collectArray                       // finally back to an array
}

main() {
    println(quickSort([5, 2, 9, 1, 7]))    // [1, 2, 5, 7, 9]
}
```

**Notes**: **recursion has two mandatory parts** — the "exit" (`size <= 1`) and the "descent" (each call shrinks); `ArrayList |> collectArray` performs the ArrayList→Array conversion (consuming the iterator into a new array, chapter 11); putting `import` at the **top** of the file is the convention (this block already follows it).

## 17.6 Stack and Queue: Two Ways of "Queuing"

**Definition**: a **stack** (Stack) = last-in-first-out (LIFO) — like stacked plates, the last one placed is taken first; a **queue** (Queue) = first-in-first-out (FIFO) — like a lunch line, first come first served.

**Syntax** (simulated with an ArrayList):

```cangjie
import std.collection.{ArrayList}

struct Stack {
    public var data: ArrayList<Int64>
    init() { this.data = ArrayList<Int64>() }
    public func push(value: Int64) { this.data.add(value) }
    public func pop(): Option<Int64> {
        if (this.data.size == 0) { return None }
        let top = this.data[this.data.size - 1]
        this.data.remove(this.data.size - 1..this.data.size)
        return Some(top)
    }
    public func isEmpty(): Bool { return this.data.size == 0 }
}

main() {
    let plates = Stack()
    plates.push(1)
    plates.push(2)
    plates.push(3)
    println(plates.pop().getOrThrow())    // 3 (last in, first out)
    println(plates.pop().getOrThrow())    // 2
    println(plates.pop().getOrThrow())    // 1
}
```

**Notes**: classic stack uses — the function call stack (who called whom returns when), undo (Ctrl+Z), bracket matching; classic queue uses — task queues, message queues. `remove(range)` removes the last element (chapter 11: remove takes a range only).

## 17.7 Recursion: A Function Calling Itself

**Definition**: recursion = a function **calling itself** on a smaller version of the same problem. It is "divide-and-conquer" written another way — **split the big problem into small ones, then assemble the small answers into the big answer**.

**Syntax**:

```cangjie
func factorial(n: Int64): Int64 {
    if (n <= 1) { return 1 }          // exit: the smallest problem answered directly
    return n * factorial(n - 1)             // descent: the problem shrinks (n-1), the solution assembles (×n)
}

func fibonacci(n: Int64): Int64 {
    if (n <= 1) { return n }         // exit
    return fibonacci(n - 1) + fibonacci(n - 2)   // two smaller problems
}

main() {
    println(factorial(5))        // 120 (5×4×3×2×1)
    println(fibonacci(10))   // 55
}
```

**Notes**:

- **Both elements of recursion are indispensable**: the exit (the termination condition) + the descent (the problem shrinks) — without an exit = a stack-overflow crash;
- Recursion vs loops: recursive code is closer to the math (readable), loops perform better (no call overhead); for very deep recursion (tens of thousands), use a loop;
- Naive Fibonacci recursion recomputes massively (O(2ⁿ)) — optimize with a loop or memoization (exercise 4).

## 17.8 How Hashing Works: The Secret of O(1)

**Definition**: why is a HashMap O(1)? — a **hash function** turns the key (say the string "Wangcai") into a number (a bucket number), jumping straight to the right bucket. Looking up "how old is Wangcai" doesn't scan all entries — one hash computation locates it.

**Why O(1)**: however many entries there are, the hash function's computation takes the same time — "compute → jump to the bucket → take out" in three steps, independent of data volume.

**The costs** (recap of chapter 11):

- **Unordered**: the bucket number is decided by the hash, not the insertion order — hence no iteration-order guarantee;
- **Keys must be hashable**: strings and integers are naturally hashable; custom types implement `Hashable`;
- **Collisions**: two keys hashing to the same bucket — the HashMap resolves them internally with chains/open addressing; with many collisions it degrades toward O(n).

**Syntax** (word-frequency counting with a HashMap — the classic hash application):

```cangjie
import std.collection.{HashMap, ArrayList}

func wordFrequencies(text: String): HashMap<String, Int64> {
    var counts = HashMap<String, Int64>()
    let words = text.split(" ")
    for (word in words) {
        counts[word] = counts.get(word).getOrDefault({ => 0 }) + 1   // the counting pattern
    }
    return counts
}

main() {
    let counts = wordFrequencies("apple banana apple orange apple banana")
    for (word in counts.keys()) {
        println("${word}: ${counts[word]} time(s)")
    }
}
```

**Notes**: `counts.get(word).getOrDefault({ => 0 }) + 1` — "take the old value (0 if absent) → add 1 → put it back" is the standard counting trio (chapter 11).

## 17.9 Common Algorithm Templates

**Definition**: the "skeletons" of several high-frequency algorithms — memorize and apply:

```cangjie
import std.collection.{HashMap}
// Template 1: traversal sum (the piggy bank)
func arraySum(list: Array<Int64>): Int64 {
    var total = 0
    for (item in list) { total += item }
    return total
}

// Template 2: find the maximum (the tournament)
func findMax(list: Array<Int64>): Option<Int64> {
    if (list.size == 0) { return None }
    var largest = list[0]
    for (item in list) {
        if (item > largest) { largest = item }
    }
    return Some(largest)
}

// Template 3: counting (the grouping pattern of chapter 11)
func count(list: Array<Int64>): HashMap<Int64, Int64> {
    var counts = HashMap<Int64, Int64>()
    for (item in list) {
        counts[item] = counts.get(item).getOrDefault({ => 0 }) + 1
    }
    return counts
}

main() {
    println(arraySum([1, 2, 3, 4]))       // 10
    println(findMax([3, 7, 2, 9]).getOrThrow())   // 9
    println(count([1, 2, 1, 3, 1]).size)  // 3 (three distinct numbers)
}
```

**Notes**: an empty list has no "maximum" — return an `Option` (expected failures use Options, chapter 14); think through a template's edges (empty, single element, all identical).

## Exercises

1. Implement binary search with a `while` loop (no ranges — practice hand-written loop control);
2. Add a `descending: Bool = false` parameter to `selectionSort` for descending order;
3. Use a stack to simulate "bracket matching": `"(()())"` succeeds, `"(()"` fails (hint: push on `(`, pop on `)`; an empty stack at the end means matched);
4. Implement Fibonacci with a loop (non-recursive) and compare performance against the recursive version;
5. Challenge: implement "binary insertion sort" — locate the insertion point with binary search, and analyze its complexity.

## Summary

- Big O measures trends: O(1) < O(log n) < O(n) < O(n log n) < O(n²);
- Binary search: a **sorted** array halves each step (O(log n)); the loop condition is `low <= high`;
- Selection/bubble sort: O(n²), for understanding the principle — in daily work use `sort`;
- Quicksort: divide-and-conquer + recursion, O(n log n) on average; **recursion = exit + descent**;
- Stack LIFO (push/pop), queue FIFO; the secret of hash O(1) is the hash function locating directly;
- The counting trio: `counts.get(key).getOrDefault({ => 0 }) + 1`.

## Questions to Think About

1. Why does binary search require a sorted array? What happens on an unsorted one? (Hint: the comparison result loses its directional meaning.)
2. Give a real-life example of a stack and of a queue; why does the function call use a stack? (Hint: the last called returns first.)
3. What happens with `factorial(10000)`? What does the recursion depth limit protect?
4. Is lookup still O(1) when hashes collide? When does a HashMap degrade? (Hint: the collision chain grows.)
