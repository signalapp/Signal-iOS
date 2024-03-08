//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

/// Represents a type that contains one or more identifiers, which may refer to
/// itself or any other type.
protocol ContainsIdentifiers<ContainedIdType> {
    associatedtype ContainedIdType: Hashable
    var containedIds: [ContainedIdType] { get }
}

/// An ordered list of elements that each contain one or more identifiers, which
/// can be indexed by the elements' contained identifiers.
struct IdentifierIndexedArray<Element: ContainsIdentifiers> {
    /// All the elements managed by this indexed array.
    private var elements: [Element]

    /// Maps the contained IDs of each element to the index of that element
    /// in ``elements``.
    private var elementIndicesByIds: [Element.ContainedIdType: Int]

    init(elements: [Element]) {
        self.elements = elements
        self.elementIndicesByIds = elements.indicesByEachContainedId()
    }

    // MARK: -

    var allElements: [Element] { elements }

    var count: Int { elements.count }
    var isEmpty: Bool { elements.isEmpty }

    var first: Element? { elements.first }
    var last: Element? { elements.last }

    subscript(index index: Int) -> Element {
        return elements[index]
    }

    subscript(safe index: Int) -> Element? {
        return elements[safe: index]
    }

    subscript(id id: Element.ContainedIdType) -> Element? {
        guard let index = index(forId: id) else {
            return nil
        }

        return self[index: index]
    }

    func index(forId id: Element.ContainedIdType) -> Int? {
        return elementIndicesByIds[id]
    }

    /// Appends the given elements to this array.
    /// - Note
    /// Runs in `O(newElements.count)`.
    mutating func append(newElements: [Element]) {
        for element in newElements {
            for id in element.containedIds {
                elementIndicesByIds[id] = elements.count
            }

            elements.append(element)
        }
    }

    /// Prepends the given elements to this array.
    /// - Note
    /// Runs in `O(self.count)`.
    mutating func prepend(newElements: [Element]) {
        elements = newElements + elements
        elementIndicesByIds = elements.indicesByEachContainedId()
    }

    /// Replace the element at the given index with the given new element.
    mutating func replace(
        elementAtIndex indexToReplace: Int,
        with newElement: Element
    ) {
        let existingElement = elements[indexToReplace]
        elements[indexToReplace] = newElement

        for id in existingElement.containedIds {
            elementIndicesByIds.removeValue(forKey: id)
        }

        for id in newElement.containedIds {
            elementIndicesByIds[id] = indexToReplace
        }
    }
}

// MARK: -

private extension Array where Element: ContainsIdentifiers {
    /// Computes a mapping of each ID contained within each element of this
    /// array to that element's index in this array.
    ///
    /// - Important
    /// When an element of this array contains multiple IDs, each of those IDs
    /// in the returned mapping will refer to the same index.
    func indicesByEachContainedId() -> [Element.ContainedIdType: Int] {
        return Dictionary(
            self.enumerated().flatMap { (idx, element) -> [(Element.ContainedIdType, Int)] in
                return element.containedIds.map { ($0, idx) }
            },
            uniquingKeysWith: { _, new in
                owsFailDebug("Unexpectedly encountered duplicate IDs across ContainsIdentifiers elements!")
                return new
            }
        )
    }
}
