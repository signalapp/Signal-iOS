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

    public static var supportsSecureCoding = true
    public static let mentionPlaceholder = "\u{FFFC}" // Object Replacement Character

    public let text: String
    public let ranges: MessageBodyRanges
    public var hasMentions: Bool { ranges.hasMentions }

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
        isRTL: Bool = CurrentAppContext().isRTL
    ) -> HydratedMessageBody {
        return HydratedMessageBody(
            messageBody: self,
            mentionHydrator: mentionHydrator,
            isRTL: isRTL
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
}

public extension TSThread {

    var allowsMentionSend: Bool {
        guard let groupThread = self as? TSGroupThread else { return false }
        return groupThread.groupModel.groupsVersion == .V2
    }
}
