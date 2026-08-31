macro package define
import std.ast.*

public macro dprint(input: Tokens): Tokens {
    let inputStr = input.toString()
    return quote(
        print($(inputStr) + " = ")
        println($(input)))
}
