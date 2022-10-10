// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

// MARK: - Atomic<Value>

/// The `Atomic<Value>` wrapper is a generic wrapper providing a thread-safe way to get and set a value
///
/// A write-up on the need for this class and it's approach can be found here:
/// https://www.vadimbulavin.com/swift-atomic-properties-with-property-wrappers/
/// there is also another approach which can be taken but it requires separate types for collections and results in
/// a somewhat inconsistent interface between different `Atomic` wrappers
@propertyWrapper
public class Atomic<Value> {
    // Note: Using 'userInteractive' to ensure this can't be blockedby higher priority queues
    // which could result in the main thread getting blocked
    private let queue: DispatchQueue = DispatchQueue(
        label: "io.oxen.\(UUID().uuidString)",
        qos: .userInteractive
    )
    private var value: Value

    /// In order to change the value you **must** use the `mutate` function
    public var wrappedValue: Value {
        return queue.sync { return value }
    }

    /// For more information see https://github.com/apple/swift-evolution/blob/master/proposals/0258-property-wrappers.md#projections
    public var projectedValue: Atomic<Value> {
        return self
    }
    
    // MARK: - Initialization

    public init(_ initialValue: Value) {
        self.value = initialValue
    }
    
    // MARK: - Functions

    @discardableResult public func mutate<T>(_ mutation: (inout Value) -> T) -> T {
        return queue.sync {
            return mutation(&value)
        }
    }
}

extension Atomic where Value: CustomDebugStringConvertible {
    var debugDescription: String {
        return value.debugDescription
    }
}
