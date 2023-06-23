//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// MessageBody is a container for a message's body as well as the `MessageBodyRanges` that
/// apply to it.
/// Most of the work is done by `MessageBodyRanges`; this is just a container for the text too.
@objcMembers
public class MessageBody: NSObject, NSCopying, NSSecureCoding {

    typealias Style = MessageBodyRanges.Style
    typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    public static var supportsSecureCoding = true
    public static let mentionPlaceholder = "\u{FFFC}" // Object Replacement Character

    public let text: String
    public let ranges: MessageBodyRanges
    public var hasRanges: Bool { ranges.hasRanges }
    private var hasMentions: Bool { ranges.hasMentions }

    public init(text: String, ranges: MessageBodyRanges) {
        self.text = text
        self.ranges = ranges
    }

    public required init?(coder: NSCoder) {
        guard let text = coder.decodeObject(of: NSString.self, forKey: "text") as String? else {
            owsFailDebug("Missing text")
            return nil
        }

        guard let ranges = coder.decodeObject(of: MessageBodyRanges.self, forKey: "ranges") else {
            owsFailDebug("Missing ranges")
            return nil
        }

        self.text = text
        self.ranges = ranges
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return MessageBody(text: text, ranges: ranges)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(text, forKey: "text")
        coder.encode(ranges, forKey: "ranges")
    }

    public func hydrating(
        mentionHydrator: MentionHydrator,
        filterStringForDisplay: Bool = true,
        isRTL: Bool = CurrentAppContext().isRTL
    ) -> HydratedMessageBody {
        let body = filterStringForDisplay ? self.filterStringForDisplay() : self
        return HydratedMessageBody(
            messageBody: body,
            mentionHydrator: mentionHydrator,
            isRTL: isRTL
        )
    }

    // Strip leading and trailing whitespace and other non-printed characters,
    // preserving ranges.
    public func filterStringForDisplay() -> MessageBody {
        let originalText = text as NSString
        let filteredText = originalText.filterStringForDisplay() as NSString

        guard filteredText.length != originalText.length else {
            // if we didn't strip anything, nothing needs to change.
            return self
        }
        // We filtered things, we need to adjust ranges.

        // NOTE that we only handle leading characters getting stripped;
        // if characters in the middle of the string get stripped that
        // will mess up all the ranges. That never has been handled by the app.

        let strippedPrefixLength = originalText.range(of: filteredText as String).location
        let filteredStringEntireRange = NSRange(location: 0, length: filteredText.length)

        var adjustedMentions = [NSRange: UUID]()
        let orderedAdjustedMentions: [NSRangedValue<UUID>] = ranges.orderedMentions.compactMap { mention in
            guard
                let newRange = NSRange(
                    location: mention.range.location - strippedPrefixLength,
                    length: mention.range.length
                ).intersection(filteredStringEntireRange),
                  newRange.length > 0
            else {
                return nil
            }
            adjustedMentions[newRange] = mention.value
            return .init(mention.value, range: newRange)
        }
        let adjustedStyles: [NSRangedValue<CollapsedStyle>] = ranges.collapsedStyles.compactMap { style in
            guard
                let newRange = NSRange(
                    location: style.range.location - strippedPrefixLength,
                    length: style.range.length
                ).intersection(filteredStringEntireRange),
                newRange.length > 0
            else {
                return nil
            }
            return .init(
                style.value,
                range: newRange
            )
        }
        return MessageBody(
            text: filteredText as String,
            ranges: MessageBodyRanges(
                mentions: adjustedMentions,
                orderedMentions: orderedAdjustedMentions,
                collapsedStyles: adjustedStyles
            )
        )
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MessageBody else {
            return false
        }
        guard text == other.text else {
            return false
        }
        guard ranges == other.ranges else {
            return false
        }
        return true
    }
}

extension MessageBody {

    /// Convenience method to hydrate a MessageBody for forwarding to a thread destination.
    public func forForwarding(
        to context: TSThread,
        transaction: GRDBReadTransaction,
        isRTL: Bool = CurrentAppContext().isRTL
    ) -> HydratedMessageBody {
        guard hasMentions else {
            return hydrating(mentionHydrator: { _ in return .preserveMention }, isRTL: isRTL)
        }

        let groupMemberUuids: Set<UUID>
        if let groupThread = context as? TSGroupThread, groupThread.isGroupV2Thread {
            groupMemberUuids = Set(groupThread.recipientAddresses(with: transaction.asAnyRead).compactMap(\.uuid))
        } else {
            groupMemberUuids = Set()
        }
        // We want to preserve mentions for group members of the detination group,
        // not hydrate them. They will be hydrated by us and all other members
        // with their own info when they actually get rendered. Non-members may
        // not be known to everyone so we need to hydrate them out.
        let mentionHydrator = ContactsMentionHydrator.mentionHydrator(
            excludedUuids: groupMemberUuids,
            transaction: transaction.asAnyRead.asV2Read
        )

        return hydrating(mentionHydrator: mentionHydrator, isRTL: isRTL)
    }

    /// When pasting a message body into a new context, we need to hydrate mentions
    /// that don't belong in the new context (such that they are just plaintext of the contact name
    /// as we know it), and maintain mentions that do apply.
    ///
    /// This context is not necessarily one single thread; we could be pasting into a composer
    /// for sending to multiple threads. So the input array is _all_ valid addresses.
    public func forPasting(
        intoContextWithPossibleAddresses possibleAddresses: [SignalServiceAddress],
        transaction: DBReadTransaction,
        isRTL: Bool = CurrentAppContext().isRTL
    ) -> MessageBody {
        guard hasMentions else {
            return self
        }
        let mentionHydrator = ContactsMentionHydrator.mentionHydrator(
            excludedUuids: Set(possibleAddresses.compactMap(\.uuid)),
            transaction: transaction
        )
        return hydrating(mentionHydrator: mentionHydrator, isRTL: isRTL).asMessageBodyForForwarding()
    }

    // MARK: Merging

    /// Given a substring and set of styles _within that substring_, returns the same
    /// substring if found with provided styles merged with the overall styles from
    /// the entire message body.
    ///
    /// If the substring is not found, returns self.
    ///
    /// The provided styles should have their locations in the substring's local coordinates,
    /// e.g. 0 being the first character of the substring.
    public func mergeIntoFirstMatchOfStyledSubstring(
        _ substring: String,
        styles: [NSRangedValue<MessageBodyRanges.Style>]
    ) -> MessageBody {
        // First find the offset.
        let substringRange = (text as NSString).range(of: substring)
        guard substringRange.location != NSNotFound else {
            return self
        }
        let subrangeStyles = MessageBodyRanges.SubrangeStyles(
            substringRange: substringRange,
            stylesInSubstring: styles
        )
        let newRanges = self.ranges.mergingStyles(subrangeStyles)
        return MessageBody(
            text: substring,
            ranges: newRanges
        )
    }
}

public extension TSThread {

    var allowsMentionSend: Bool {
        guard let groupThread = self as? TSGroupThread else { return false }
        return groupThread.groupModel.groupsVersion == .V2
    }
}
