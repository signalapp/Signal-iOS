//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

final internal class BackupArchiveReactionArchiver: BackupArchiveProtoStreamWriter {
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>

    private let reactionStore: BackupArchiveReactionStore

    init(reactionStore: BackupArchiveReactionStore) {
        self.reactionStore = reactionStore
    }

    // MARK: - Archiving

    func archiveReactions(
        _ message: TSMessage,
        context: BackupArchive.RecipientArchivingContext
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

            let sentAtTimestamp = reaction.sentAtTimestamp
            guard BackupArchive.Timestamps.isValid(sentAtTimestamp) else {
                errors.append(.archiveFrameError(
                    .invalidReactionTimestamp,
                    message.uniqueInteractionId
                ))
                continue
            }

            var reactionProto = BackupProto_Reaction()
            reactionProto.emoji = reaction.emoji
            reactionProto.authorID = authorId.value
            reactionProto.sentTimestamp = sentAtTimestamp
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
        chatItemId: BackupArchive.ChatItemId,
        message: TSMessage,
        context: BackupArchive.RecipientRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        var reactionErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]()
        for reaction in reactions {
            let reactorAddress = context[reaction.authorRecipientId]

            let insertResult: Result<Void, Error>
            switch reactorAddress {
            case .localAddress:
                insertResult = Result {
                    try reactionStore.createReaction(
                        uniqueMessageId: message.uniqueId,
                        emoji: reaction.emoji,
                        reactorAci: context.localIdentifiers.aci,
                        sentAtTimestamp: reaction.sentTimestamp,
                        sortOrder: reaction.sortOrder,
                        context: context
                    )
                }
            case .contact(let address):
                if let aci = address.aci {
                    insertResult = Result {
                        try reactionStore.createReaction(
                            uniqueMessageId: message.uniqueId,
                            emoji: reaction.emoji,
                            reactorAci: aci,
                            sentAtTimestamp: reaction.sentTimestamp,
                            sortOrder: reaction.sortOrder,
                            context: context
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
                            context: context
                        )
                    }
                } else {
                    reactionErrors.append(.restoreFrameError(
                        .invalidProtoData(.reactionNotFromAciOrE164),
                        chatItemId
                    ))
                    continue
                }
            case .group, .distributionList, .releaseNotesChannel, .callLink:
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

            switch insertResult {
            case .success:
                break
            case .failure(let insertError):
                reactionErrors.append(
                    .restoreFrameError(.databaseInsertionFailed(insertError), chatItemId)
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
