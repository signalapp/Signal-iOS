//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum AtomicError: Int, Error {
    case invalidTransition
}

// MARK: -

private class Atomics {
    // All instances can share a single queue.
    fileprivate static let serialQueue = DispatchQueue(label: "Atomics")
}

// MARK: -

// Provides Objective-C compatibility for the most common atomic value type.
@objc
public class AtomicBool: NSObject {
    private let value = AtomicValue<Bool>(false)

    @objc
    public required init(_ value: Bool) {
        self.value.set(value)
    }

    @objc
    public func get() -> Bool {
        return value.get()
    }

    @objc
    public func set(_ value: Bool) {
        self.value.set(value)
    }

    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    private func transition(from fromValue: Bool, to toValue: Bool) throws {
        return try value.transition(from: fromValue, to: toValue)
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
        return value.get()
    }

    @objc
    public func set(_ value: UInt) {
        self.value.set(value)
    }

    @discardableResult
    @objc
    public func increment() -> UInt {
        return value.map { $0 + 1 }
    }
}

// MARK: -

public class AtomicValue<T> {
    private var value: T

    public required init(_ value: T) {
        self.value = value
    }

    fileprivate var serialQueue: DispatchQueue {
        return Atomics.serialQueue
    }

    public func get() -> T {
        return serialQueue.sync {
            return self.value
        }
    }

    public func set(_ value: T) {
        serialQueue.sync {
            self.value = value
        }
    }

    // Transform the current value using a block.
    @discardableResult
    public func map(_ block: @escaping (T) -> T) -> T {
        return serialQueue.sync {
            let newValue = block(self.value)
            self.value = newValue
            return newValue
        }
    }
}

// MARK: -

extension AtomicValue where T: Equatable {
    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    public func transition(from fromValue: T, to toValue: T) throws {
        return try serialQueue.sync {
            guard self.value == fromValue else {
                throw AtomicError.invalidTransition
            }
            self.value = toValue
        }
    }
}

// MARK: -

public class AtomicArray<T: AnyObject> {
    private let serialQueue = DispatchQueue(label: "AtomicArray")

    private var values = [T]()

    public required init() {
    }

    public required init(_ values: [T]) {
        self.values = values
    }

    public func append(_ value: T) {
        serialQueue.sync {
            return self.values.append(value)
        }
    }

    public func remove(_ valueToRemove: T) {
        serialQueue.sync {
            self.values = self.values.filter { (value: T) -> Bool in
                valueToRemove !== value
            }
        }
    }

    public var first: T? {
        return serialQueue.sync {
            return self.values.first
        }
    }
}
