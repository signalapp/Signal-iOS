//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public struct HTMLMetadata: Equatable {
    /// Parsed from <title>
    var titleTag: String?
    /// Parsed from <link rel="icon"...>
    var faviconUrlString: String?
    /// Parsed from <meta name="description"...>
    var description: String?

    /// All properties below are parsed from opengraph tags matching the format <meta property="og:*"...>

    /// Parsed from the og:title property
    var ogTitle: String?
    /// Parsed from the og:description property
    var ogDescription: String?
    /// Parsed from the og:image or og:image:url property
    var ogImageUrlString: String?
    /// Parsed from the og:published_time or og:article:published_time
    var ogPublishDateString: String?
    /// Parsed from the og:modified_time or og:article:modified_time
    var ogModifiedDateString: String?

    static func construct(parsing rawHTML: String) -> HTMLMetadata {
        let opengraphTags = Self.parseOpengraphTags(in: rawHTML)
        return HTMLMetadata(
            titleTag: Self.parseTitleTag(in: rawHTML),
            faviconUrlString: Self.parseFaviconUrlString(in: rawHTML),
            description: Self.parseDescriptionTag(in: rawHTML),
            ogTitle: opengraphTags["title"],
            ogDescription: opengraphTags["description"],
            ogImageUrlString: (opengraphTags["image"] ?? opengraphTags["image:url"]),
            ogPublishDateString: (opengraphTags["published_time"] ?? opengraphTags["article:published_time"]),
            ogModifiedDateString: (opengraphTags["modified_time"] ?? opengraphTags["article:modified_time"])
        )
    }
}

// MARK: - Parsing

extension HTMLMetadata {

    private static func parseTitleTag(in rawHTML: String) -> String? {
        titleRegex
            .firstMatchSet(in: rawHTML)?
            .group(idx: 0)
            .flatMap { decodeHTMLEntities(in: String($0)) }
    }

    private static func parseFaviconUrlString(in rawHTML: String) -> String? {
        guard let matchedTag = faviconRegex
                .firstMatchSet(in: rawHTML)
                .map({ String($0.fullString) }) else { return nil }

        return faviconUrlRegex
            .parseFirstMatch(inText: matchedTag)
            .flatMap { decodeHTMLEntities(in: String($0)) }
    }

    private static func parseDescriptionTag(in rawHTML: String) -> String? {
        guard let matchedTag = metaDescriptionRegex
                .firstMatchSet(in: rawHTML)
                .map({ String($0.fullString) }) else { return nil }

        return contentRegex
            .parseFirstMatch(inText: matchedTag)
            .flatMap { decodeHTMLEntities(in: String($0)) }
    }

    private static func parseOpengraphTags(in rawHTML: String) -> [String: String] {
        opengraphTagRegex
            .allMatchSets(in: rawHTML)
            .reduce(into: [:]) { (builder, matchSet) in
                guard let ogTypeSubstring = matchSet.group(idx: 0) else { return }
                let ogType = String(ogTypeSubstring)
                let fullTag = String(matchSet.fullString)

                // Exit early if we've already found a tag of this type
                guard builder[ogType] == nil else { return }
                guard let content = contentRegex.parseFirstMatch(inText: fullTag) else { return }

                builder[ogType] = decodeHTMLEntities(in: content)
            }
    }

    private static func decodeHTMLEntities(in string: String) -> String? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        return attributedString.string
    }
}

 // MARK: - Regular Expressions

extension HTMLMetadata {
    static let titleRegex = regex(pattern: "<\\s*title[^>]*>(.*?)<\\s*/title[^>]*>")
    static let faviconRegex = regex(pattern: "<\\s*link[^>]*rel\\s*=\\s*\"\\s*(shortcut\\s+)?icon\\s*\"[^>]*>")
    static let faviconUrlRegex = regex(pattern: "href\\s*=\\s*\"([^\"]*)\"")
    static let metaDescriptionRegex = regex(pattern: "<\\s*meta[^>]*name\\s*=\\s*\"\\s*description[^\"]*\"[^>]*>")
    static let opengraphTagRegex = regex(pattern: "<\\s*meta[^>]*property\\s*=\\s*\"\\s*og:([^\"]+?)\"[^>]*>")
    static let contentRegex = regex(pattern: "content\\s*=\\s*\"([^\"]*?)\"")

    static private func regex(pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive])
    }
}
