//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension NSRegularExpression {

    func hasMatch(input: String) -> Bool {
        return self.firstMatch(in: input, options: [], range: input.entireRange) != nil
    }

    class func parseFirstMatch(
        pattern: String,
        text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            guard let match = regex.firstMatch(in: text,
                                               options: [],
                                               range: text.entireRange) else {
                                                return nil
            }
            let matchRange = match.range(at: 1)
            guard let textRange = Range(matchRange, in: text) else {
                owsFailDebug("Invalid match.")
                return nil
            }
            let substring = String(text[textRange])
            return substring
        } catch {
            Logger.error("Error: \(error)")
            return nil
        }
    }

    func parseFirstMatch(inText text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let match = self.firstMatch(in: text,
                                          options: [],
                                          range: text.entireRange) else {
                                            return nil
        }
        let matchRange = match.range(at: 1)
        guard let textRange = Range(matchRange, in: text) else {
            owsFailDebug("Invalid match.")
            return nil
        }
        let substring = String(text[textRange])
        return substring
    }

    @nonobjc
    func firstMatchSet(in searchString: String) -> MatchSet? {
        firstMatch(in: searchString, options: [], range: searchString.completeNSRange)?
            .createMatchSet(originalSearchString: searchString)
    }

    @nonobjc
    func allMatchSets(in searchString: String) -> [MatchSet] {
        matches(in: searchString, options: [], range: searchString.completeNSRange)
            .compactMap { $0.createMatchSet(originalSearchString: searchString) }
    }
}

public struct MatchSet {
    let fullString: Substring
    let matchedGroups: [Substring?]

    func group(idx: Int) -> Substring? {
        guard idx < matchedGroups.count else { return nil }
        return matchedGroups[idx]
    }
}

fileprivate extension String {
    subscript(_ nsRange: NSRange) -> Substring? {
        guard let swiftRange = Range(nsRange, in: self) else { return nil }
        return self[swiftRange]
    }

    var completeRange: Range<String.Index> {
        startIndex..<endIndex
    }

    var completeNSRange: NSRange {
        NSRange(completeRange, in: self)
    }
}

fileprivate extension NSTextCheckingResult {
    func createMatchSet(originalSearchString string: String) -> MatchSet? {
        guard numberOfRanges > 0 else { return nil }
        let substrings = (0..<numberOfRanges)
            .map { range(at: $0) }
            .map { string[$0] }

        guard let fullString = substrings[0] else {
            owsFailDebug("Missing expected full string")
            return nil
        }

        return MatchSet(fullString: fullString, matchedGroups: Array(substrings[1...]))
    }
}
