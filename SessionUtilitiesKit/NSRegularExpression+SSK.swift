//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
extension NSRegularExpression {

    @objc
    public func hasMatch(input: String) -> Bool {
        return self.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) != nil
    }

    @objc
    public class func parseFirstMatch(pattern: String, text: String, options: NSRegularExpression.Options = []) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) else {
                return nil
            }
            let matchRange = match.range(at: 1)
            guard let textRange = Range(matchRange, in: text) else {
                return nil
            }
            let substring = String(text[textRange])
            return substring
        } catch {
            return nil
        }
    }

    @objc
    public func parseFirstMatch(inText text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let match = self.firstMatch(in: text,
                                          options: [],
                                          range: NSRange(location: 0, length: text.utf16.count)) else {
                                            return nil
        }
        let matchRange = match.range(at: 1)
        guard let textRange = Range(matchRange, in: text) else {
            return nil
        }
        let substring = String(text[textRange])
        return substring
    }
    
    @nonobjc
    public func firstMatchSet(in searchString: String) -> MatchSet? {
        firstMatch(in: searchString, options: [], range: searchString.completeNSRange)?.createMatchSet(originalSearchString: searchString)
    }

    @nonobjc
    public func allMatchSets(in searchString: String) -> [MatchSet] {
        matches(in: searchString, options: [], range: searchString.completeNSRange).compactMap { $0.createMatchSet(originalSearchString: searchString) }
    }
    
}

public struct MatchSet {
    public let fullString: Substring
    public let matchedGroups: [Substring?]

    public func group(idx: Int) -> Substring? {
        guard idx < matchedGroups.count else { return nil }
        return matchedGroups[idx]
    }
}

extension String {
    
    public subscript(_ nsRange: NSRange) -> Substring? {
        guard let swiftRange = Range(nsRange, in: self) else { return nil }
        return self[swiftRange]
    }

    public var completeRange: Range<String.Index> {
        startIndex..<endIndex
    }

    public var completeNSRange: NSRange {
        NSRange(completeRange, in: self)
    }
}

extension NSTextCheckingResult {
    
    public func createMatchSet(originalSearchString string: String) -> MatchSet? {
        guard numberOfRanges > 0 else { return nil }
        let substrings = (0..<numberOfRanges)
            .map { range(at: $0) }
            .map { string[$0] }

        guard let fullString = substrings[0] else {
            return nil
        }

        return MatchSet(fullString: fullString, matchedGroups: Array(substrings[1...]))
    }
}

