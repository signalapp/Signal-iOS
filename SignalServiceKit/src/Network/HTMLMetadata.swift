//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct HTMLMetadata: Equatable {
    /// Parsed from <title>
    var titleTag: String?
    /// Parsed from <link rel="icon"...>
    var faviconUrlString: String?
    /// Parsed from <meta name="description"...>
    var description: String?
    /// Parsed from the og:title meta property
    var ogTitle: String?
    /// Parsed from the og:description meta property
    var ogDescription: String?
    /// Parsed from the og:image or og:image:url meta property
    var ogImageUrlString: String?
    /// Parsed from the og:published_time meta property
    var ogPublishDateString: String?
    /// Parsed from article:published_time meta property
    var articlePublishDateString: String?
    /// Parsed from the og:modified_time meta property
    var ogModifiedDateString: String?
    /// Parsed from the article:modified_time meta property
    var articleModifiedDateString: String?

    static func construct(parsing rawHTML: String) -> HTMLMetadata {
        let metaPropertyTags = Self.parseMetaProperties(in: rawHTML)
        return HTMLMetadata(
            titleTag: Self.parseTitleTag(in: rawHTML),
            faviconUrlString: Self.parseFaviconUrlString(in: rawHTML),
            description: Self.parseDescriptionTag(in: rawHTML),
            ogTitle: metaPropertyTags["og:title"],
            ogDescription: metaPropertyTags["og:description"],
            ogImageUrlString: (metaPropertyTags["og:image"] ?? metaPropertyTags["og:image:url"]),
            ogPublishDateString: metaPropertyTags["og:published_time"],
            articlePublishDateString: metaPropertyTags["article:published_time"],
            ogModifiedDateString: metaPropertyTags["og:modified_time"],
            articleModifiedDateString: metaPropertyTags["article:modified_time"]
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

        return metaContentRegex
            .parseFirstMatch(inText: matchedTag)
            .flatMap { decodeHTMLEntities(in: String($0)) }
    }

    private static func parseMetaProperties(in rawHTML: String) -> [String: String] {
        metaPropertyRegex
            .allMatchSets(in: rawHTML)
            .reduce(into: [:]) { (builder, matchSet) in
                guard let ogTypeSubstring = matchSet.group(idx: 0) else { return }
                let ogType = String(ogTypeSubstring)
                let fullTag = String(matchSet.fullString)

                // Exit early if we've already found a tag of this type
                guard builder[ogType] == nil else { return }
                guard let content = metaContentRegex.parseFirstMatch(inText: fullTag) else { return }

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
    static let metaPropertyRegex = regex(pattern: "<\\s*meta[^>]*property\\s*=\\s*\"\\s*([^\"]+?)\"[^>]*>")
    static let metaContentRegex = regex(pattern: "content\\s*=\\s*\"([^\"]*?)\"")

    static private func regex(pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive])
    }
}
