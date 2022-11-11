//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/**
 * Container for a weakly referenced object.
 *
 * Only use this for |T| with reference-semantic entities
 * That is - <T> should inherit from AnyObject or Class-only protocols, but not structs or enums.
 *
 * Based on https://devforums.apple.com/message/981472#981472, but also supports class-only protocols
 */
public struct Weak<T> {
    private weak var _value: AnyObject?

    public var value: T? {
        get {
            return _value as? T
        }
        set {
            _value = newValue as AnyObject
        }
    }

    public init(value: T) {
        self.value = value
    }
}

public struct WeakArray<Element> {
    private var array: [Weak<Element>] = []

    public var elements: [Element] {
        array.compactMap { $0.value }
    }

    public var weakReferenceCount: Int {
        array.count
    }

    public mutating func append(_ element: Element) {
        array = array.filter { $0.value != nil } + [Weak(value: element)]
    }

    public mutating func removeAll(where shouldDelete: (Element) throws -> Bool) rethrows {
        try array.removeAll { weakBox in
            guard let element = weakBox.value else { return true }
            return try shouldDelete(element)
        }
    }

    public mutating func cullExpired() {
        array.removeAll { weakBox in
            weakBox.value == nil
        }
    }
}

extension WeakArray: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Element
    public init(arrayLiteral elements: Element...) {
        self.init()
        for element in elements {
            self.append(element)
        }
    }
}
