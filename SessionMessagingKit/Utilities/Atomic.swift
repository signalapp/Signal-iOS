// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

/// See https://www.donnywals.com/why-your-atomic-property-wrapper-doesnt-work-for-collection-types/
/// for more information about the below types

protocol UnsupportedType {}

extension Array: UnsupportedType {}
extension Set: UnsupportedType {}
extension Dictionary: UnsupportedType {}

// MARK: - Atomic<Value>

/// The `Atomic<Value>` wrapper is a generic wrapper providing a thread-safe way to get and set a value
@propertyWrapper
struct Atomic<Value> {
    private let queue: DispatchQueue = DispatchQueue(label: "io.oxen.\(UUID().uuidString)", qos: .utility, attributes: .concurrent, autoreleaseFrequency: .inherit, target: .global())
    private var value: Value

    init(_ initialValue: Value) {
        if initialValue is UnsupportedType { preconditionFailure("Use the appropriate Aromic... type for collections") }
        
        self.value = initialValue
    }

    var wrappedValue: Value {
        get { return queue.sync { return value } }
        set { return queue.sync { value = newValue } }
    }
}

extension Atomic where Value: CustomDebugStringConvertible {
    var debugDescription: String {
        return value.debugDescription
    }
}

// MARK: - AtomicArray<Value>

/// The `AtomicArray<Value>` wrapper is a generic wrapper providing a thread-safe way to get and set an array or one of it's values
///
/// Note: This is a class rather than a struct as you need to modify a reference rather than a copy for the concurrency to work
@propertyWrapper
class AtomicArray<Value>: CustomDebugStringConvertible {
    private let queue: DispatchQueue = DispatchQueue(label: "io.oxen.\(UUID().uuidString)", qos: .utility, attributes: .concurrent, autoreleaseFrequency: .inherit, target: .global())
    private var value: [Value]

    init(_ initialValue: [Value] = []) {
        self.value = initialValue
    }

    var wrappedValue: [Value] {
        get { return queue.sync { return value } }
        set { return queue.sync { value = newValue } }
    }
    
    subscript(index: Int) -> Value {
        get { queue.sync { value[index] }}
        set { queue.async(flags: .barrier) { self.value[index] = newValue } }
    }
    
    public var debugDescription: String {
        return value.debugDescription
    }
}

// MARK: - AtomicDict<Key, Value>

/// The `AtomicDict<Key, Value>` wrapper is a generic wrapper providing a thread-safe way to get and set a dictionaries or one of it's values
///
/// Note: This is a class rather than a struct as you need to modify a reference rather than a copy for the concurrency to work
@propertyWrapper
class AtomicDict<Key: Hashable, Value>: CustomDebugStringConvertible {
    private let queue: DispatchQueue = DispatchQueue(label: "io.oxen.\(UUID().uuidString)", qos: .utility, attributes: .concurrent, autoreleaseFrequency: .inherit, target: .global())
    private var value: [Key: Value]

    init(_ initialValue: [Key: Value] = [:]) {
        self.value = initialValue
    }
    
    var wrappedValue: [Key: Value] {
        get { return queue.sync { return value } }
        set { return queue.sync { value = newValue } }
    }
    
    subscript(key: Key) -> Value? {
        get { queue.sync { value[key] }}
        set { queue.async(flags: .barrier) { self.value[key] = newValue } }
    }
    
    var debugDescription: String {
        return value.debugDescription
    }
}
