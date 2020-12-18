
/// Returns `f(x!)` if `x != nil`, or `nil` otherwise.
public func given<T, U>(_ x: T?, _ f: (T) throws -> U) rethrows -> U? { return try x.map(f) }
