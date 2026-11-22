//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class BackupArchiveReactionArchiver {
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError

    private let reactionStore: BackupArchiveReactionStore

    init(reactionStore: BackupArchiveReactionStore) {
        self.reactionStore = reactionStore
    }

    // MARK: - Archiving

    func archiveReactions(
        _ message: TSMessage,
        context: BackupArchive.RecipientArchivingContext,
    ) -> BackupArchive.ArchiveInteractionResult<[BackupProto_Reaction]> {
        let reactions = reactionStore.allReactions(message: message, context: context).reversed()

        var errors = [ArchiveFrameError]()
        var reactionProtos = [BackupProto_Reaction]()

        for (sortOrder, reaction) in reactions.enumerated() {
            guard let authorId = context.recipientId(forRecipientDbRowId: reaction.reactorId) else {
                errors.append(.archiveFrameError(.referencedRecipientIdMissing2(reaction.reactorId)))
                continue
            }

            let sentAtTimestamp = reaction.sentTimestamp
            guard BackupArchive.Timestamps.isValid(sentAtTimestamp) else {
                errors.append(.archiveFrameError(.invalidReactionTimestamp))
                continue
            }

            var reactionProto = BackupProto_Reaction()
            reactionProto.emoji = reaction.emoji
            reactionProto.authorID = authorId.value
            reactionProto.sentTimestamp = sentAtTimestamp
            reactionProto.sortOrder = UInt64(sortOrder)

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
        message: TSMessage,
        threadId: TSThread.RowId,
        context: BackupArchive.RecipientRestoringContext,
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        var reactionErrors = [BackupArchive.RestoreFrameError]()
        for reaction in reactions.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let reactorId: SignalRecipient.RowId?

            switch context[reaction.authorRecipientId] {
            case .localAddress:
                reactorId = context.localSignalRecipientRowId
            case .contact:
                reactorId = context.recipientDbRowId(forBackupRecipientId: reaction.authorRecipientId)
            case .group, .distributionList, .releaseNotesChannel, .callLink:
                // Referencing a group or distributionList as the author is invalid.
                reactionErrors.append(.restoreFrameError(.invalidProtoData(.reactionNotFromAciOrE164)))
                continue
            case nil:
                reactorId = nil
            }
            guard let reactorId else {
                reactionErrors.append(.restoreFrameError(
                    .invalidProtoData(.recipientIdNotFound(reaction.authorRecipientId)),
                ))
                continue
            }
            reactionStore.createReaction(
                message: message,
                reactorId: reactorId,
                threadId: threadId,
                emoji: reaction.emoji,
                sentAtTimestamp: reaction.sentTimestamp,
                context: context,
            )
        }

        if reactionErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), reactionErrors)
        }
    }
}
