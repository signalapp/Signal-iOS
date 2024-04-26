//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupReactionArchiver: MessageBackupProtoArchiver {

    private let reactionStore: ReactionStore

    init(
        reactionStore: ReactionStore
    ) {
        self.reactionStore = reactionStore
    }

    // MARK: - Archiving

    func archiveReactions(
        _ message: TSMessage,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<[BackupProto.Reaction]> {
        let reactions = reactionStore.allReactions(messageId: message.uniqueId, tx: tx)

        var errors = [MessageBackupChatItemArchiver.ArchiveMultiFrameResult.ArchiveFrameError]()
        var reactionProtos = [BackupProto.Reaction]()

        for reaction in reactions {
            guard
                let authorAddress = MessageBackup.ContactAddress(
                    aci: reaction.reactorAci,
                    e164: E164(reaction.reactorPhoneNumber)
                )?.asArchivingAddress()
            else {
                // Skip this reaction.
                errors.append(.invalidReactionAddress(message.uniqueInteractionId))
                continue
            }

            guard let authorId = context[authorAddress] else {
                errors.append(.referencedRecipientIdMissing(
                    message.uniqueInteractionId,
                    authorAddress
                ))
                continue
            }

            let reaction = BackupProto.Reaction(
                emoji: reaction.emoji,
                authorId: authorId.value,
                sentTimestamp: reaction.sentAtTimestamp,
                sortOrder: reaction.sortOrder
            )

            reactionProtos.append(reaction)
        }

        if errors.isEmpty {
            return .success(reactionProtos)
        } else {
            return .partialFailure(reactionProtos, errors)
        }
    }

    // MARK: Restoring

    func restoreReactions(
        _ reactions: [BackupProto.Reaction],
        chatItemId: MessageBackup.ChatItemId,
        message: TSMessage,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
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
                    tx: tx
                )
            case .contact(let address):
                if let aci = address.aci {
                    reactionStore.createReactionFromRestoredBackup(
                        uniqueMessageId: message.uniqueId,
                        emoji: reaction.emoji,
                        reactorAci: aci,
                        sentAtTimestamp: reaction.sentTimestamp,
                        sortOrder: reaction.sortOrder,
                        tx: tx
                    )
                } else if let e164 = address.e164 {
                    reactionStore.createReactionFromRestoredBackup(
                        uniqueMessageId: message.uniqueId,
                        emoji: reaction.emoji,
                        reactorE164: e164,
                        sentAtTimestamp: reaction.sentTimestamp,
                        sortOrder: reaction.sortOrder,
                        tx: tx
                    )
                } else {
                    reactionErrors.append(
                        .invalidProtoData(chatItemId, .reactionNotFromAciOrE164)
                    )
                    continue
                }
            case .group:
                // Referencing a group as the author is invalid.
                reactionErrors.append(
                    .invalidProtoData(chatItemId, .reactionNotFromAciOrE164)
                )
                continue
            case nil:
                reactionErrors.append(.invalidProtoData(
                    chatItemId,
                    .recipientIdNotFound(reaction.authorRecipientId)
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
