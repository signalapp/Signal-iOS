//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension CollectionDifference where ChangeElement: Identifiable {
    /// Represents a batch of changes derived from a `CollectionDifferance`,
    /// suitable for applying to a `UITableView` or `UICollectionView`.
    public struct ChangeBatch: Collection, ExpressibleByDictionaryLiteral {
        public typealias Key = ChangeElement.ID
        public typealias Value = (offset: Int, element: ChangeElement, previousOffset: Int?)

        private var storage: [Key: Value]

        public init() {
            self.storage = [:]
        }

        public var offsets: IndexSet {
            IndexSet(storage.values.lazy.map(\.offset))
        }

        public func indexPaths(in section: Int) -> [IndexPath] {
            offsets.map { IndexPath(row: $0, section: section) }
        }

        public subscript(key: Key) -> Value? {
            get { storage[key] }
            set { storage[key] = newValue }
        }

        // MARK: ExpressibleByDictionaryLiteral

        public init(dictionaryLiteral elements: (Key, Value)...) {
            self.storage = Dictionary(uniqueKeysWithValues: elements)
        }

        // MARK: Collection

        public typealias Index = Dictionary<Key, Value>.Index
        public typealias Element = Dictionary<Key, Value>.Element

        public var isEmpty: Bool {
            storage.isEmpty
        }

        public var startIndex: Index {
            storage.startIndex
        }

        public var endIndex: Index {
            storage.endIndex
        }

        public func index(after i: Index) -> Index {
            storage.index(after: i)
        }

        public subscript(position: Index) -> Element {
            storage[position]
        }
    }

    /// A combined set of batched changes derived from a `CollectionDifference`,
    /// suitable for applying to a `UITableView` or `UICollectionView`.
    public struct BatchedChanges {
        /// An ordered set of all removals in the `CollectionDifference`.
        public fileprivate(set) var removals = ChangeBatch()

        /// An ordered set of all insertions in the `CollectionDifference`.
        public fileprivate(set) var insertions = ChangeBatch()

        /// An ordered set of all updates in the `CollectionDifference`, i.e.,
        /// a combination of removal & insertion where the change element's `id`
        /// is the same, but the element's value has changed.
        public fileprivate(set) var updates = ChangeBatch()
    }

    /// Iterate over each change in the `CollectionDifference`, combining
    /// changes of the same type (removal, insertion or update) into a
    /// corresponding `ChangeBatch`.
    ///
    /// An **update** change is defined as a **remove** followed by an **insert**
    /// where the change elements’ `id` properties are equal. The original pair
    /// of remove & insert operations are replaced by a single update in the
    /// resulting `BatchedChanges`.
    public func batchedChanges() -> BatchedChanges {
        var changes = BatchedChanges()

        for change in self {
            switch change {
            case let .remove(offset, element, associatedWith: _):
                changes.removals[element.id] = (offset, element, nil)

            case let .insert(offset, element, associatedWith: _):
                if let removal = changes.removals[element.id] {
                    changes.removals[element.id] = nil
                    changes.updates[element.id] = (offset, element, previousOffset: removal.offset)
                } else {
                    changes.insertions[element.id] = (offset, element, nil)
                }
            }
        }

        return changes
    }
}
