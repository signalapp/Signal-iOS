//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupReactionArchiver: MessageBackupProtoArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    private let reactionStore: ReactionStore

    init(reactionStore: ReactionStore) {
        self.reactionStore = reactionStore
    }

    // MARK: - Archiving

    func archiveReactions(
        _ message: TSMessage,
        context: MessageBackup.RecipientArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<[BackupProto_Reaction]> {
        let reactions = reactionStore.allReactions(messageId: message.uniqueId, tx: context.tx)

        var errors = [ArchiveFrameError]()
        var reactionProtos = [BackupProto_Reaction]()

        for reaction in reactions {
            guard
                let authorAddress = MessageBackup.ContactAddress(
                    aci: reaction.reactorAci,
                    e164: E164(reaction.reactorPhoneNumber)
                )?.asArchivingAddress()
            else {
                // Skip this reaction.
                errors.append(.archiveFrameError(.invalidReactionAddress, message.uniqueInteractionId))
                continue
            }

            guard let authorId = context[authorAddress] else {
                errors.append(.archiveFrameError(
                    .referencedRecipientIdMissing(authorAddress),
                    message.uniqueInteractionId
                ))
                continue
            }

            var reactionProto = BackupProto_Reaction()
            reactionProto.emoji = reaction.emoji
            reactionProto.authorID = authorId.value
            reactionProto.sentTimestamp = reaction.sentAtTimestamp
            reactionProto.sortOrder = reaction.sortOrder

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
        chatItemId: MessageBackup.ChatItemId,
        message: TSMessage,
        context: MessageBackup.RecipientRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        var reactionErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]()
        for reaction in reactions {
            let reactorAddress = context[reaction.authorRecipientId]

            switch reactorAddress {
            case .localAddress:
                reactionStore.createReactionFromRestoredBackup(
                    uniqueMessageId: message.uniqueId,
                    emoji: reaction.emoji,
                    reactorAci: context.localIdentifiers.aci,
                    sentAtTimestamp: reaction.sentTimestamp,
                    sortOrder: reaction.sortOrder,
                    tx: context.tx
                )
            case .contact(let address):
                if let aci = address.aci {
                    reactionStore.createReactionFromRestoredBackup(
                        uniqueMessageId: message.uniqueId,
                        emoji: reaction.emoji,
                        reactorAci: aci,
                        sentAtTimestamp: reaction.sentTimestamp,
                        sortOrder: reaction.sortOrder,
                        tx: context.tx
                    )
                } else if let e164 = address.e164 {
                    reactionStore.createReactionFromRestoredBackup(
                        uniqueMessageId: message.uniqueId,
                        emoji: reaction.emoji,
                        reactorE164: e164,
                        sentAtTimestamp: reaction.sentTimestamp,
                        sortOrder: reaction.sortOrder,
                        tx: context.tx
                    )
                } else {
                    reactionErrors.append(.restoreFrameError(
                        .invalidProtoData(.reactionNotFromAciOrE164),
                        chatItemId
                    ))
                    continue
                }
            case .group, .distributionList, .releaseNotesChannel:
                // Referencing a group or distributionList as the author is invalid.
                reactionErrors.append(.restoreFrameError(
                    .invalidProtoData(.reactionNotFromAciOrE164),
                    chatItemId
                ))
                continue
            case nil:
                reactionErrors.append(.restoreFrameError(
                    .invalidProtoData(.recipientIdNotFound(reaction.authorRecipientId)),
                    chatItemId
                ))
                continue
            }

        }

        if reactionErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), reactionErrors)
        }
    }
}
