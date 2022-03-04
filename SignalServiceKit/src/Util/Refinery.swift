//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

// A Refinery helps you iteratively assign values to keys. Each iteration provides the keys without values yet and
// through successive calls to refine(_:) values are provided by the caller. It's more useful than map when you can
// look up a collection of keys at once, such as in a SQL query because you don't need to worry about values that were
// resolved in a previous step.
//
// Example:
//
// Refinery(phoneNumbers).refine { phoneNumbers in
//   return NamesForPhoneNumbersFromAddressBook(phoneNumbers)  // returns nil if not in address book
// }.refine { phoneNumbers in
//   return NamesForPhoneNumbersFromDatabase(phoneNumbers)  // returns nil if not in database
// }.refine { phoneNumbers in
//   return phoneNumbers.map { formatPhoneNumber($0) }
// }.values
//
// The `values` array is parallel to the `keys` the Refinery was initialized with.
public class Refinery<Key, Value> {
    // Keys whose values the client wants to compute.
    public let keys: [Key]

    // Parallel to `keys`. Each call to `refine` may change some of these from nil to nonnil.
    private(set) public var values: [Value?]

    // Indexes in `values` that are nil.
    private var indexes: IndexSet

    public init(_ keys: [Key]) {
        self.keys = keys
        values = Array(repeating: nil, count: keys.count)
        indexes = IndexSet(0..<keys.count)
    }

    public func refine<Result>(_ closure: (AnySequence<Key>) -> Result) -> Self where Result: Sequence, Result.Element == Value? {
        internalRefine(indexes, closure: closure)
        return self
    }

    // This helps you partition the keys so that they can be refined differently based on some precondition.
    // Keys meeting the condition are sent to the `then` closure; all others go to `otherwise`.
    public func refine<Result>(condition: (Key) -> Bool,
                               then: (AnySequence<Key>) -> Result,
                               otherwise: (AnySequence<Key>) -> Result) -> Self where Result: Sequence, Result.Element == Value? {
        let (matching, nonMatching) = partitionIndexes {
            condition(keys[$0])
        }

        internalRefine(matching, closure: then)
        internalRefine(nonMatching, closure: otherwise)

        return self
    }

    // `indexes` gives the indexes of `self.keys` to try to get values for from `closure`.
    // As a side-effect, it assigns to self.values and removes from self.indexes when a value is assigned.
    private func internalRefine<Result>(_ indexes: IndexSet,
                                        closure: (AnySequence<Key>) -> Result) where Result: Sequence, Result.Element == Value? {
        let refinedValues = closure(keys(at: indexes))
        for (i, maybeValue) in zip(indexes, refinedValues) {
            guard let value = maybeValue else {
                continue
            }
            self.indexes.remove(i)
            values[i] = value
        }
    }

    private func partitionIndexes(_ closure: (Int) -> Bool) -> (IndexSet, IndexSet) {
        var lhs = IndexSet()
        var rhs = IndexSet()
        for index in indexes {
            if closure(index) {
                lhs.insert(index)
            } else {
                rhs.insert(index)
            }
        }
        return (lhs, rhs)
    }

    private func keys(at indexes: IndexSet) -> AnySequence<Key> {
        let keys = self.keys
        return AnySequence(indexes.lazy.map { keys[$0] })
    }
}
