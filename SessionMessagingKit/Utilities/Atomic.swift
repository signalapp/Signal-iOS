// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

/// The `Atomic<T>` wrapper is a generic wrapper providing a thread-safe way to get and set a value
@propertyWrapper
struct Atomic<Value> {
    private let lock = DispatchSemaphore(value: 1)
    private var value: Value

    init(_ initialValue: Value) {
        self.value = initialValue
    }

    var wrappedValue: Value {
        get {
            lock.wait()
            defer { lock.signal() }
            return value
        }
        set {
            lock.wait()
            value = newValue
            lock.signal()
        }
    }
}
