//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

fileprivate class Box<A> {
    var value: A
    init(_ val: A) {
        self.value = val
    }
}

public extension Sequence {
    // `group` function lifted from https://stackoverflow.com/a/31220067
    public func group<U: Hashable>(by key: (Iterator.Element) -> U) -> [U:[Iterator.Element]] {
        var categories: [U: Box<[Iterator.Element]>] = [:]
        for element in self {
            let key = key(element)
            // We use a Box type to avoid copying the entire array every time we mutate it.
            if case nil = categories[key]?.value.append(element) {
                categories[key] = Box([element])
            }
        }
        var result: [U: [Iterator.Element]] = Dictionary(minimumCapacity: categories.count)
        for (key, val) in categories {
            result[key] = val.value
        }
        return result
    }
}
