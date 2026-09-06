<!-- zhc-i18n 源: docs/中文仓颉程序设计/第2卷-核心与进阶/12-结构体与类.md 基线: 12bd193040c6e236 时间: 2026-09-06 -->

Language：[中文原版](../../../../docs/中文仓颉程序设计/第2卷-核心与进阶/12-结构体与类.md) · **English** · [English quick start](../en/README.md) · [日本語チュートリアル](../ja/tutorial-00.md)

# Chapter 12 Structs and Classes

> **What you will learn in this chapter**: master the two ways of organizing data — `struct` (value semantics) and `class` (reference semantics); understand the explicit design of open/override/interface/polymorphism; write safe object-oriented code with properties and type tests.
> **After this chapter you can answer**: How do structs and classes differ? Why are Cangjie classes uninheritable by default? What happens if you forget `override`?

---

## Opening Story: Things That Belong Together, Bundled Together

To describe a point you need x and y. Writing two separate variables means forever remembering "x goes with y". A **struct** bundles related data into one whole — like a **medical check-up form** that fixes height, weight, and eyesight together:

```cangjie
struct Point {
    public var x: Int64
    public var y: Int64
    init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }
    public func distanceSquared(): Int64 {
        return this.x * this.x + this.y * this.y
    }
}

main() {
    let origin = Point(3, 4)
    println("coordinates (${origin.x}, ${origin.y})")
    println("squared distance to origin: ${origin.distanceSquared()}")
}
```

- `struct Point`: defines a "point"-shaped box holding x and y;
- `init(...)`: the **constructor** — putting the ingredients in when the box is made;
- `this`: refers to "this very box"; `this.x` means "the x inside myself";
- `Point(3, 4)`: builds a point with x=3, y=4 from the blueprint (Pythagoras: 3²+4²=25, prints 25).

**Classes** look a lot like structs but are more powerful — the coolest part is **inheritance**: a dog is a kind of animal; a dog "inherits" everything from animal and adds its own traits:

```cangjie
open class Animal {
    public var name: String
    init(name: String) {
        this.name = name
    }
    public open func sound(): String { return "..." }
}

class Dog <: Animal {
    init(name: String) {
        super(name)
    }
    public override func sound(): String { return "Woof" }
}

main() {
    let wangcai = Dog("Wangcai")
    println("${wangcai.name} says: ${wangcai.sound()}")
}
```

- `class Dog <: Animal`: Dog "less-than-colon" Animal — **a Dog is a kind of Animal**, inheriting everything from it;
- `super(name)`: hands the name to the parent Animal to handle (borrowing the parent's constructor);
- `override`: Dog changes "sound" from "..." to "Woof" — an **override** (a covering redefinition).

> Why classes and inheritance? The real world is itself layered: "animal → dog", "vehicle → electric vehicle". Writing programs to match reality makes them understandable and extensible — adding a cat later needs no change to Animal, only a new `Cat` class. Why must `Animal` be marked `open`? Section 12.4 answers it.

## 12.1 Definition: Value Semantics vs Reference Semantics

**Definition**: two ways to bundle related data into a whole:

| | `struct` | `class` |
|---|---|---|
| Semantics | **value type**: assignment/passing is a **full copy** | **reference type**: assignment/passing **shares a reference** |
| After assignment | changing the copy **does not affect** the original | several variables point at **the same object**; change one, all see it |
| Capability | no inheritance, no polymorphism | inheritable, polymorphic (requires `open`) |
| Best for | small, independent, safety-critical data (coordinates, colors, amounts) | objects whose data is used from many places (student records, bank accounts) |

**Rule of thumb: small and independent → struct; polymorphism/sharing → class.**

## 12.2 Structs: Value Types

**Syntax**:

```cangjie
struct Point {
    public var x: Int64
    public var y: Int64

    init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }

    public func distanceSquared(): Int64 {
        return this.x * this.x + this.y * this.y
    }
}

main() {
    let origin = Point(3, 4)
    println("point: (${origin.x}, ${origin.y})")
    println("squared distance: ${origin.distanceSquared()}")   // 25

    var copy = origin                        // value semantics: a full copy
    copy.x = 100                            // only the copy changes
    println("${origin.x} ${copy.x}")           // 3 100 (origin unaffected)
}
```

**Notes**:

- `init` is the constructor; inside it, `this` refers to the current instance;
- Members are **private by default**; mark `public` for outside visibility;
- Structs **cannot inherit** and cannot have abstract members — the default choice for "small data + no polymorphism".

## 12.3 Classes: Reference Types

**Syntax**:

```cangjie
class Student {
    public var name: String
    public var score: Int64

    init(name: String, score: Int64) {
        this.name = name
        this.score = score
    }

    public func grade(): String {
        if (this.score >= 90) { return "Excellent" }
        return "Keep trying"
    }
}

main() {
    let xiaoming = Student("Xiaoming", 95)
    let xiaohong = xiaoming                        // reference semantics: the same object
    xiaohong.score = 70
    println("${xiaoming.name}: ${xiaoming.grade()}")   // Xiaoming: Keep trying (xiaoming changed too!)
}
```

**Notes**: fields are private by default (invisible outside the class); classes are **uninheritable** by default (requires `open`) — both are explicit safety designs.

## 12.4 open and override: Inheritance Is Closed by Default

**Definition**: inheritance breaks encapsulation (the subclass depends on the parent's internals), so Cangjie makes it **a privilege requiring explicit application** — `open` declares "I allow others to extend me", and `override` declares "I am indeed covering a parent method".

**Syntax**:

```cangjie
open class Animal {
    public open func sound(): String { return "..." }
}

class Dog <: Animal {
    public override func sound(): String { return "Woof" }
}

main() {
    let pet: Animal = Dog()       // a parent-typed variable holding a child object
    println(pet.sound())        // Woof (dynamic dispatch: the runtime picks the implementation)
}
```

**Three hard rules (tested on official 1.0.5)**:

| Rule | Consequence |
|---|---|
| Inheriting a non-`open` class | compile error "non-open type cannot be inherited" |
| Overriding a parent method not marked `open` | compile error (cannot override) |
| Overriding without the `override` keyword | compile error — `override` is **mandatory**, preventing the classic bug of "meant to override, typo'd into a new method" |

## 12.5 Inheritance and super

**Definition**: the "dog is an animal" IS-A relationship is expressed `class Dog <: Animal` (`<:` reads "is a subtype of"). The subclass inherits everything from the parent, and can call the parent constructor with `super(...)` or reuse parent logic via `super.method()`.

**Syntax**:

```cangjie
open class Animal {
    public var name: String
    init(name: String) { this.name = name }
    public open func introduce(): String { return "I am ${this.name}" }
}

class Dog <: Animal {
    init(name: String) {
        super(name)              // first statement: call the parent constructor
    }
    public override func introduce(): String {
        return "${super.introduce()}, a dog"    // reuse parent logic, then extend
    }
}

main() {
    println(Dog("Wangcai").introduce())   // I am Wangcai, a dog
}
```

**Notes**:

- Cangjie is **single-inheritance** (one class has exactly one parent);
- A subclass constructor **must call `super(...)` first**, before initializing its own fields;
- When a field and a constructor parameter share a name, you **must** use `this.` to distinguish — otherwise `name = name` assigns to itself and the field is never initialized (a compiler error).

## 12.6 Interfaces: Capability Lists

**Definition**: a pure behavioral contract — method signatures only (default implementations allowed), no state. A class can only single-inherit, but can implement **many interfaces** — interfaces are "capability lists".

**Syntax**:

```cangjie
interface Soundable {
    func sound(): String
}

class Dog <: Soundable {
    public func sound(): String { return "Woof" }
}

class Cat <: Soundable {
    public func sound(): String { return "Meow" }
}

main() {
    let pet: Soundable = Dog()
    let kitty: Soundable = Cat()
    println(pet.sound() + kitty.sound())   // WoofMeow
}
```

**Notes**: interface methods are **public** by default; `<:` serves both inheritance and interface implementation; the implementing class **must implement every method without a default** (missing one is a compile error); a variable of interface type can only call the methods the interface declares.

## 12.7 Abstract Classes and Statics

**Definition**: an **abstract class** = a marked "unfinished product" — it **cannot be instantiated** and exists only to be inherited; abstract methods have no body and force subclasses to implement them. **Static members** belong to **the class itself** (not instances).

**Syntax**:

```cangjie
abstract class Shape {
    public func area(): Float64        // abstract method: simply omit the body
}

class Square <: Shape {
    public var side: Float64
    init(side: Float64) { this.side = side }
    public override func area(): Float64 { return this.side * this.side }
}

class Utils {
    static func double(n: Int64): Int64 { return n * 2 }
    static var callCount: Int64 = 0
}

main() {
    println(Square(3.0).area())    // 9.0
    Utils.callCount += 1
    println(Utils.double(21))        // 42
}
```

**Notes**: abstract classes are **automatically open**; a subclass that doesn't implement all abstract methods must itself be marked `abstract`; static methods **cannot access instance fields/`this`**; a static mutable member is global state (synchronize under concurrency).

## 12.8 Properties: The Balance Point of Encapsulation

**Definition**: a **property**: read and written from outside like a field, but controlled inside by `get()` — "the data is visible but untamperable"; a **mutable property**: readable and writable, with `get()` and `set(value)` appearing as a pair.

**Syntax**:

```cangjie
class Book {
    private var titleValue: String = ""
    public prop title: String {
        get() { return this.titleValue }
    }
    init(title: String) { this.titleValue = title }
}

class Thermometer {
    private var celsiusValue: Float64 = 0.0
    public mut prop celsius: Float64 {
        get() { return this.celsiusValue }
        set(value) { this.celsiusValue = value }    // the parameter is the new value
    }
}

main() {
    let book = Book("Cangjie Dictionary")
    println(book.title)              // Cangjie Dictionary
    // book.title = "other"  ← compile error: the prop is read-only, cannot assign

    let meter = Thermometer()
    meter.celsius = 36.5               // goes through set
    println(meter.celsius)              // 36.5 (goes through get)
}
```

**Notes**: a `prop` is **read-only** — only `get()` may be defined; a `mut prop` must provide both `get()` and `set(value)`; the parentheses on `get()` **cannot be omitted** (official 1.0.5 syntax); the accessors live inside the class and may touch private fields.

## 12.9 mut: Struct Member Functions That Mutate

**Definition**: a struct is a value type, and a `let` binding is immutable — if a member function could quietly rewrite fields, copies would "change behind your back". `mut` turns "this function changes self" into a **visible permission**.

**Syntax**:

```cangjie
struct Counter {
    public var value: Int64
    init(value: Int64) { this.value = value }
    public mut func increment() {
        this.value += 1           // only a mut func may modify the struct itself
    }
}

main() {
    var counter = Counter(1)
    counter.increment()
    println(counter.value)               // 2
}
```

**Three hard rules (tested on official 1.0.5)**:

| Rule | Consequence |
|---|---|
| Calling a `mut` function on a `let`-bound instance | compile error (`let` is immutable; needs `var`) |
| Marking a class's method `mut` | compile error (class methods can modify fields naturally; `mut` is forbidden there) |
| `mut` on parameters/member variables/static functions | compile error (`mut` **only** decorates instance member functions of structs/interfaces) |

## 12.10 Type Testing and Casting (is / as)

**Definition**: holding a parent-typed variable and wondering whether it is really a certain subclass — `is` is the type test returning a Bool; `as` is the downcast returning an `Option<T>`.

**Syntax**:

```cangjie
open class Animal {}

class Dog <: Animal {
    public func wagTail(): String { return "wag wag" }
}

class Cat <: Animal {}

main() {
    let pet: Animal = Dog()            // upcast (child → parent): automatic, always safe
    if (pet is Dog) {             // `is`: the type test, returns a Bool
        println("it's a dog")
    }
    println(pet is Cat)               // false (runtime output keeps the official format)

    let wangcai = (pet as Dog).getOrThrow()   // downcast (parent → child): must use as
    println(wangcai.wagTail())
}
```

**Notes**: a downcast can fail (an Animal isn't necessarily a Dog) — `as` returns an **`Option<T>`** (failure is `None`); unwrap with `.getOrThrow()` or handle with `match`; the safer path is `is` first, then `as`; **numeric conversion and type-hierarchy conversion are two different things** (`Int64(3.9)` is numeric conversion, chapter 9).

## 12.11 Polymorphism and Dynamic Binding

**Definition**: a variable of interface/parent type can hold any implementing/child object, and calling a method **decides at runtime** which version runs — **program to the interface**: code depends on "abstraction", not "concrete".

**Syntax**:

```cangjie
interface Soundable {
    func sound(): String
}

class Dog <: Soundable {
    public func sound(): String { return "Woof" }
}

class Cat <: Soundable {
    public func sound(): String { return "Meow" }
}

func allSound(pets: Array<Soundable>) {
    for (pet in pets) {
        println(pet.sound())        // dynamic binding: each speaks its own sound
    }
}

main() {
    allSound([Dog(), Cat()])
}
```

**Notes**: polymorphism works only on **reference types** (classes/interfaces) — structs are value types with no dynamic binding; `open` + `override` + interface implementation together form the polymorphism trio.

## ✳ Design Ideas

**① Value vs reference semantics: first decide "how is this data shared"**. Struct assignment is a copy — for "small, independent, safety-critical" data; class instances share by reference — for objects "used from many places".

**② Closed by default: safe design makes inheritance expensive and explicit**. Inheritance breaks encapsulation — Cangjie requires `open` to inherit and `override` to cover, turning "extension points" into the class author's explicit decision: when writing a class, decide which parts are left open for others; the rest is sealed by default.

**③ Three levels of encapsulation**: `public var` (fully open) → `prop`/`mut prop` (data visible but reads/writes controlled) → `private` (fully hidden). Start with the simplest; upgrade to a property when validation/caching is needed — caller code doesn't change.

**④ Composition over inheritance**: structs can nest inside classes. Prefer composition ("has-a") where it expresses the relationship — inheritance suits "is-a" relationships with genuine polymorphism needs.

**⑤ Program to the interface**: `allSound` depends only on `Soundable`, knowing and caring nothing about dogs versus cats. Abstracting "the part that changes" into an interface is the core technique of extensibility.

**⑥ Explicit over implicit**: mandatory `override` prevents typo'd names, visible `mut` prevents copies changing behind your back, explicit `as` prevents type mismatches — Cangjie turns "places where mistakes can happen" into explicit compile-time checks.

## Exercises

1. Define a `struct Rectangle` (width/height + an `area()` method) and verify that assignment copies and the two are independent;
2. Define a `class Student` (name/score + `grade()`), keep 3 students in an `ArrayList`, iterate and print the average score;
3. Define an `interface Movable` (`move(distance: Int64)`), have `class Car` and `class Bicycle` implement it, and write a function that accepts an array of the interface and moves them all;
4. Add validation to the `Thermometer`'s `set`: accept only values between -50 and 150, otherwise throw;
5. Think: why does `let counter = Counter(1); counter.increment()` fail to compile, while `var counter` works?

## Summary

- `struct` value semantics (assignment copies), `class` reference semantics (assignment shares); fields are private by default;
- Inheritance and interface implementation use `<:`; inheritance and overriding need both the parent's `open` and the child's `override`;
- `super(...)` calls the parent constructor (must be the first statement), `super.method()` reuses parent logic; single inheritance, many interfaces;
- A `prop` is read-only, a `mut prop` is read-write (`get()`/`set(value)` in pairs); `mut` only decorates instance member functions of structs/interfaces;
- Enums can carry data and matching is forced exhaustive; `is` tests types, `as` downcasts (returning an `Option`);
- Polymorphism = interface/parent-typed variables + runtime dynamic binding, valid only for reference types.

## Questions to Think About

1. Why does Cangjie demand both the parent's `open` and the child's `override`? What bugs disappear when either is removed? (Hint: typo'd names, accidental inheritance.)
2. Struct assignment is a copy — do two variables point to the same data or to two independent pieces? Why does that make it "thread-safe"?
3. The `as` downcast returns an `Option` — why not the object directly, or an exception? (Hint: expected failure vs unexpected error, chapter 14.)
4. Polymorphism works only on reference types — why can't structs be polymorphic? What does "value types have no dynamic binding" imply?
