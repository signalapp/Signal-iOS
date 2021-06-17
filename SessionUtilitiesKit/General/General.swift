
/// Does nothing, but is never inlined and thus evaluating its argument will never be optimized away.
///
/// Useful for forcing the instantiation of lazy properties like globals.
@inline(never)
public func touch<Value>(_ value: Value) { /* Do nothing */ }

/// Returns `f(x!)` if `x != nil`, or `nil` otherwise.
public func given<T, U>(_ x: T?, _ f: (T) throws -> U) rethrows -> U? { return try x.map(f) }

public func with<T, U>(_ x: T, _ f: (T) throws -> U) rethrows -> U { return try f(x) }
