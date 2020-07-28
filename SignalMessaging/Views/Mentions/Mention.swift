//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objcMembers
public class Mention: NSObject {
    public static let mentionPrefix = "@"
    public static let mentionPrefixLength = (mentionPrefix as NSString).length

    // Each mention has a uniqueID so we can differentiate
    // two mentions for the same address that are side-by-side
    public let uniqueId = UUID().uuidString
    public let address: SignalServiceAddress

    public let style: Style
    @objc(MentionStyle)
    public enum Style: Int {
        case incoming
        case outgoing

        public static var composing: Self = .incoming
    }

    public let text: String
    public var length: Int { (text as NSString).length }

    public init(address: SignalServiceAddress, style: Style) {
        self.address = address
        self.style = style
        self.text = Self.mentionPrefix + Environment.shared.contactsManager.displayName(for: address)
    }

    public var attributedString: NSAttributedString { NSAttributedString(string: text, attributes: attributes) }

    public var attributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .mention: self,
            .font: UIFont.ows_dynamicTypeBody
        ]

        switch style {
        case .incoming:
            attributes[.backgroundColor] = Theme.isDarkThemeEnabled ? .ows_blackAlpha20 : UIColor(rgbHex: 0xCCCCCC)
            attributes[.foregroundColor] = ConversationStyle.bubbleTextColorIncoming
        case .outgoing:
            attributes[.backgroundColor] = Theme.isDarkThemeEnabled ? .ows_blackAlpha20 : UIColor.ows_signalBlueDark
            attributes[.foregroundColor] = ConversationStyle.bubbleTextColorOutgoing
        }

        return attributes
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Mention else { return false }
        return other.uniqueId == uniqueId
    }
    override public var hash: Int { uniqueId.hashValue }
}

extension NSAttributedString.Key {
    static let mention = NSAttributedString.Key("Mention")
}

extension MessageBody {
    convenience init(attributedString: NSAttributedString) {
        var mentionRanges = [NSRange: UUID]()

        let mutableAttributedString = attributedString.mutableCopy() as! NSMutableAttributedString

        mutableAttributedString.enumerateAttribute(
            .mention,
            in: NSRange(location: 0, length: attributedString.length),
            options: .longestEffectiveRangeNotRequired
        ) { mention, subrange, _ in
            guard let mention = mention as? Mention else { return }

            // This string may not be a full mention, for example we may
            // have copied a string that only selects part of a mention.
            // We only want to treat it as a mention if we have the full
            // thing.
            guard subrange.length == mention.length else { return }

            mutableAttributedString.replaceCharacters(in: subrange, with: Self.mentionPlaceholder)

            let placeholderRange = NSRange(
                location: subrange.location,
                length: (Self.mentionPlaceholder as NSString).length
            )
            mentionRanges[placeholderRange] = mention.address.uuid
        }

        self.init(text: mutableAttributedString.string, mentionRanges: mentionRanges)
    }
}
