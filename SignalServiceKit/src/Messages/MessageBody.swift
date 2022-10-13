//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objcMembers
public class MessageBody: NSObject, NSCopying, NSSecureCoding {
    public static var supportsSecureCoding = true
    public static let mentionPlaceholder = "\u{FFFC}" // Object Replacement Character

    public let text: String
    public let ranges: MessageBodyRanges
    public var hasRanges: Bool { ranges.hasMentions }

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

    public func plaintextBody(transaction: GRDBReadTransaction) -> String {
        return ranges.plaintextBody(text: text, transaction: transaction)
    }

    public func forNewContext(
        _ context: TSThread,
        transaction: GRDBReadTransaction
    ) -> MessageBody {
        guard hasRanges else { return self }
        guard let groupThread = context as? TSGroupThread, groupThread.isGroupV2Thread else {
            return MessageBody(text: plaintextBody(transaction: transaction), ranges: .empty)
        }

        let mutableText = NSMutableString(string: text)
        var mentions = [NSRange: UUID]()
        var rangeOffset = 0

        func shouldPreserveMention(_ address: SignalServiceAddress) -> Bool {
            return groupThread.recipientAddressesWithSneakyTransaction.contains(address)
        }

        for (range, uuid) in ranges.orderedMentions {
            guard range.location >= 0 && range.location + range.length <= (text as NSString).length else {
                owsFailDebug("Ignoring invalid range in body ranges \(range)")
                continue
            }

            let mentionAddress = SignalServiceAddress(uuid: uuid)
            let offsetRange = NSRange(location: range.location + rangeOffset, length: range.length)

            if shouldPreserveMention(mentionAddress) {
                mentions[offsetRange] = uuid
            } else {
                let displayName = Self.contactsManager.displayName(
                    for: mentionAddress,
                    transaction: transaction.asAnyRead
                )
                let mentionPlaintext = MessageBodyRanges.mentionPrefix + displayName
                mutableText.replaceCharacters(in: offsetRange, with: mentionPlaintext)
                rangeOffset += (mentionPlaintext as NSString).length - range.length
            }
        }

        return MessageBody(text: String(mutableText), ranges: MessageBodyRanges(mentions: mentions))
    }
}

@objcMembers
public class MessageBodyRanges: NSObject, NSCopying, NSSecureCoding {
    public static var supportsSecureCoding = true
    public static let mentionPrefix = "@"
    public static var empty: MessageBodyRanges { MessageBodyRanges(mentions: [:]) }

    public let mentions: [NSRange: UUID]
    public var hasMentions: Bool { !mentions.isEmpty }

    // Sorted from lowest location to highest location
    public var orderedMentions: [(NSRange, UUID)] {
        mentions.sorted(by: { $0.key.location < $1.key.location })
    }

    public init(mentions: [NSRange: UUID]) {
        self.mentions = mentions

        super.init()
    }

    public convenience init(protos: [SSKProtoDataMessageBodyRange]) {
        var mentions = [NSRange: UUID]()
        for proto in protos {
            guard let mentionUuidString = proto.mentionUuid, let mentionUuid = UUID(uuidString: mentionUuidString) else { continue }
            let range = NSRange(location: Int(proto.start), length: Int(proto.length))
            mentions[range] = mentionUuid
        }
        self.init(mentions: mentions)
    }

    public required init?(coder: NSCoder) {
        let mentionsCount = coder.decodeInteger(forKey: "mentionsCount")

        var mentions = [NSRange: UUID]()
        for idx in 0..<mentionsCount {
            guard let range = coder.decodeObject(of: NSValue.self, forKey: "mentions.range.\(idx)")?.rangeValue else {
                owsFailDebug("Failed to decode mention range key of MessageBody")
                return nil
            }
            guard let uuid = coder.decodeObject(of: NSUUID.self, forKey: "mentions.uuid.\(idx)") as UUID? else {
                owsFailDebug("Failed to decode mention range value of MessageBody")
                return nil
            }
            mentions[range] = uuid
        }

        self.mentions = mentions
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return MessageBodyRanges(mentions: mentions)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(mentions.count, forKey: "mentionsCount")
        for (idx, (range, uuid)) in mentions.enumerated() {
            coder.encode(NSValue(range: range), forKey: "mentions.range.\(idx)")
            coder.encode(uuid, forKey: "mentions.uuid.\(idx)")
        }
    }

    public func plaintextBody(text: String, transaction: GRDBReadTransaction) -> String {
        guard hasMentions else { return text }

        let mutableText = NSMutableString(string: text)

        for (range, uuid) in orderedMentions.reversed() {
            guard range.location >= 0 && range.location + range.length <= (text as NSString).length else {
                owsFailDebug("Ignoring invalid range in body ranges \(range)")
                continue
            }

            let displayName = Self.contactsManager.displayName(
                for: SignalServiceAddress(uuid: uuid),
                transaction: transaction.asAnyRead
            )
            mutableText.replaceCharacters(in: range, with: Self.mentionPrefix + displayName)
        }

        return mutableText.filterStringForDisplay()
    }
}
