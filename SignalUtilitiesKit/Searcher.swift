//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

// A generic searching class, configurable with an indexing block
public class Searcher<T> {

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
        var normalized = normalize(string: string)

        // Remove any phone number formatting from the search terms
        let nonformattingScalars = normalized.unicodeScalars.lazy.filter {
            !CharacterSet.punctuationCharacters.contains($0)
        }

        normalized = String(String.UnicodeScalarView(nonformattingScalars))

        return normalized.components(separatedBy: .whitespacesAndNewlines)
    }

    private func normalize(string: String) -> String {
        return string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
