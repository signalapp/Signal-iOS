//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objcMembers
public class Mention: NSObject {
    public static let mentionPrefix = MessageBodyRanges.mentionPrefix
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
        case composingAttachment

        public static var composing: Self = .incoming
    }

    public let text: String
    public var length: Int { (text as NSString).length }

    public class func withSneakyTransaction(address: SignalServiceAddress, style: Style) -> Mention {
        return SDSDatabaseStorage.shared.uiRead { transaction in
            return Mention(address: address, style: style, transaction: transaction.unwrapGrdbRead)
        }
    }

    public init(address: SignalServiceAddress, style: Style, transaction: GRDBReadTransaction) {
        self.address = address
        self.style = style
        self.text = Self.mentionPrefix + Environment.shared.contactsManager.displayName(for: address, transaction: transaction.asAnyRead)
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
        case .composingAttachment:
            attributes[.backgroundColor] = UIColor.ows_gray75
            attributes[.foregroundColor] = Theme.darkThemePrimaryColor
        }

        return attributes
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Mention else { return false }
        return other.uniqueId == uniqueId
    }
    override public var hash: Int { uniqueId.hashValue }

    public class func threadAllowsMentionSend(_ thread: TSThread) -> Bool {
        guard FeatureFlags.mentionsSend else { return false }
        guard let groupThread = thread as? TSGroupThread else { return false }
        return groupThread.groupModel.groupsVersion == .V2
    }
}

extension NSAttributedString.Key {
    static let mention = NSAttributedString.Key("Mention")
}

extension MessageBody {
    public convenience init(attributedString: NSAttributedString) {
        var mentions = [NSRange: UUID]()

        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)

        mutableAttributedString.enumerateAttribute(
            .mention,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
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
            mentions[placeholderRange] = mention.address.uuid
        }

        self.init(text: mutableAttributedString.string, ranges: .init(mentions: mentions))
    }

    @objc
    public func attributedBody(
        style: Mention.Style,
        attributes: [NSAttributedString.Key: Any],
        shouldResolveAddress: (SignalServiceAddress) -> Bool,
        transaction: GRDBReadTransaction
    ) -> NSAttributedString {
        return ranges.attributedBody(
            text: text,
            style: style,
            attributes: attributes,
            shouldResolveAddress: shouldResolveAddress,
            transaction: transaction
        )
    }
}

extension MessageBodyRanges {
    @objc
    public func attributedBody(
        text: String,
        style: Mention.Style,
        attributes: [NSAttributedString.Key: Any],
        shouldResolveAddress: (SignalServiceAddress) -> Bool,
        transaction: GRDBReadTransaction
    ) -> NSAttributedString {
        guard hasMentions else { return NSAttributedString(string: text, attributes: attributes) }

        let mutableText = NSMutableAttributedString(string: text, attributes: attributes)

        for (range, uuid) in orderedMentions.reversed() {
            guard range.location >= 0 && range.location + range.length <= (text as NSString).length else {
                owsFailDebug("Ignoring invalid range in body ranges \(range)")
                continue
            }

            let mention = Mention(
                address: SignalServiceAddress(uuid: uuid),
                style: style,
                transaction: transaction
            )

            if shouldResolveAddress(mention.address) {
                mutableText.replaceCharacters(in: range, with: mention.attributedString)
            } else {
                mutableText.replaceCharacters(in: range, with: mention.text)
            }
        }

        return NSAttributedString(attributedString: mutableText)
    }
}
