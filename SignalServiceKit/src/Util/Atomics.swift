//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

enum AtomicError: Error {
    case invalidTransition
}

// MARK: -

@objc
public class AtomicBool: NSObject {
    private var value: Bool

    @objc
    public required init(_ value: Bool) {
        self.value = value
    }

    // All instances can share a single queue.
    private static let serialQueue = DispatchQueue(label: "AtomicBool")

    @objc
    public func get() -> Bool {
        return AtomicBool.serialQueue.sync {
            return self.value
        }
    }

    @objc
    public func set(_ value: Bool) {
        return AtomicBool.serialQueue.sync {
            self.value = value
        }
    }

    // Sets value to "toValue" IFF it currently has "fromValue",
    // otherwise throws.
    @objc
    public func transition(from fromValue: Bool, to toValue: Bool) throws {
        return try AtomicBool.serialQueue.sync {
            guard self.value == fromValue else {
                throw AtomicError.invalidTransition
            }
            self.value = toValue
        }
    }
}

// MARK: -

private class AtomicArrayQueue {
    // All instances can share a single queue.
    fileprivate static let serialQueue = DispatchQueue(label: "AtomicArray")
}

public class AtomicArray<T: AnyObject> {
    private var values = [T]()

    public required init() {
    }

    public required init(_ values: [T]) {
        self.values = values
    }

    public func append(_ value: T) {
        AtomicArrayQueue.serialQueue.sync {
            return self.values.append(value)
        }
    }

    public func remove(_ valueToRemove: T) {
        AtomicArrayQueue.serialQueue.sync {
            self.values = self.values.filter { (value: T) -> Bool in
                valueToRemove !== value
            }
        }
    }

    public var first: T? {
        return AtomicArrayQueue.serialQueue.sync {
            return self.values.first
        }
    }
}
