<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/20-扩展与运算符重载.md 基线: 5be458b7795902b8 时间: 2026-09-06 -->

Language：[Chinese original](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/20-扩展与运算符重载.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 20 Extensions and Operator Overloading

> **What you will learn in this chapter**: master the two keys to "adding behavior to a type without touching its source" — `extend` (bolt-on methods / interface implementations) and `operator` overloading (letting your own types support `+`, `==`, `[]` and other native syntax). Understand how they divide labor with inheritance/override (chapter 12), and write custom types that read like "built-in language types".
> **After this chapter you can answer**: Why are extensions "bolt-on"? Can an extension add stored fields? Can `+=` be overloaded directly? What should you think through before overloading `+` for your type?

---

## 20.1 From Idea to Practice: Why Extensions Exist

Section 16.9 covered the idea: classic OO "modifying a class" has two pains — **no permission to modify** (the standard library, someone else's class) and **modifying affects everyone** (the fragile base class). `extend` turns "adding behavior" into a **bolt-on** operation: each module attaches methods only to the types it cares about, with no interference.

This chapter turns the idea into muscle memory. Start with the most direct example — attaching methods to the official integer type:

```cangjie
// Extension methods: attach bolt-on methods to an official type (without modifying it)
extend Int64 {
    public func doubled(): Int64 { return this * 2 }
    public func isEven(): Bool { return this % 2 == 0 }
}

main() {
    let n = 21
    println("${n} doubled = ${n.doubled()}")
    println("is ${n} even? ${n.isEven()}")
    println("100 doubled = ${100.doubled()}")
}
```

Run result:

```
21 doubled = 42
21 is even? false
100 doubled = 200
```

Three points:

1. `extend Type { ... }` is written exactly like a class body — methods and property accessors all allowed;
2. Inside the methods, `this` accesses "the extended value": in `n.doubled()`, `n` IS `this`;
3. Literals can call it directly: `100.doubled()` — because extensions apply to the **type**, not to a specific variable.

## 20.2 The Boundary of Extensions: Behavior Yes, State No

Extensions can attach **methods** (functions/property accessors) but cannot add **stored fields** to a type — the storage layout is fixed when the type is defined, and a bolt-on cannot change it.

| What you can do | What you cannot do |
|---|---|
| Add functions (methods) | Add `let`/`var` stored fields |
| Add property accessors (`get`/`set`) | Change the type's inheritance relationships (but you can retro-fit interface implementations, see 20.3) |
| Add operator overloads (see 20.4-20.6) | Access the original type's private members (visibility rules unchanged) |

This boundary is actually an **advantage**: extensions can only "add behavior", never "add state" — so extensions can never tangle two modules' state together. Each attaches its own methods without interference.

## 20.3 Extensions Implementing Interfaces: Giving Unrelated Types Common Behavior

Chapter 12 covered: an interface is a "capability contract", and `class Dog <: Soundable` declares the capability **when the class is defined**. But what if "someone else defined the classes, and I want to handle them uniformly"? — `extend X <: Interface`:

```cangjie
// Extension implements interface: giving "completely unrelated" types a common behavior (retrofitting)
interface Soundable {
    func sound(): String
}

class Dog {}
class Cat {}
class AlarmClock {}

extend Dog <: Soundable {
    public func sound(): String { return "Woof" }
}
extend Cat <: Soundable {
    public func sound(): String { return "Meow" }
}
extend AlarmClock <: Soundable {
    public func sound(): String { return "Ring ring" }
}

main() {
    let buddies: Array<Soundable> = [Dog(), Cat(), AlarmClock()]
    for (buddy in buddies) {
        println(buddy.sound())
    }
}
```

Run result:

```
Woof
Meow
Ring ring
```

Teaching points:

- `Dog`, `Cat`, and `AlarmClock` were defined with nothing in common, and **afterwards** three `extend … <: Soundable` blocks retro-fitted the same capability;
- Once the capability is retro-fitted, they can all be put into an `Array<Soundable>` and called uniformly — **polymorphism doesn't need to be planned in advance**;
- Scope: retro-fitting interfaces onto your own classes, or onto third-party library classes (provided the interface and the type are both visible in your module).

> **A thought tip**: extension-implements-interface is the strongest form of "composition over inheritance" — inheritance demands you **foresee the future** (think of every subclass while writing the class); extensions let you **buy the ticket anytime**. Many of the standard library's "dialect methods" (`trimAscii`/`split`, etc.) are attached to strings/collections precisely through the extension mechanism.

## 20.4 Operator Overloading: Making Your Type Support "+"

### 20.4.1 Member-Style Overloading

First, declaring an operator directly in a class — giving a vector class its own `+` and `==`:

```cangjie
// Declaring operator overloads in the class: the class defines its own "+"
class Vector {
    public let x: Int64
    public let y: Int64
    init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }

    public operator func +(other: Vector): Vector {
        return Vector(this.x + other.x, this.y + other.y)
    }
    public operator func ==(other: Vector): Bool {
        return this.x == other.x && this.y == other.y
    }
}

main() {
    let a = Vector(1, 2)
    let b = Vector(3, 4)
    let c = a + b            // your class supports "+" for the first time
    println("a + b = (${c.x}, ${c.y})")
    println("a == b? ${a == b}")
    println("a == Vector(1, 2)? ${a == Vector(1, 2)}")
}
```

Run result:

```
a + b = (4, 6)
a == b? false
a == Vector(1, 2)? true
```

Anatomy of `public operator func +(...)`:

| Part | Meaning |
|---|---|
| `public` | may be omitted (visibility rules same as ordinary functions) |
| `operator` | declares this as an operator overload (written before the function name) |
| `func` | shares the `func` keyword with ordinary functions |
| `+` | the operator symbol being overloaded, written in the name position |
| `(other: Vector)` | parameter: the right operand of a binary operator (unary operators take none) |
| `: Vector` | return type: `+` usually returns a new object |

`a + b` is rewritten by the compiler into a call to `a.+(b)` — note **the left operand is the receiver**, so in the `==` overload `this` is the left-hand `a`.

### 20.4.2 What If You Don't Overload `==`?

The default `==` performs a **reference comparison** on classes (do the two variables point to the same object?), not a content comparison — two `Vector(1, 2)`s with identical contents are not equal. So "value-semantic classes" almost always overload `==`. This also explains the chapter 9 pitfall "custom classes inside an Option can't be compared directly": the essence is that the class never overloaded `==`.

**Note: `!=` is not automatically negated**. After overloading only `==`, writing `a != b` prompts you to add `operator func !=` (or use chapter 15's `@Derive(Equals)` to generate full equality in one stroke). When you need both, the classic form of `!=` is `return !(this == other)` — maintaining the logic in one place only.

## 20.5 Extension-Style Operators: No Class Changes, Behavior Still Bolted On

Operator overloading and extensions are **orthogonal** — they compose: add operators to someone else's class inside an `extend` block. This is the most common posture:

```cangjie
// Extension operators: no class changes, behavior still bolted on
class Point {
    public let x: Int64
    public let y: Int64
    init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }
}

extend Point {
    public operator func +(other: Point): Point {
        return Point(this.x + other.x, this.y + other.y)
    }
    public operator func ==(other: Point): Bool {
        return this.x == other.x && this.y == other.y
    }
    public operator func !(): Point {        // unary: symmetric about the origin
        return Point(-this.x, -this.y)
    }
    public operator func <(other: Point): Bool {   // comparing distance to origin (squared)
        return this.x * this.x + this.y * this.y
               < other.x * other.x + other.y * other.y
    }
}

main() {
    let a = Point(1, 2)
    let b = Point(3, 4)
    let c = a + b
    println("a + b = (${c.x}, ${c.y})")
    println("!a = (${(!a).x}, ${(!a).y})")
    println("a < b? ${a < b}")
}
```

Run result:

```
a + b = (4, 6)
!a = (-1, -2)
a < b? true
```

Note that unary operator calls need parentheses: `(!a).x` — because `!` binds looser than `.`, `!a.x` parses as `!(a.x)`.

### 20.5.1 Compound Assignment `+=`: Not Directly Overloadable, But Auto-Expanded

`+=`, `-=`, `*=` and friends **cannot be overloaded directly**. But the good news: as long as `+` is overloaded, `a += b` automatically expands into `a = a + b` — provided `a` is a `var` binding:

```cangjie
// Compound +=: not directly overloadable, but auto-expands once + is overloaded (a += b ⇒ a = a + b)
class Counter {
    public var value: Int64
    init(value: Int64) { this.value = value }
}
extend Counter {
    public operator func +(other: Counter): Counter {
        return Counter(this.value + other.value)
    }
}
main() {
    var a = Counter(10)
    a += Counter(5)        // equivalent to a = a + Counter(5)
    println("a's value = ${a.value}")
}
```

Run result:

```
a's value = 15
```

## 20.6 The Index Operator: Making Your Type Support `[]`

`[]` is the "get the element at this index" operator. Collections have it (`array[0]`) — custom types can too:

```cangjie
// The index operator []: subscript read/write support for custom types
class Duo {
    public let first: String
    public let second: String
    init(first: String, second: String) {
        this.first = first
        this.second = second
    }
}

extend Duo {
    public operator func [](index: Int64): String {
        if (index == 0) {
            return this.first
        }
        return this.second
    }
}

main() {
    let team = Duo("Amy", "Mei")
    println("place 1: ${team[0]}")
    println("place 2: ${team[1]}")
}
```

Run result:

```
place 1: Amy
place 2: Mei
```

`operator func []` in read-only form already makes `team[0]` work. Real containers (like chapter 11's collections) also pair `set` for a read-write version — but for teaching, remember: **give the read-only version first; it's enough and safe**.

## 20.7 The Discipline of Operator Overloading: What Can Be Overloaded, What Must Not Be Abused

### The overloadable operator surface (the common subset)

| Category | Operators | Parameters | Typical return |
|---|---|---|---|
| Arithmetic | `+` `-` `*` `/` `%` | 1 (right operand) | new object |
| Comparison | `==` `!=` `<` `>` `<=` `>=` | 1 | `Bool` |
| Unary | `!` (logical not/negate) | 0 | same type or Bool |
| Index | `[]` | 1 (index) | element type |

### The lines you must not cross

1. **No inventing new symbols**: you can only overload operators the language already has — `**` (power), `<>` (a self-invented angle pair) don't exist; overloading adds no syntax;
2. **No changing arity or precedence**: `+` is always binary with unchanged precedence — `a + b * c` still multiplies first;
3. **Not overloadable**: `=` (assignment), `&&`/`||` (short-circuit), `?:` (none in Cangjie), compound assignments like `+=` (auto-expanded);
4. **Semantic consistency**: `+` should be commutative (`a + b == b + a`), `==` should be reflexive (`a == a`) and complementary with `!=` — overloading `+` as "subtraction" won't bother the compiler, but readers of your code will go mad;
5. **Be careful overriding within inheritance hierarchies**: the compiler restricts "subclasses redefining parent operators" strictly (identical signature, and the parent needs `open`); for differentiated behavior **prefer extensions** over inheritance-based overrides — consistent with 16.9's "composition over inheritance".

> **A contrast to remember**: `override` changes a parent implementation **within an inheritance hierarchy** (chapter 12); `operator` extends the **behavioral surface of a type**. Different keywords, different scenarios — an operator overload appearing together with the `redefinition` modifier is a conflict; don't mix them.

## 20.8 Comprehensive Case: A Fraction Class

Combine the two keys of this chapter: a "behaviorally complete" fraction class (numerator/denominator) — add, subtract, multiply, and equality all supporting native syntax:

```cangjie
// Comprehensive case: the fraction class (arithmetic + equality comparison)
class Fraction {
    public let numerator: Int64
    public let denominator: Int64
    init(numerator: Int64, denominator: Int64) {
        this.numerator = numerator
        this.denominator = denominator
    }
}

extend Fraction {
    public operator func +(other: Fraction): Fraction {
        return Fraction(this.numerator * other.denominator + other.numerator * this.denominator,
                    this.denominator * other.denominator)
    }
    public operator func -(other: Fraction): Fraction {
        return Fraction(this.numerator * other.denominator - other.numerator * this.denominator,
                    this.denominator * other.denominator)
    }
    public operator func *(other: Fraction): Fraction {
        return Fraction(this.numerator * other.numerator, this.denominator * other.denominator)
    }
    public operator func ==(other: Fraction): Bool {
        return this.numerator * other.denominator == other.numerator * this.denominator
    }
}

main() {
    let half = Fraction(1, 2)
    let third = Fraction(1, 3)
    let sum = half + third
    let diff = half - third
    let product = half * third
    println("1/2 + 1/3 = ${sum.numerator}/${sum.denominator}")
    println("1/2 - 1/3 = ${diff.numerator}/${diff.denominator}")
    println("1/2 × 1/3 = ${product.numerator}/${product.denominator}")
    println("1/2 == 2/4? ${half == Fraction(2, 4)}")
}
```

Run result:

```
1/2 + 1/3 = 5/6
1/2 - 1/3 = 1/6
1/2 × 1/3 = 1/6
1/2 == 2/4? true
```

Note that `==` uses **cross multiplication** (`numerator1 × denominator2 == numerator2 × denominator1`) rather than field-by-field comparison — `1/2` and `2/4` are stored differently but equal in value, which is exactly the point: "overloading `==` defines your type's semantics of equality".

> **Authenticity**: every code block above was verified with `zhc run` (outputs shown in each section). Extensions + operators are the watershed of "the custom-type experience" — once the fraction class is done, your type feels as natural as `Int64` or `String`.

## Exercises

1. Extend `Int64` with a `factorial(): Int64` method (`n` factorial = `1 × 2 × … × n`, recursion allowed, see chapter 17) and verify `5.factorial()` is 120;
2. Add division `/` to the fraction class from 20.8 (multiply by the reciprocal) and write a `simplify()` method (divide numerator and denominator by their greatest common divisor, Euclid's algorithm), so `1/2 + 1/2` prints `1/1` instead of `2/4`;
3. Judge this: someone says "since extensions can add methods, they can also turn a `class` into a `struct` (switching the storage semantics)". Correct or not? Why? (Hint: the boundary table in 20.2.)

---

## Summary

- `extend` = a **bolt-on** that adds no storage, only behavior; `extend X <: Interface` lets existing types retroactively gain interface capabilities;
- `operator func +` and friends = native operator syntax for custom types, written inside the class or inside an `extend` block;
- `+=` cannot be overloaded directly but auto-expands once `+` is (needs a `var` binding); `[]` provides subscript reads;
- The discipline: no new symbols, no changed precedence/arity, consistent semantics, prefer extensions when inheritance-based overriding is limited;
- The division with chapter 12's `override`: `override` covers methods within an inheritance hierarchy; `operator` extends a type's behavioral surface.

## Questions to Think About

1. Why can't extensions add stored fields? If they could, what problems would appear? (Hint: think "type layout" and "multiple modules each extending".)
2. Overload `==` (compare by student id) and `<` (sort by student id) for chapter 12's `Student` class, and verify in `main` that `Student(1) == Student(1)` is true.
3. What is the division of labor between `@Derive(Equals)` (chapter 15) and hand-written `operator func ==`/`!=`? When would you rather hand-write? (Hint: `Derive` can only compare field-by-field; it cannot express custom equality semantics like cross multiplication.)
