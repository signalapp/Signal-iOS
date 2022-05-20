// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUIKit
import SessionMessagingKit

public enum MentionUtilities {
    public static func highlightMentions(in string: String, threadVariant: SessionThread.Variant) -> String {
        return highlightMentions(
            in: string,
            threadVariant: threadVariant,
            isOutgoingMessage: false,
            attributes: [:]
        ).string // isOutgoingMessage and attributes are irrelevant
    }

    public static func highlightMentions(
        in string: String,
        threadVariant: SessionThread.Variant,
        isOutgoingMessage: Bool,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        guard
            let regex: NSRegularExpression = try? NSRegularExpression(pattern: "@[0-9a-fA-F]{66}", options: [])
        else {
            return NSAttributedString(string: string)
        }
        
        var string = string
        var lastMatchEnd: Int = 0
        var mentions: [(range: NSRange, publicKey: String)] = []
        
        while let match: NSTextCheckingResult = regex.firstMatch(
            in: string,
            options: .withoutAnchoringBounds,
            range: NSRange(location: lastMatchEnd, length: string.utf16.count - lastMatchEnd)
        ) {
            guard let range: Range = Range(match.range, in: string) else { break }
            
            let publicKey: String = String(string[range].dropFirst()) // Drop the @
            
            guard let displayName: String = Profile.displayNameNoFallback(id: publicKey, threadVariant: threadVariant) else {
                lastMatchEnd = (match.range.location + match.range.length)
                continue
            }
            
            string = string.replacingCharacters(in: range, with: "@\(displayName)")
            lastMatchEnd = (match.range.location + displayName.utf16.count)
            
            mentions.append((
                // + 1 to include the @
                range: NSRange(location: match.range.location, length: displayName.utf16.count + 1),
                publicKey: publicKey
            ))
        }
        
        let result: NSMutableAttributedString = NSMutableAttributedString(string: string, attributes: attributes)
        mentions.forEach { mention in
            // FIXME: This might break when swapping between themes
            let color = isOutgoingMessage ? (isLightMode ? .white : .black) : Colors.accent
            result.addAttribute(.foregroundColor, value: color, range: mention.range)
            result.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.smallFontSize), range: mention.range)
        }
        
        return result
    }
}
