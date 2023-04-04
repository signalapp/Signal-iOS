//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objcMembers
public class Mention: NSObject {
    public static let mentionPrefix = MessageBodyRanges.mentionPrefix
    public static let mentionPrefixLength = (mentionPrefix as NSString).length

    public static let attributeKey = NSAttributedString.Key.mention

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
        case quotedReply
        case longMessageView
        case groupReply

        public static var composing: Self = .incoming
    }

    public let text: String
    public var length: Int { (text as NSString).length }

    public class func withSneakyTransaction(address: SignalServiceAddress, style: Style) -> Mention {
        databaseStorage.read { transaction in
            Mention(address: address, style: style, transaction: transaction.unwrapGrdbRead)
        }
    }

    public convenience init(address: SignalServiceAddress, style: Style, transaction: GRDBReadTransaction) {
        let displayName = Self.contactsManager.displayName(
            for: address,
            transaction: transaction.asAnyRead
        )
        self.init(
            address: address,
            style: style,
            text: Self.mentionPrefix + displayName
        )
    }

    private init(address: SignalServiceAddress, style: Style, text: String) {
        self.address = address
        self.style = style
        self.text = text
    }

    public var attributedString: NSAttributedString { NSAttributedString(string: text, attributes: attributes) }

    public var attributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .mention: self,
            .font: UIFont.ows_dynamicTypeBody
        ]

        switch style {
        case .incoming:
            attributes[.backgroundColor] = Theme.isDarkThemeEnabled ? UIColor.ows_gray60 : UIColor.ows_gray20
            attributes[.foregroundColor] = ConversationStyle.bubbleTextColorIncoming
        case .outgoing:
            attributes[.backgroundColor] = UIColor(white: 0, alpha: 0.25)
            attributes[.foregroundColor] = ConversationStyle.bubbleTextColorOutgoing
        case .composingAttachment:
            attributes[.backgroundColor] = UIColor.ows_gray75
            attributes[.foregroundColor] = Theme.darkThemePrimaryColor
        case .quotedReply:
            attributes[.backgroundColor] = nil
            attributes[.foregroundColor] = Theme.primaryTextColor
        case .longMessageView:
            attributes[.backgroundColor] = Theme.isDarkThemeEnabled ? UIColor.ows_signalBlueDark : UIColor.ows_blackAlpha20
            attributes[.foregroundColor] = Theme.primaryTextColor
        case .groupReply:
            attributes[.backgroundColor] = UIColor.ows_gray60
            attributes[.foregroundColor] = UIColor.ows_gray05
        }

        return attributes
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Mention else { return false }
        return other.uniqueId == uniqueId
    }
    override public var hash: Int { uniqueId.hashValue }

    public class func threadAllowsMentionSend(_ thread: TSThread) -> Bool {
        guard let groupThread = thread as? TSGroupThread else { return false }
        return groupThread.groupModel.groupsVersion == .V2
    }

    @objc(refreshAttributedInMutableAttributedString:)
    public class func refreshAttributes(in mutableAttributedString: NSMutableAttributedString) {
        mutableAttributedString.enumerateMentions { mention, subrange, _ in
            guard let mention = mention else { return }
            mutableAttributedString.addAttributes(mention.attributes, range: subrange)
        }
    }

    @objc(updateWithStyle:inMutableAttributedString:)
    public class func updateWithStyle(_ style: Style, in mutableAttributedString: NSMutableAttributedString) {
        mutableAttributedString.enumerateMentions { mention, subrange, _ in
            guard let mention = mention else { return }
            let restyledMention = Mention(address: mention.address, style: style, text: mention.text)
            mutableAttributedString.addAttributes(restyledMention.attributes, range: subrange)
        }
    }
}

extension NSAttributedString.Key {
    public static let mention = NSAttributedString.Key("Mention")
}

extension MessageBody {
    public convenience init(attributedString: NSAttributedString) {
        var mentions = [NSRange: UUID]()

        let filteredAttributedString = attributedString.filterForDisplay
        let mutableAttributedString = NSMutableAttributedString(attributedString: filteredAttributedString)

        // TODO[TextFormatting]: parse out styles as well
        mutableAttributedString.enumerateMentions { mention, subrange, _ in
            guard let mention = mention else { return }

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

        self.init(text: mutableAttributedString.string, ranges: .init(mentions: mentions, styles: []))
    }

    public func textValue(style: Mention.Style,
                          attributes: [NSAttributedString.Key: Any],
                          shouldResolveAddress: (SignalServiceAddress) -> Bool,
                          transaction: GRDBReadTransaction) -> CVTextValue {
        ranges.textValue(text: text,
                         style: style,
                         attributes: attributes,
                         shouldResolveAddress: shouldResolveAddress,
                         transaction: transaction)
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

    public func textValue(text: String,
                          style: Mention.Style,
                          attributes: [NSAttributedString.Key: Any],
                          shouldResolveAddress: (SignalServiceAddress) -> Bool,
                          transaction: GRDBReadTransaction) -> CVTextValue {

        guard hasMentions || !attributes.isEmpty else {
            return .text(text: text)
        }
        let attributedText = attributedBody(text: text,
                                            style: style,
                                            attributes: attributes,
                                            shouldResolveAddress: shouldResolveAddress,
                                            transaction: transaction)
        return .attributedText(attributedText: attributedText)
    }

    @objc
    public func attributedBody(
        text: String,
        style: Mention.Style,
        attributes: [NSAttributedString.Key: Any],
        shouldResolveAddress: (SignalServiceAddress) -> Bool,
        transaction: GRDBReadTransaction
    ) -> NSAttributedString {
        // TODO[TextFormatting]: this drives the text we display in message bubbles.
        // update it to render styles as well.
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

        return NSAttributedString(attributedString: mutableText).filterForDisplay
    }
}

extension NSAttributedString {
    public func enumerateMentions(
        in range: NSRange? = nil,
        handler: (Mention?, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        enumerateAttribute(
            .mention,
            in: range ?? NSRange(location: 0, length: length),
            options: []
        ) { handler($0 as? Mention, $1, $2) }
    }

    // This is private because it's *only* safe to use on mention attributed strings.
    fileprivate var filterForDisplay: NSAttributedString {
        guard length > 0 else { return self }

        if string.ows_stripped().isEmpty { return NSAttributedString(string: "") }

        let mutableString = NSMutableAttributedString(attributedString: self)

        // Filter each non-mention substring

        // TODO: If we ever start supporting other styling than mentions,
        // this method of filtering will fall down. For now, we can safely
        // filter all the text before/after/between mentions and treat it
        // as having the same set of attributes.
        mutableString.enumerateMentions { mention, subrange, _ in
            guard mention == nil else { return }

            let string = mutableString.attributedSubstring(from: subrange).string
            let attributes = mutableString.attributes(at: subrange.location, effectiveRange: nil)

            mutableString.replaceCharacters(
                in: subrange,
                with: NSAttributedString(string: string.filterSubstringForDisplay(), attributes: attributes)
            )
        }

        // Strip the resulting string
        mutableString.ows_strip()

        return NSAttributedString(attributedString: mutableString)
    }
}
