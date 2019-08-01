//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

/// A dictionary that maintains a 1:1 key <-> value mapping and allows lookup by value or key.
public final class BidirectionalDictionary<ElementOne: Hashable, ElementTwo: Hashable>: NSObject, NSCoding {
    private var forwardDictionary = [ElementOne: ElementTwo]()
    private var backwardDictionary = [ElementTwo: ElementOne]()

    public required override init() {
        forwardDictionary = [:]
        backwardDictionary = [:]
    }

    public convenience init(uniqueKeysWithValues elements: [(ElementOne, ElementTwo)]) {
        self.init()
        elements.forEach { self[$0] = $1 }
    }

    public subscript(_ key: ElementOne) -> ElementTwo? {
        get {
            return forwardDictionary[key]
        }
        set {
            guard let newValue = newValue else {
                if let previousValue = forwardDictionary[key] {
                    backwardDictionary[previousValue] = nil
                }
                forwardDictionary[key] = nil
                return
            }

            forwardDictionary[key] = newValue
            backwardDictionary[newValue] = key
        }
    }

    public subscript(_ key: ElementTwo) -> ElementOne? {
        get {
            return backwardDictionary[key]
        }
        set {
            guard let newValue = newValue else {
                if let previousValue = backwardDictionary[key] {
                    forwardDictionary[previousValue] = nil
                }
                backwardDictionary[key] = nil
                return
            }

            backwardDictionary[key] = newValue
            forwardDictionary[newValue] = key
        }
    }

    public var count: Int {
        assert(forwardDictionary.count == backwardDictionary.count)
        return forwardDictionary.count
    }

    // MARK: - NSCoding

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(forwardDictionary, forKey: "forwardDictionary")
        aCoder.encode(backwardDictionary, forKey: "backwardDictionary")
    }

    public init?(coder aDecoder: NSCoder) {
        forwardDictionary = aDecoder.decodeObject(forKey: "forwardDictionary") as? [ElementOne: ElementTwo] ?? [:]
        backwardDictionary = aDecoder.decodeObject(forKey: "backwardDictionary") as? [ElementTwo: ElementOne] ?? [:]

        guard forwardDictionary.count == backwardDictionary.count else {
            owsFailDebug("incorrect backing values")
            return nil
        }
    }
}

// MARK: - Collection

extension BidirectionalDictionary: Collection {
    public typealias Index = DictionaryIndex<ElementOne, ElementTwo>

    public var startIndex: Index {
        return forwardDictionary.startIndex
    }

    public var endIndex: Index {
        return forwardDictionary.endIndex
    }

    public subscript (position: Index) -> Iterator.Element {
        precondition((startIndex ..< endIndex).contains(position), "out of bounds")
        let element = forwardDictionary[position]
        return (element.key, element.value)
    }

    public func index(after i: Index) -> Index {
        return forwardDictionary.index(after: i)
    }
}

// MARK: - Sequence

extension BidirectionalDictionary: Sequence {
    public typealias Iterator = AnyIterator<(ElementOne, ElementTwo)>

    public func makeIterator() -> Iterator {
        var iterator = forwardDictionary.makeIterator()
        return AnyIterator { iterator.next() }
    }
}

// MARK: - Transforms

extension BidirectionalDictionary {
    public func mapValues<T>(_ transform: (ElementTwo) throws -> T) rethrows -> BidirectionalDictionary<ElementOne, T> {
        return try forwardDictionary.reduce(into: BidirectionalDictionary<ElementOne, T>()) { dict, pair in
            dict[pair.key] = try transform(pair.value)
        }
    }

    public func map<T>(_ transform: (ElementOne, ElementTwo) throws -> T) rethrows -> [T] {
        return try forwardDictionary.map(transform)
    }

    public func filter(_ isIncluded: (ElementOne, ElementTwo) throws -> Bool) rethrows -> BidirectionalDictionary<ElementOne, ElementTwo> {
        return try forwardDictionary.reduce(
            into: BidirectionalDictionary<ElementOne, ElementTwo>()
        ) { dict, pair in
            guard try isIncluded(pair.key, pair.value) else { return }
            dict[pair.key] = pair.value
        }
    }
}

// MARK: -

extension BidirectionalDictionary: ExpressibleByDictionaryLiteral {
    public typealias Key = ElementOne
    public typealias Value = ElementTwo

    public convenience init(dictionaryLiteral elements: (ElementOne, ElementTwo)...) {
        self.init(uniqueKeysWithValues: elements)
    }
}
