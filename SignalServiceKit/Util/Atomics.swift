//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum AtomicError: Error {
    case invalidTransition
}

// MARK: -

extension UnfairLock {
    // The default lock shared by _all_ atomics.
    public static let sharedGlobal = UnfairLock()
}

// MARK: -

public final class AtomicBool: Sendable {
    private let value: AtomicValue<Bool>

    public init(_ value: Bool, lock: UnfairLock) {
        self.value = AtomicValue(value, lock: lock)
    }

    public func get() -> Bool {
        value.get()
    }

    public func set(_ value: Bool) {
        self.value.set(value)
    }

    public func swap(_ value: Bool) -> Bool {
        self.value.swap(value)
    }

    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    private func transition(from fromValue: Bool, to toValue: Bool) throws {
        try value.transition(from: fromValue, to: toValue)
    }

    public func tryToSetFlag() -> Bool {
        do {
            try transition(from: false, to: true)
            return true
        } catch {
            return false
        }
    }

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

public final class AtomicUInt: Sendable {
    private let value: AtomicValue<UInt>

    public init(_ value: UInt = 0, lock: UnfairLock) {
        self.value = AtomicValue(value, lock: lock)
    }

    public func get() -> UInt {
        value.get()
    }

    public func set(_ value: UInt) {
        self.value.set(value)
    }

    public func swap(_ value: UInt) -> UInt {
        self.value.swap(value)
    }

    @discardableResult
    public func increment() -> UInt {
        value.map { $0 + 1 }
    }

    @discardableResult
    public func decrementOrZero() -> UInt {
        value.map { max($0, 1) - 1 }
    }

    @discardableResult
    public func add(_ delta: UInt) -> UInt {
        value.map { $0 + delta }
    }
}

// MARK: -

public final class AtomicValue<T>: Sendable {
    private let lock: UnfairLock
    nonisolated(unsafe) private var value: T

    public init(_ value: T, lock: UnfairLock) {
        self.value = value
        self.lock = lock
    }

    public func get() -> T {
        lock.withLock {
            self.value
        }
    }

    public func set(_ value: T) {
        lock.withLock {
            self.value = value
        }
    }

    // Returns the old value.
    public func swap(_ value: T) -> T {
        lock.withLock {
            let oldValue = self.value
            self.value = value
            return oldValue
        }
    }

    // Transform the current value using a block.
    @discardableResult
    public func map(_ block: (T) -> T) -> T {
        lock.withLock {
            let newValue = block(self.value)
            self.value = newValue
            return newValue
        }
    }

    @discardableResult
    public func update<Result>(block: (inout T) throws -> Result) rethrows -> Result {
        try lock.withLock { try block(&self.value) }
    }
}

// MARK: -

extension AtomicValue where T: Equatable {
    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    public func transition(from fromValue: T, to toValue: T) throws {
        try lock.withLock {
            guard self.value == fromValue else {
                throw AtomicError.invalidTransition
            }
            self.value = toValue
        }
    }
}

// MARK: -

public final class AtomicOptional<T>: Sendable {
    fileprivate let value: AtomicValue<T?>

    public init(_ value: T?, lock: UnfairLock) {
        self.value = AtomicValue(value, lock: lock)
    }

    public func get() -> T? {
        value.get()
    }

    public func set(_ value: T?) {
        self.value.set(value)
    }

    // Returns the old value.
    public func swap(_ value: T?) -> T? {
        self.value.swap(value)
    }

    public func map(_ block: (T?) -> T?) -> T? {
        value.map(block)
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

public final class AtomicArray<T>: Sendable {
    private let lock: UnfairLock
    nonisolated(unsafe) private var values: [T]

    public init(_ values: [T] = [], lock: UnfairLock) {
        self.values = values
        self.lock = lock
    }

    public func get() -> [T] {
        lock.withLock {
            values
        }
    }

    public func set(_ values: [T]) {
        lock.withLock {
            self.values = values
        }
    }

    public func append(_ value: T) {
        lock.withLock {
            values.append(value)
        }
    }

    public func append(contentsOf newElements: some Sequence<T>) {
        lock.withLock {
            values.append(contentsOf: newElements)
        }
    }

    public var first: T? {
        lock.withLock {
            values.first
        }
    }

    public func popHead() -> T? {
        lock.withLock {
            guard !values.isEmpty else {
                return nil
            }
            return values.removeFirst()
        }
    }

    public func popTail() -> T? {
        lock.withLock {
            guard !values.isEmpty else {
                return nil
            }
            return values.removeLast()
        }
    }

    public func pushTail(_ value: T) {
        append(value)
    }

    public func pushHead(_ value: T) {
        lock.withLock {
            self.values.insert(value, at: 0)
        }
    }

    public var count: Int {
        lock.withLock { values.count }
    }

    @discardableResult
    public func removeAll() -> [T] {
        lock.withLock {
            let oldValues = values
            values = []
            return oldValues
        }
    }
}

extension AtomicArray where T: Equatable {
    public func remove(_ valueToRemove: T) {
        lock.withLock {
            self.values = self.values.filter { (value: T) -> Bool in
                valueToRemove != value
            }
        }
    }
}

// MARK: -

public final class AtomicDictionary<Key: Hashable, Value>: Sendable {
    private let lock: UnfairLock
    nonisolated(unsafe) private var values: [Key: Value]

    public init(_ values: [Key: Value] = [:], lock: UnfairLock) {
        self.values = values
        self.lock = lock
    }

    public subscript(_ key: Key) -> Value? {
        get { lock.withLock { self.values[key] } }
        set { lock.withLock { self.values[key] = newValue } }
    }

    public func pop(_ key: Key) -> Value? {
        lock.withLock {
            guard let value = self.values[key] else { return nil }
            self.values[key] = nil
            return value
        }
    }

    public func get() -> [Key: Value] {
        lock.withLock { self.values }
    }

    public func set(_ values: [Key: Value]) {
        lock.withLock { self.values = values }
    }

    public var isEmpty: Bool {
        lock.withLock { values.isEmpty }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        lock.withLock {
            values.removeValue(forKey: key)
        }
    }

    @discardableResult
    public func removeAllValues() -> [Value] {
        lock.withLock {
            let result = Array(values.values)
            values.removeAll()
            return result
        }
    }

    public var count: Int {
        lock.withLock { values.count }
    }

    public var allValues: [Value] {
        lock.withLock { Array(values.values) }
    }
}

// MARK: -

public final class AtomicSet<T: Hashable>: Sendable {
    private let lock: UnfairLock
    nonisolated(unsafe) private var values = Set<T>()

    public init(lock: UnfairLock) {
        self.lock = lock
    }

    public func insert(_ value: T) {
        lock.withLock { _ = self.values.insert(value) }
    }

    public func contains(_ value: T) -> Bool {
        lock.withLock { self.values.contains(value) }
    }

    @discardableResult
    public func remove(_ value: T) -> Bool {
        lock.withLock { () -> Bool in
            self.values.remove(value) != nil
        }
    }

    public var isEmpty: Bool {
        lock.withLock { values.isEmpty }
    }

    public var count: Int {
        lock.withLock { values.count }
    }

    public var allValues: Set<T> {
        lock.withLock { values }
    }

    @discardableResult
    public func removeAllValues() -> Set<T> {
        lock.withLock {
            let result = values
            values.removeAll()
            return result
        }
    }
}

@propertyWrapper
public struct Atomic<Value>: Sendable {
    private let value: AtomicValue<Value>

    public init(wrappedValue value: Value) {
        self.value = AtomicValue(value, lock: UnfairLock())
    }

    public var wrappedValue: Value {
        get {
            value.get()
        }
        nonmutating set {
            value.set(newValue)
        }
    }
}
