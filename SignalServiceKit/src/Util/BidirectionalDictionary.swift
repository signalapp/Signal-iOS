//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public final class AnyBidirectionalDictionary: NSObject, NSCoding {
    fileprivate let forwardDictionary: [AnyHashable: AnyHashable]
    fileprivate let backwardDictionary: [AnyHashable: AnyHashable]

    public init<ElementOne: Hashable, ElementTwo: Hashable>(_ bidirectionalDictionary: BidirectionalDictionary<ElementOne, ElementTwo>) {
        forwardDictionary = .init(uniqueKeysWithValues: bidirectionalDictionary.forwardDictionary.map {
            (AnyHashable($0.key), AnyHashable($0.value))
        })
        backwardDictionary = .init(uniqueKeysWithValues: bidirectionalDictionary.backwardDictionary.map {
            (AnyHashable($0.key), AnyHashable($0.value))
        })
    }

    // MARK: - NSCoding

    @objc public func encode(with aCoder: NSCoder) {
        aCoder.encode(forwardDictionary, forKey: "forwardDictionary")
        aCoder.encode(backwardDictionary, forKey: "backwardDictionary")
    }

    @objc public init?(coder aDecoder: NSCoder) {
        forwardDictionary = aDecoder.decodeObject(forKey: "forwardDictionary") as? [AnyHashable: AnyHashable] ?? [:]
        backwardDictionary = aDecoder.decodeObject(forKey: "backwardDictionary") as? [AnyHashable: AnyHashable] ?? [:]

        guard forwardDictionary.count == backwardDictionary.count else {
            owsFailDebug("incorrect backing values")
            return nil
        }
    }
}

/// A dictionary that maintains a 1:1 key <-> value mapping and allows lookup by value or key.
public struct BidirectionalDictionary<ElementOne: Hashable, ElementTwo: Hashable> {
    fileprivate typealias ForwardType = [ElementOne: ElementTwo]
    fileprivate typealias BackwardType = [ElementTwo: ElementOne]

    fileprivate var forwardDictionary: ForwardType
    fileprivate var backwardDictionary: BackwardType

    public init() {
        forwardDictionary = [:]
        backwardDictionary = [:]
    }

    public init?(_ anyBidirectionalDictionary: AnyBidirectionalDictionary) {
        guard let forwardDictionary = anyBidirectionalDictionary.forwardDictionary as? ForwardType,
            let backwardDictionary = anyBidirectionalDictionary.backwardDictionary as? BackwardType else {
            return nil
        }

        self.forwardDictionary = forwardDictionary
        self.backwardDictionary = backwardDictionary
    }

    public init(uniqueKeysWithValues elements: [(ElementOne, ElementTwo)]) {
        self.init()
        elements.forEach { self[$0] = $1 }
    }

    public subscript(_ key: ElementOne) -> ElementTwo? {
        get {
            return forwardDictionary[key]
        }
        set {
            if let previousValue = forwardDictionary[key] {
                backwardDictionary[previousValue] = nil
            }

            guard let newValue = newValue else {
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
            if let previousValue = backwardDictionary[key] {
                forwardDictionary[previousValue] = nil
            }

            guard let newValue = newValue else {
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

    public var forwardKeys: [ElementOne] {
        return Array(forwardDictionary.keys)
    }

    public var backwardKeys: [ElementTwo] {
        return Array(backwardDictionary.keys)
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
        owsAssert((startIndex ..< endIndex).contains(position), "out of bounds")
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

    public init(dictionaryLiteral elements: (ElementOne, ElementTwo)...) {
        self.init(uniqueKeysWithValues: elements)
    }
}

// MARK: -

extension BidirectionalDictionary: Codable where ElementOne: Codable, ElementTwo: Codable {}
