//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

/// Key for grouping reactions on a message. Sticker reactions are grouped by
/// (packId + stickerId), while emoji reactions are grouped by canonical base emoji.
public enum ReactionGroupKey: Hashable {
    case emoji(String)
    case sticker(packId: Data, stickerId: UInt32)

    init?(reaction: OWSReaction) {
        if let sticker = reaction.sticker {
            self = .sticker(packId: sticker.packId, stickerId: sticker.stickerId)
        } else if let emoji = EmojiWithSkinTones(rawValue: reaction.emoji) {
            self = .emoji(emoji.baseEmoji.rawValue)
        } else {
            return nil
        }
    }
}

public class InteractionReactionState: NSObject {
    var hasReactions: Bool { return !emojiCounts.isEmpty }

    struct EmojiCount {
        let emoji: String
        let groupKey: ReactionGroupKey
        let count: Int
        let highestSortOrder: UInt64
        let stickerAttachment: CVAttachment?
    }

    let reactionsByGroupKey: [ReactionGroupKey: [OWSReaction]]
    let emojiCounts: [EmojiCount]
    let localUserReaction: OWSReaction?
    let stickerAttachmentByReactionId: [Int64: CVAttachment]

    var localUserReactionGroupKey: ReactionGroupKey? {
        localUserReaction.flatMap { ReactionGroupKey(reaction: $0) }
    }

    init?(interaction: TSInteraction, transaction: DBReadTransaction) {
        guard let message = interaction as? TSMessage else { return nil }

        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress else {
            owsFailDebug("missing local address")
            return nil
        }

        let finder = ReactionFinder(uniqueMessageId: message.uniqueId)
        let allReactions = finder.allReactions(transaction: transaction)
        let localUserReaction = allReactions.first(where: { $0.reactor == localAddress })

        var stickerAttachmentByReactionIdLocal = [Int64: CVAttachment]()
        if let messageRowId = message.sqliteRowId {
            let attachmentStore = DependenciesBridge.shared.attachmentStore
            let allRefs = attachmentStore.fetchReferencedAttachmentsOwnedByMessage(
                messageRowId: messageRowId,
                tx: transaction,
            )
            for referencedAttachment in allRefs {
                if case .message(.reactionSticker(let metadata)) = referencedAttachment.reference.owner {
                    if let stream = referencedAttachment.asReferencedStream {
                        stickerAttachmentByReactionIdLocal[metadata.reactionRowId] = .stream(stream)
                    } else if let pointer = referencedAttachment.asReferencedAnyPointer {
                        stickerAttachmentByReactionIdLocal[metadata.reactionRowId] = .pointer(
                            pointer,
                            downloadState: pointer.attachmentPointer.downloadState(tx: transaction)
                        )
                    } else {
                        // If we can't download, fall back to displaying emoji (no sticker).
                        stickerAttachmentByReactionIdLocal[metadata.reactionRowId] = nil
                    }
                }
            }
        }

        // Group reactions by ReactionGroupKey so that sticker reactions are never
        // merged with pure emoji reactions that share the same associated emoji.
        reactionsByGroupKey = allReactions.reduce(
            into: [ReactionGroupKey: [OWSReaction]](),
        ) { result, reaction in
            guard let key = ReactionGroupKey(reaction: reaction) else {
                return owsFailDebug("Skipping reaction with [unknown emoji]")
            }

            var reactions = result[key] ?? []
            reactions.append(reaction)
            result[key] = reactions
        }

        emojiCounts = reactionsByGroupKey.compactMap { (groupKey, reactions) in
            guard let mostRecentReaction = reactions.first else {
                owsFailDebug("unexpectedly missing reactions")
                return nil
            }
            let mostRecentEmoji = mostRecentReaction.emoji

            let emojiToRender: String
            if let localUserReaction, reactions.contains(localUserReaction) {
                emojiToRender = localUserReaction.emoji
            } else {
                emojiToRender = mostRecentEmoji
            }

            let highestSortOrder =
                (reactions.map { $0.sortOrder }.max() ?? mostRecentReaction.sortOrder)

            let stickerAttachment: CVAttachment? = {
                if
                    let reactionId = mostRecentReaction.id,
                    let state = stickerAttachmentByReactionIdLocal[reactionId]
                {
                    return state
                }
                return nil
            }()

            return EmojiCount(
                emoji: emojiToRender,
                groupKey: groupKey,
                count: reactions.count,
                highestSortOrder: highestSortOrder,
                stickerAttachment: stickerAttachment,
            )
        }.sorted { (lhs: EmojiCount, rhs: EmojiCount) in
            if lhs.count != rhs.count {
                // Sort more common reactions (higher counter) first.
                return lhs.count > rhs.count
            } else if lhs.highestSortOrder != rhs.highestSortOrder {
                // Sort reactions received in descending order of when we received them.
                return lhs.highestSortOrder > rhs.highestSortOrder
            } else {
                // Ensure stability of sort by comparing emoji.
                return lhs.emoji > rhs.emoji
            }
        }

        self.localUserReaction = localUserReaction
        stickerAttachmentByReactionId = stickerAttachmentByReactionIdLocal
    }
}
