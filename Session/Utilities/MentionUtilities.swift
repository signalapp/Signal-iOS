// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUIKit
import SessionMessagingKit

public enum MentionUtilities {
    public static func highlightMentionsNoAttributes(
        in string: String,
        threadVariant: SessionThread.Variant,
        currentUserPublicKey: String,
        currentUserBlindedPublicKey: String?
    ) -> String {
        /// **Note:** We are returning the string here so the 'textColor' and 'primaryColor' values are irrelevant
        return highlightMentions(
            in: string,
            threadVariant: threadVariant,
            currentUserPublicKey: currentUserPublicKey,
            currentUserBlindedPublicKey: currentUserBlindedPublicKey,
            isOutgoingMessage: false,
            textColor: .black,
            theme: .classicDark,
            primaryColor: Theme.PrimaryColor.green,
            attributes: [:]
        ).string
    }

    public static func highlightMentions(
        in string: String,
        threadVariant: SessionThread.Variant,
        currentUserPublicKey: String?,
        currentUserBlindedPublicKey: String?,
        isOutgoingMessage: Bool,
        textColor: UIColor,
        theme: Theme,
        primaryColor: Theme.PrimaryColor,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        guard
            let regex: NSRegularExpression = try? NSRegularExpression(pattern: "@[0-9a-fA-F]{66}", options: [])
        else {
            return NSAttributedString(string: string)
        }
        
        var string = string
        var lastMatchEnd: Int = 0
        var mentions: [(range: NSRange, isCurrentUser: Bool)] = []
        let currentUserPublicKeys: Set<String> = [
            currentUserPublicKey,
            currentUserBlindedPublicKey
        ]
        .compactMap { $0 }
        .asSet()
        
        while let match: NSTextCheckingResult = regex.firstMatch(
            in: string,
            options: .withoutAnchoringBounds,
            range: NSRange(location: lastMatchEnd, length: string.utf16.count - lastMatchEnd)
        ) {
            guard let range: Range = Range(match.range, in: string) else { break }
            
            let publicKey: String = String(string[range].dropFirst()) // Drop the @
            let isCurrentUser: Bool = currentUserPublicKeys.contains(publicKey)
            
            guard let targetString: String = {
                guard !isCurrentUser else { return "MEDIA_GALLERY_SENDER_NAME_YOU".localized() }
                guard let displayName: String = Profile.displayNameNoFallback(id: publicKey, threadVariant: threadVariant) else {
                    lastMatchEnd = (match.range.location + match.range.length)
                    return nil
                }
                
                return displayName
            }()
            else { continue }
            
            string = string.replacingCharacters(in: range, with: "@\(targetString)")
            lastMatchEnd = (match.range.location + targetString.utf16.count)
            
            mentions.append((
                // + 1 to include the @
                range: NSRange(location: match.range.location, length: targetString.utf16.count + 1),
                isCurrentUser: isCurrentUser
            ))
        }
        
        let sizeDiff: CGFloat = (Values.smallFontSize / Values.mediumFontSize)
        let result: NSMutableAttributedString = NSMutableAttributedString(string: string, attributes: attributes)
        mentions.forEach { mention in
            result.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.smallFontSize), range: mention.range)
            
            if mention.isCurrentUser {
                // Note: The designs don't match with the dynamic sizing so these values need to be calculated
                // to maintain a "rounded rect" effect rather than a "pill" effect
                result.addAttribute(.currentUserMentionBackgroundCornerRadius, value: (8 * sizeDiff), range: mention.range)
                result.addAttribute(.currentUserMentionBackgroundPadding, value: (3 * sizeDiff), range: mention.range)
                result.addAttribute(.currentUserMentionBackgroundColor, value: primaryColor.color, range: mention.range)
                result.addAttribute(
                    .foregroundColor,
                    value: UIColor.black,   // Note: This text should always be black
                    range: mention.range
                )
            }
            else {
                result.addAttribute(
                    .foregroundColor,
                    value: (isOutgoingMessage || theme.interfaceStyle == .light ?
                        textColor :
                        primaryColor.color
                    ),
                    range: mention.range
                )
            }
        }
        
        return result
    }
}
