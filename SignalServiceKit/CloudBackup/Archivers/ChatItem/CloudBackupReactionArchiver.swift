//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class CloudBackupReactionArchiver: CloudBackupProtoArchiver {

    private let reactionStore: ReactionStore

    init(
        reactionStore: ReactionStore
    ) {
        self.reactionStore = reactionStore
    }

    // MARK: - Archiving

    func archiveReactions(
        _ message: TSMessage,
        context: CloudBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> CloudBackup.ArchiveInteractionResult<[BackupProtoReaction]> {
        let reactions = reactionStore.allReactions(messageId: message.uniqueId, tx: tx)

        var errors = [CloudBackupChatItemArchiver.ArchiveMultiFrameResult.Error]()
        var reactionProtos = [BackupProtoReaction]()

        for reaction in reactions {
            let authorAddress: CloudBackup.RecipientArchivingContext.Address
            if let aci = reaction.reactorAci {
                authorAddress = .contactAci(aci)
            } else if let e164 = E164(reaction.reactorPhoneNumber) {
                authorAddress = .contactE164(e164)
            } else {
                // Skip this reaction.
                errors.append(.init(objectId: message.chatItemId, error: .invalidReactionAddress))
                continue
            }

            guard let authorId = context[authorAddress] else {
                errors.append(.init(
                    objectId: message.chatItemId,
                    error: .referencedIdMissing(.recipient(authorAddress))
                ))
                continue
            }

            let protoBuilder = BackupProtoReaction.builder(
                emoji: reaction.emoji,
                authorID: authorId.value,
                sentTimestamp: reaction.sentAtTimestamp,
                // TODO: this should be sort order; have to update backup proto.
                receivedTimestamp: reaction.sortOrder
            )

            do {
                let proto = try protoBuilder.build()
                reactionProtos.append(proto)
            } catch {
                errors.append(.init(
                    objectId: message.chatItemId,
                    error: .protoSerializationError(error)
                ))
                continue
            }
        }

        if errors.isEmpty {
            return .success(reactionProtos)
        } else {
            return .partialFailure(reactionProtos, errors)
        }
    }

    // MARK: Restoring

    func restoreReactions(
        _ reactions: [BackupProtoReaction],
        message: TSMessage,
        context: CloudBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> CloudBackup.RestoreInteractionResult<Void> {
        var reactionErrors = [CloudBackup.RestoringFrameError]()
        for reaction in reactions {
            let reactorAddress = context[reaction.authorRecipientId]

            let reactorAci: Aci
            switch reactorAddress {
            case .noteToSelf:
                reactorAci = context.localIdentifiers.aci
            case .contact(let aci, _, _):
                guard let aci else {
                    // Referencing a non-aci author is invalid.
                    reactionErrors.append(.invalidProtoData)
                    continue
                }
                reactorAci = aci
            case .group:
                // Referencing a group as the author is invalid.
                reactionErrors.append(.invalidProtoData)
                continue
            case nil:
                reactionErrors.append(.identifierNotFound(.recipient(reaction.authorRecipientId)))
                continue
            }

            reactionStore.createReactionfromRestoredBackup(
                uniqueMessageId: message.uniqueId,
                emoji: reaction.emoji,
                reactor: reactorAci,
                sentAtTimestamp: reaction.sentTimestamp,
                // TODO: update the proto spec
                sortOrder: reaction.receivedTimestamp,
                tx: tx
            )
        }

        if reactionErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), reactionErrors)
        }
    }
}
