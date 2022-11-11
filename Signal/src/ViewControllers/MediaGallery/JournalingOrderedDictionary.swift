//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public enum JournalingOrderedDictionaryChange<ChangeType: Equatable>: Equatable, CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .prepend:
            return "prepend"
        case .append:
            return "append"
        case .modify(index: let index, changes: let changes):
            return "modify index=\(index) changes=\(changes.map { String(reflecting: $0) })"
        case .remove(index: let i):
            return "remove index=\(i)"
        case .removeAll:
            return "removeAll"
        }
    }
    /// Add one key to the beginning
    case prepend

    /// Add one key to the end.
    case append

    /// Modify the value of a key
    case modify(index: Int, changes: [ChangeType])

    /// Remove by index
    case remove(index: Int)

    /// Delete all keys
    case removeAll
}

/// Like OrderedDictionary but it creates a journal of mutations.
/// This is designed for the benefit of MediaGallerySections and is not quite as capable as OrderedDictionary.
/// `ChangeType` describes a modification to an instance of `ValueType`, which is opaque to this object.
public struct JournalingOrderedDictionary<KeyType: Hashable, ValueType, ChangeType: Equatable> {
    private(set) public var orderedDictionary = OrderedDictionary<KeyType, ValueType>()
    private(set) public var journal = [Change]()
    public typealias Change = JournalingOrderedDictionaryChange<ChangeType>
    public var orderedKeys: [KeyType] { orderedDictionary.orderedKeys }
    public var isEmpty: Bool { orderedDictionary.isEmpty }

    public mutating func prepend(key: KeyType, value: ValueType) {
        journal.append(.prepend)
        orderedDictionary.prepend(key: key, value: value)
    }

    public mutating func append(key: KeyType, value: ValueType) {
        let i = orderedDictionary.count
        journal.append(.append)
        orderedDictionary.append(key: key, value: value)
    }

    @discardableResult
    public mutating func replaceValue(at i: Int, value: ValueType, changes: [ChangeType]) -> ValueType {
        if !changes.isEmpty {
            journal.append(.modify(index: i, changes: changes))
        }
        let key = orderedDictionary[i].key
        return orderedDictionary.replace(key: key, value: value)
    }

    public subscript(key: KeyType) -> ValueType? {
        return orderedDictionary[key]
    }

    public mutating func remove(at index: Int) {
        journal.append(.remove(index: index))
        orderedDictionary.remove(at: index)
    }

    public mutating func eraseJournal() {
        journal = []
    }

    public mutating func removeAll() {
        journal = [.removeAll]
        orderedDictionary.removeAll()
    }
}

extension JournalingOrderedDictionary: RandomAccessCollection {
    public var startIndex: Int { orderedDictionary.startIndex }
    public var endIndex: Int { orderedDictionary.endIndex }

    public func entry(atPosition position: Int) -> (key: KeyType, value: ValueType) {
        return orderedDictionary[position]
    }

    public subscript(position: Int) -> (key: KeyType, value: ValueType) {
        return orderedDictionary[position]
    }
}
