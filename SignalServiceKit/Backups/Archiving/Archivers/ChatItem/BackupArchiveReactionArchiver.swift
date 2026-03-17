//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class BackupArchiveReactionArchiver: BackupArchiveProtoStreamWriter {
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>

    private let attachmentsArchiver: BackupArchiveMessageAttachmentArchiver
    private let reactionStore: BackupArchiveReactionStore

    init(
        attachmentsArchiver: BackupArchiveMessageAttachmentArchiver,
        reactionStore: BackupArchiveReactionStore,
    ) {
        self.attachmentsArchiver = attachmentsArchiver
        self.reactionStore = reactionStore
    }

    // MARK: - Archiving

    func archiveReactions(
        _ message: TSMessage,
        reactionStickerAttachments: BackupArchive.ReactionStickerAttachments,
        context: BackupArchive.RecipientArchivingContext,
    ) -> BackupArchive.ArchiveInteractionResult<[BackupProto_Reaction]> {
        let reactions: [OWSReaction]
        do {
            reactions = try reactionStore.allReactions(message: message, context: context)
        } catch {
            return .completeFailure(.fatalArchiveError(.reactionIteratorError(error)))
        }

        var errors = [ArchiveFrameError]()
        var reactionProtos = [BackupProto_Reaction]()

        for reaction in reactions {
            guard
                let authorAddress = BackupArchive.ContactAddress(
                    aci: reaction.reactorAci,
                    e164: E164(reaction.reactorPhoneNumber),
                )?.asArchivingAddress()
            else {
                // Skip this reaction.
                errors.append(.archiveFrameError(.invalidReactionAddress, message.uniqueInteractionId))
                continue
            }

            guard let authorId = context[authorAddress] else {
                errors.append(.archiveFrameError(
                    .referencedRecipientIdMissing(authorAddress),
                    message.uniqueInteractionId,
                ))
                continue
            }

            let sentAtTimestamp = reaction.sentAtTimestamp
            guard BackupArchive.Timestamps.isValid(sentAtTimestamp) else {
                errors.append(.archiveFrameError(
                    .invalidReactionTimestamp,
                    message.uniqueInteractionId,
                ))
                continue
            }

            var reactionProto = BackupProto_Reaction()
            reactionProto.emoji = reaction.emoji
            reactionProto.authorID = authorId.value
            reactionProto.sentTimestamp = sentAtTimestamp
            reactionProto.sortOrder = reaction.sortOrder

            if
                let sticker = reaction.sticker,
                let stickerReferencedAttachment =
                    reactionStickerAttachments.sticker(for: reaction)
            {
                var stickerProto = BackupProto_Sticker()
                stickerProto.emoji = reaction.emoji
                stickerProto.packID = sticker.packId
                stickerProto.packKey = sticker.packKey
                stickerProto.stickerID = sticker.stickerId
                stickerProto.data = stickerReferencedAttachment.asBackupFilePointer(
                    context: context
                )
                reactionProto.sticker = stickerProto
            }
            reactionProtos.append(reactionProto)
        }

        if errors.isEmpty {
            return .success(reactionProtos)
        } else {
            return .partialFailure(reactionProtos, errors)
        }
    }

    // MARK: Restoring

    func restoreReactions(
        _ reactions: [BackupProto_Reaction],
        chatItemId: BackupArchive.ChatItemId,
        message: TSMessage,
        messageRowId: Int64,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        var reactionErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]()
        for reaction in reactions {
            let reactorAddress = context.recipientContext[reaction.authorRecipientId]

            var sticker: StickerInfo?
            if reaction.hasSticker, !reaction.sticker.packID.isEmpty {
                sticker = StickerInfo(
                    packId: reaction.sticker.packID,
                    packKey: reaction.sticker.packKey,
                    stickerId: reaction.sticker.stickerID
                )
            }

            // OWSReaction row id
            let insertResult: Result<Int64?, Error>
            switch reactorAddress {
            case .localAddress:
                insertResult = Result {
                    try reactionStore.createReaction(
                        uniqueMessageId: message.uniqueId,
                        emoji: reaction.emoji,
                        sticker: sticker,
                        reactorAci: context.localIdentifiers.aci,
                        sentAtTimestamp: reaction.sentTimestamp,
                        sortOrder: reaction.sortOrder,
                        context: context.recipientContext,
                    )
                }
            case .contact(let address):
                if let aci = address.aci {
                    insertResult = Result {
                        try reactionStore.createReaction(
                            uniqueMessageId: message.uniqueId,
                            emoji: reaction.emoji,
                            sticker: sticker,
                            reactorAci: aci,
                            sentAtTimestamp: reaction.sentTimestamp,
                            sortOrder: reaction.sortOrder,
                            context: context.recipientContext,
                        )
                    }
                } else if let e164 = address.e164 {
                    insertResult = Result {
                        try reactionStore.createLegacyReaction(
                            uniqueMessageId: message.uniqueId,
                            emoji: reaction.emoji,
                            reactorE164: e164,
                            sentAtTimestamp: reaction.sentTimestamp,
                            sortOrder: reaction.sortOrder,
                            context: context.recipientContext,
                        )
                    }
                } else {
                    reactionErrors.append(.restoreFrameError(
                        .invalidProtoData(.reactionNotFromAciOrE164),
                        chatItemId,
                    ))
                    continue
                }
            case .group, .distributionList, .releaseNotesChannel, .callLink:
                // Referencing a group or distributionList as the author is invalid.
                reactionErrors.append(.restoreFrameError(
                    .invalidProtoData(.reactionNotFromAciOrE164),
                    chatItemId,
                ))
                continue
            case nil:
                reactionErrors.append(.restoreFrameError(
                    .invalidProtoData(.recipientIdNotFound(reaction.authorRecipientId)),
                    chatItemId,
                ))
                continue
            }

            switch insertResult {
            case .success(let reactionRowId):
                if let reactionRowId {
                    if let sticker {
                        let attachmentResult = attachmentsArchiver.restoreReactionStickerAttachment(
                            reaction.sticker.data,
                            stickerPackId: sticker.packId,
                            stickerId: sticker.stickerId,
                            reactionRowId: reactionRowId,
                            chatItemId: chatItemId,
                            messageRowId: messageRowId,
                            message: message,
                            thread: thread,
                            context: context
                        )
                        innerSwitch: switch attachmentResult.bubbleUp(
                            Void.self,
                            partialErrors: &reactionErrors
                        ) {
                        case .continue:
                            break innerSwitch
                        case .bubbleUpError(let error):
                            return error
                        }
                    }
                } else {
                    reactionErrors.append(
                        .restoreFrameError(
                            .databaseModelMissingRowId(modelClass: OWSReaction.self),
                            chatItemId
                        ),
                    )
                }
            case .failure(let insertError):
                reactionErrors.append(
                    .restoreFrameError(.databaseInsertionFailed(insertError), chatItemId),
                )
            }
        }

        if reactionErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), reactionErrors)
        }
    }
}
