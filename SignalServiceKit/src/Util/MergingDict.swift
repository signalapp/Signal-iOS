//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol Mergeable {
    func merge(_ other: Self) -> Self
}

/// Just a wrapper around a dictionary that handles merging elements
/// when an overwrite happens.
public struct MergingDict<K, V> where K: Hashable, V: Mergeable {

    private var dict = [K: V]()

    public init() {}

    public var keys: Set<K> {
        return Set(dict.keys)
    }

    public func keys(where fn: (V) -> Bool) -> Set<K> {
        var set = Set<K>()
        dict.forEach { k, v in
            if fn(v) {
                set.insert(k)
            }
        }
        return set
    }

    public subscript(_ key: K) -> V? {
        get {
            return dict[key]
        }
        set {
            if let newValue {
                insert(key, newValue)
            } else {
                dict[key] = nil
            }
        }
    }

    public var isEmpty: Bool { dict.isEmpty }
    public var count: Int { dict.count }

    public mutating func insert(_ key: K, _ value: V) {
        guard let ourValue = dict[key] else {
            dict[key] = value
            return
        }
        dict[key] = ourValue.merge(value)
    }

    public mutating func formUnion(_ other: Self) {
        for (k, v) in other.dict {
            insert(k, v)
        }
    }
}
