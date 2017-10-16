//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

// ObjC compatible searcher
@objc class AnySearcher: NSObject {
    private let searcher: Searcher<AnyObject>

    public init(indexer: @escaping (AnyObject) -> String ) {
        searcher = Searcher(indexer: indexer)
        super.init()
    }

    @objc(item:doesMatchQuery:)
    public func matches(item: AnyObject, query: String) -> Bool {
        return searcher.matches(item: item, query: query)
    }
}

class Searcher<T> {

    private let indexer: (T) -> String

    public init(indexer: @escaping (T) -> String) {
        self.indexer = indexer
    }

    public func matches(item: T, query: String) -> Bool {
        let itemString = normalize(string: indexer(item))

        return stem(string: query).map { queryStem in
            return itemString.contains(queryStem)
        }.reduce(true) { $0 && $1 }
    }

    private func stem(string: String) -> [String] {
        return normalize(string: string).components(separatedBy: .whitespaces)
    }

    private func normalize(string: String) -> String {
        return string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
