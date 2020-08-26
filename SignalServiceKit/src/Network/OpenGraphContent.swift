//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct OpenGraphContent {
    let title: String?
    let imageURL: String?

    init(parsing rawHTML: String) {
        let parsedTags = Self.parseOGTags(rawHTML: rawHTML)
        self.title = parsedTags["title"]
        self.imageURL = parsedTags["image"]
    }
}

// MARK: - Parsing

private extension OpenGraphContent {
    // The content and og:* tags can appear in any order. It's simpler to separate this out into two regexes
    // The first looks for any meta tag with "property="og*".
    // The second takes the entire tag that was found, at looks for content="*" anywhere
    static let opengraphTagRegex = try! NSRegularExpression(pattern: "<\\s*meta[^>]*property\\s*=\\s*\"\\s*og:([^\"]+)\"[^>]*>",
                                                            options: [.dotMatchesLineSeparators, .caseInsensitive])
    static let contentRegex = try! NSRegularExpression(pattern: "content\\s*=\\s*\"([^\"]*)\"",
                                                       options: [.dotMatchesLineSeparators, .caseInsensitive])

    private static func parseOGTags(rawHTML: String) -> [String: String] {
        opengraphTagRegex
            .allMatchedStrings(in: rawHTML)
            .reduce(into: [:]) { (builder, matchSet) in
                guard matchSet.count >= 2 else { return }
                let fullTag = matchSet[0]
                let ogType = matchSet[1]
                guard let content = contentRegex.parseFirstMatch(inText: fullTag) else { return }
                builder[ogType] = decodeHTMLEntities(inString: content)
        }
    }

    private static func decodeHTMLEntities(inString value: String) -> String? {
        guard let data = value.data(using: .utf8) else {
            return nil
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html,
            NSAttributedString.DocumentReadingOptionKey.characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }

        return attributedString.string
    }
}

private extension NSRegularExpression {

    func allMatchedStrings(in searchString: String) -> [[String]] {
        let stringRange = NSRange(searchString.startIndex..<searchString.endIndex, in: searchString)
        let allMatches = matches(in: searchString, options: [], range: stringRange)

        // Each result has one or more ranges
        // Map from [NSTextCheckingResult] -> [[Range]] -> [[String]]
        return allMatches.map { (match) -> [String] in
            (0..<match.numberOfRanges)
                .compactMap { rangeIdx in Range(match.range(at: rangeIdx), in: searchString) }
                .compactMap { range in String(searchString[range]) }
        }
    }

}
