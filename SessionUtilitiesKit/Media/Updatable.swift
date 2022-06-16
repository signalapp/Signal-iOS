// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum Updatable<Wrapped>: ExpressibleByNilLiteral {
    /// A cleared value.
    ///
    /// In code, the cleared of a value is typically written using the `nil`
    /// literal rather than the explicit `.remove` enumeration case.
    case remove
    
    /// The existing value, this will leave whatever value is currently available.
    case existing

    /// An updated value, stored as `Wrapped`.
    case update(Wrapped)
    
    // MARK: - ExpressibleByNilLiteral
    
    public init(nilLiteral: ()) {
        self = .remove
    }
    
    public static func updateIf(_ maybeValue: Wrapped?) -> Updatable<Wrapped> {
        switch maybeValue {
            case .some(let value): return .update(value)
            default: return .existing
        }
    }
    
    public static func updateTo(_ maybeValue: Wrapped?) -> Updatable<Wrapped> {
        switch maybeValue {
            case .some(let value): return .update(value)
            default: return .remove
        }
    }
    
    // MARK: - Functions
    
    public func value(existing: Wrapped) -> Wrapped? {
        switch self {
            case .remove: return nil
            case .existing: return existing
            case .update(let newValue): return newValue
        }
    }
    
    public func value(existing: Wrapped) -> Wrapped {
        switch self {
            case .remove: fatalError("Attempted to assign a 'removed' value to a non-null")
            case .existing: return existing
            case .update(let newValue): return newValue
        }
    }
}

// MARK: - Coalesing-nil operator

public func ?? <T>(updatable: Updatable<T>, existingValue: @autoclosure () throws -> T) rethrows -> T {
    switch updatable {
        case .remove: fatalError("Attempted to assign a 'removed' value to a non-null")
        case .existing: return try existingValue()
        case .update(let newValue): return newValue
    }
}

public func ?? <T>(updatable: Updatable<T>, existingValue: @autoclosure () throws -> T?) rethrows -> T? {
    switch updatable {
        case .remove: return nil
        case .existing: return try existingValue()
        case .update(let newValue): return newValue
    }
}

public func ?? <T>(updatable: Updatable<Optional<T>>, existingValue: @autoclosure () throws -> T?) rethrows -> T? {
    switch updatable {
        case .remove: return nil
        case .existing: return try existingValue()
        case .update(let newValue): return newValue
    }
}

// MARK: - ExpressibleBy Conformance

extension Updatable {
    public init(_ value: Wrapped) {
        self = .update(value)
    }
}

extension Updatable: ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral, ExpressibleByStringLiteral where Wrapped == String {
    public init(stringLiteral value: Wrapped) {
        self = .update(value)
    }
    
    public init(extendedGraphemeClusterLiteral value: Wrapped) {
        self = .update(value)
    }
    
    public init(unicodeScalarLiteral value: Wrapped) {
        self = .update(value)
    }
}

extension Updatable: ExpressibleByIntegerLiteral where Wrapped == Int {
    public init(integerLiteral value: Int) {
        self = .update(value)
      }
}

extension Updatable: ExpressibleByFloatLiteral where Wrapped == Double {
    public init(floatLiteral value: Double) {
        self = .update(value)
    }
}

extension Updatable: ExpressibleByBooleanLiteral where Wrapped == Bool {
    public init(booleanLiteral value: Bool) {
        self = .update(value)
    }
}
