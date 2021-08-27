//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum AtomicError: Int, Error {
    case invalidTransition
}

// MARK: -

private class Atomics {
    fileprivate static let fairQueue = DispatchQueue(label: "Atomics")
    fileprivate static let unfairLock = UnfairLock()

    // Never instantiate this class.
    private init() {}

    class func perform<T>(isFair: Bool = false, _ block: () throws -> T) rethrows -> T {
        if isFair {
            return try fairQueue.sync(execute: block)
        } else {
            return try unfairLock.withLock(block)
        }
    }
}

// MARK: -

// Provides Objective-C compatibility for the most common atomic value type.
@objc
public class AtomicBool: NSObject {
    private let value = AtomicValue<Bool>(false)

    @objc(initWithValue:)
    public required init(_ value: Bool) {
        self.value.set(value)
    }

    @objc
    public func get() -> Bool {
        value.get()
    }

    @objc
    public func set(_ value: Bool) {
        self.value.set(value)
    }

    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    private func transition(from fromValue: Bool, to toValue: Bool) throws {
        try value.transition(from: fromValue, to: toValue)
    }

    @objc
    public func tryToSetFlag() -> Bool {
        do {
            try transition(from: false, to: true)
            return true
        } catch {
            return false
        }
    }

    @objc
    public func tryToClearFlag() -> Bool {
        do {
            try transition(from: true, to: false)
            return true
        } catch {
            return false
        }
    }
}

// MARK: -

@objc
public class AtomicUInt: NSObject {
    private let value = AtomicValue<UInt>(0)

    @objc
    public required init(_ value: UInt = 0) {
        self.value.set(value)
    }

    @objc
    public func get() -> UInt {
        value.get()
    }

    @objc
    public func set(_ value: UInt) {
        self.value.set(value)
    }

    @discardableResult
    @objc
    public func increment() -> UInt {
        value.map { $0 + 1 }
    }

    @discardableResult
    @objc
    public func decrementOrZero() -> UInt {
        value.map { max($0, 1) - 1 }
    }

    @discardableResult
    @objc
    public func add(_ delta: UInt) -> UInt {
        value.map { $0 + delta }
    }
}

// MARK: -

public final class AtomicValue<T> {
    private var value: T

    public required convenience init(_ value: T) {
        self.init(value, allowOptionalType: false)
    }

    fileprivate init(_ value: T, allowOptionalType: Bool) {
        owsAssertDebug(allowOptionalType || Mirror(reflecting: value).displayStyle != .optional)
        self.value = value
    }

    public func get() -> T {
        Atomics.perform {
            self.value
        }
    }

    public func set(_ value: T) {
        Atomics.perform {
            self.value = value
        }
    }

    // Transform the current value using a block.
    @discardableResult
    public func map(_ block: @escaping (T) -> T) -> T {
        Atomics.perform {
            let newValue = block(self.value)
            self.value = newValue
            return newValue
        }
    }
}

// MARK: - 

extension AtomicValue: Codable where T: Codable {
    public convenience init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        self.init(try singleValueContainer.decode(T.self))
    }

    public func encode(to encoder: Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(value)
    }
}

// MARK: -

extension AtomicValue where T: Equatable {
    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    public func transition(from fromValue: T, to toValue: T) throws {
        try Atomics.perform {
            guard self.value == fromValue else {
                throw AtomicError.invalidTransition
            }
            self.value = toValue
        }
    }
}

// MARK: -

public final class AtomicOptional<T> {
    fileprivate let value = AtomicValue<T?>(nil, allowOptionalType: true)

    public required init(_ value: T?) {
        self.value.set(value)
    }

    public func get() -> T? {
        value.get()
    }

    public func set(_ value: T?) {
        self.value.set(value)
    }
}

extension AtomicOptional: Codable where T: Codable {
    public convenience init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()

        if singleValueContainer.decodeNil() {
            self.init(nil)
        } else {
            self.init(try singleValueContainer.decode(T.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(value)
    }
}

extension AtomicOptional where T: Equatable {

    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    public func transition(from fromValue: T?, to toValue: T?) throws {
        try value.transition(from: fromValue, to: toValue)
    }

    public func setIfNil(_ newValue: T) throws {
        try value.transition(from: nil, to: newValue)
    }

    public func tryToSetIfNil(_ newValue: T) -> Bool {
        do {
            try setIfNil(newValue)
            return true
        } catch {
            return false
        }
    }

    public func clearIfEqual(_ oldValue: T) throws {
        try value.transition(from: oldValue, to: nil)
    }

    public func tryToClearIfEqual(_ oldValue: T) -> Bool {
        do {
            try clearIfEqual(oldValue)
            return true
        } catch {
            return false
        }
    }
}

// MARK: -

public class AtomicArray<T> {

    private var values: [T]

    public required init(_ values: [T] = []) {
        self.values = values
    }

    public func get() -> [T] {
        Atomics.perform {
            values
        }
    }

    public func set(_ values: [T]) {
        Atomics.perform {
            self.values = values
        }
    }

    public func append(_ value: T) {
        Atomics.perform {
            values.append(value)
        }
    }

    public var first: T? {
        Atomics.perform {
            values.first
        }
    }

    public var popHead: T? {
        Atomics.perform {
            guard !values.isEmpty else {
                return nil
            }
            return values.removeFirst()
        }
    }

    public func pushTail(_ value: T) {
        append(value)
    }
}

extension AtomicArray where T: Equatable {
    public func remove(_ valueToRemove: T) {
        Atomics.perform {
            self.values = self.values.filter { (value: T) -> Bool in
                valueToRemove != value
            }
        }
    }
}

// MARK: -

public class AtomicDictionary<Key: Hashable, Value> {
    private var values: [Key: Value]

    public required init(_ values: [Key: Value] = [:]) {
        self.values = values
    }

    public subscript(_ key: Key) -> Value? {
        set { Atomics.perform { self.values[key] = newValue } }
        get { Atomics.perform { self.values[key] } }
    }

    public func pop(_ key: Key) -> Value? {
        Atomics.perform {
            guard let value = self.values[key] else { return nil }
            self.values[key] = nil
            return value
        }
    }

    public func get() -> [Key: Value] {
        Atomics.perform { self.values }
    }

    public func set(_ values: [Key: Value]) {
        Atomics.perform { self.values = values }
    }
}

// MARK: -

public class AtomicSet<T: Hashable> {
    private var values = Set<T>()

    public required init() {}

    public func insert(_ value: T) {
        Atomics.perform { _ = self.values.insert(value) }
    }

    public func contains(_ value: T) -> Bool {
        Atomics.perform { self.values.contains(value) }
    }
}
