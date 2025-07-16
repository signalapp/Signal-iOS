//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum InteractionDelete {
    /// Specifies the desired side effects of deleting interactions.
    public struct SideEffects {
        /// Specifies what should happen with the ``CallRecord`` associated with
        /// a ``TSInteraction`` being deleted, if one exists.
        public enum AssociatedCallDeleteBehavior {
            /// Delete any ``CallRecord`` associated with the interaction, and
            /// send a `CallEvent` sync message about that deletion.
            case localDeleteAndSendCallEventSyncMessage

            /// Delete any ``CallRecord`` associated with the interaction.
            case localDeleteOnly
        }

        /// Specifies behavior for updating the thread associated with an
        /// interaction when that interaction is deleted.
        public enum UpdateThreadOnInteractionDeleteBehavior {
            /// Update the thread after the interaction is deleted.
            case updateOnEachDeletedInteraction

            /// Skip updating the thread. This value should be used to suppress
            /// intermediate thread updates during a bulk interaction delete.
            case doNotUpdate
        }

        /// Specifies behavior for sending a `DeleteForMe` sync message for any
        /// deleted interactions.
        public enum DeleteForMeSyncMessageBehavior {
            /// Send a sync message.
            /// - Important
            /// Any interactions this case is applied to must match the given
            /// thread.
            case sendSyncMessage(interactionsThread: TSThread)

            /// Do not send a sync message.
            case doNotSend
        }

        let associatedCallDelete: AssociatedCallDeleteBehavior
        let updateThreadOnInteractionDelete: UpdateThreadOnInteractionDeleteBehavior
        let deleteForMeSyncMessage: DeleteForMeSyncMessageBehavior

        private init(
            associatedCallDelete: AssociatedCallDeleteBehavior,
            updateThreadOnInteractionDelete: UpdateThreadOnInteractionDeleteBehavior,
            deleteForMeSyncMessage: DeleteForMeSyncMessageBehavior
        ) {
            self.associatedCallDelete = associatedCallDelete
            self.updateThreadOnInteractionDelete = updateThreadOnInteractionDelete
            self.deleteForMeSyncMessage = deleteForMeSyncMessage
        }

        public static func `default`() -> SideEffects {
            return .custom()
        }

        public static func custom(
            associatedCallDelete: AssociatedCallDeleteBehavior = .localDeleteAndSendCallEventSyncMessage,
            updateThreadOnInteractionDelete: UpdateThreadOnInteractionDeleteBehavior = .updateOnEachDeletedInteraction,
            deleteForMeSyncMessage: DeleteForMeSyncMessageBehavior = .doNotSend
        ) -> SideEffects {
            return SideEffects(
                associatedCallDelete: associatedCallDelete,
                updateThreadOnInteractionDelete: updateThreadOnInteractionDelete,
                deleteForMeSyncMessage: deleteForMeSyncMessage
            )
        }
    }
}

/// Responsible for deleting ``TSInteraction``s, and initiating ``CallRecord``
/// deletion.
///
/// - Note
/// Every ``CallRecord`` is associated with a ``TSInteraction``, and when
/// one is deleted the other should be as well.
///
/// Correspondingly, this manager also provides an entrypoint for callers to
/// delete call records alongside their associated interactions. This may seem
/// counterintuitive, but avoids a circular dependency between interaction and
/// call record deletion.
///
/// - SeeAlso
/// If you're calling this type for a user-initiated deletion, consider using
/// ``DeleteForMeInfoSheetCoordinator`` in the Signal target instead, which
/// handles some one-time informational UX.
public protocol InteractionDeleteManager {
    typealias SideEffects = InteractionDelete.SideEffects

    /// Remove the given interactions.
    func delete(
        interactions: [TSInteraction],
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    )

    /// Deletes the given call records and their associated interactions.
    func delete(
        alongsideAssociatedCallRecords callRecords: [CallRecord],
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    )
}

public extension InteractionDeleteManager {
    /// Remove the given interaction.
    func delete(
        _ interaction: TSInteraction,
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    ) {
        delete(interactions: [interaction], sideEffects: sideEffects, tx: tx)
    }
}

final class InteractionDeleteManagerImpl: InteractionDeleteManager {
    private let callRecordStore: CallRecordStore
    private let callRecordDeleteManager: CallRecordDeleteManager
    private let databaseStorage: SDSDatabaseStorage
    private let deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager
    private let interactionReadCache: InteractionReadCache
    private let interactionStore: InteractionStore
    private let messageSendLog: MessageSendLog
    private let tsAccountManager: TSAccountManager

    init(
        callRecordStore: CallRecordStore,
        callRecordDeleteManager: CallRecordDeleteManager,
        databaseStorage: SDSDatabaseStorage,
        deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager,
        interactionReadCache: InteractionReadCache,
        interactionStore: InteractionStore,
        messageSendLog: MessageSendLog,
        tsAccountManager: TSAccountManager
    ) {
        self.callRecordStore = callRecordStore
        self.callRecordDeleteManager = callRecordDeleteManager
        self.databaseStorage = databaseStorage
        self.deleteForMeOutgoingSyncMessageManager = deleteForMeOutgoingSyncMessageManager
        self.interactionReadCache = interactionReadCache
        self.interactionStore = interactionStore
        self.messageSendLog = messageSendLog
        self.tsAccountManager = tsAccountManager
    }

    func delete(
        interactions: [TSInteraction],
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    ) {
        for interaction in interactions {
            guard interaction.shouldBeSaved else {
                return
            }

            _deleteInternal(
                interaction: interaction,
                knownAssociatedCallRecord: nil,
                sideEffects: sideEffects,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }

        sendDeleteForMeSyncMessageIfNecessary(
            interactions: interactions,
            sideEffects: sideEffects,
            tx: tx
        )
    }

    func delete(
        alongsideAssociatedCallRecords callRecords: [CallRecord],
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    ) {
        var deletedInteractions = [TSInteraction]()
        for callRecord in callRecords {
            guard
                let associatedInteraction: TSInteraction = interactionStore
                    .fetchAssociatedInteraction(callRecord: callRecord, tx: tx)
            else { continue }

            deletedInteractions.append(associatedInteraction)
            CallRecord.assertDebugIsCallRecordInteraction(associatedInteraction)

            _deleteInternal(
                interaction: associatedInteraction,
                knownAssociatedCallRecord: callRecord,
                sideEffects: sideEffects,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }

        sendDeleteForMeSyncMessageIfNecessary(
            interactions: deletedInteractions,
            sideEffects: sideEffects,
            tx: tx
        )
    }

    private func sendDeleteForMeSyncMessageIfNecessary(
        interactions: [TSInteraction],
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    ) {
        switch sideEffects.deleteForMeSyncMessage {
        case .sendSyncMessage(let interactionsThread):
            owsPrecondition(
                interactions.allSatisfy { $0.uniqueThreadId == interactionsThread.uniqueId },
                "Thread did not match interaction!"
            )

            if let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) {
                deleteForMeOutgoingSyncMessageManager.send(
                    deletedMessages: interactions.compactMap { $0 as? TSMessage },
                    thread: interactionsThread,
                    localIdentifiers: localIdentifiers,
                    tx: tx
                )
            }
        case .doNotSend:
            break
        }
    }

    // MARK: -

    private func _deleteInternal(
        interaction: TSInteraction,
        knownAssociatedCallRecord: CallRecord?,
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    ) {
        willRemove(
            interaction: interaction,
            knownAssociatedCallRecord: knownAssociatedCallRecord,
            sideEffects: sideEffects,
            tx: tx
        )

        tx.database.executeAndCacheStatementHandlingErrors(
            sql: "DELETE FROM model_TSInteraction WHERE uniqueId = ?",
            arguments: [interaction.uniqueId]
        )

        didRemove(
            interaction: interaction,
            sideEffects: sideEffects,
            tx: tx
        )
    }

    private func willRemove(
        interaction: TSInteraction,
        knownAssociatedCallRecord: CallRecord?,
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    ) {
        databaseStorage.updateIdMapping(interaction: interaction, transaction: tx)

        if
            let callInteraction = interaction as? CallRecordAssociatedInteraction,
            let interactionRowId = callInteraction.sqliteRowId,
            let associatedCallRecord = knownAssociatedCallRecord ?? callRecordStore.fetch(
                interactionRowId: interactionRowId, tx: tx
            )
        {
            let sendSyncMessage = switch sideEffects.associatedCallDelete {
            case .localDeleteOnly: false
            case .localDeleteAndSendCallEventSyncMessage: true
            }

            callRecordDeleteManager.deleteCallRecords(
                [associatedCallRecord],
                sendSyncMessageOnDelete: sendSyncMessage,
                tx: tx
            )
        }

        if let message = interaction as? TSMessage {
            // Ensure any associated edits are removed before removing.
            message.removeEdits(transaction: tx)
        }
    }

    private func didRemove(
        interaction: TSInteraction,
        sideEffects: SideEffects,
        tx: DBWriteTransaction
    ) {
        switch sideEffects.updateThreadOnInteractionDelete {
        case .updateOnEachDeletedInteraction:
            if let associatedThread = interaction.thread(tx: tx) {
                associatedThread.updateWithRemovedInteraction(interaction, tx: tx)
            }
        case .doNotUpdate:
            break
        }

        messageSendLog.deleteAllPayloadsForInteraction(interaction, tx: tx)
        interactionReadCache.didRemove(interaction: interaction, transaction: tx)

        if let message = interaction as? TSMessage {
            do {
                try FullTextSearchIndexer.delete(message, tx: tx)
            } catch {
                owsFailBeta("Error: \(error)")
            }

            message.removeAllAttachments(tx: tx)
            message.removeAllReactions(transaction: tx)
            message.removeAllMentions(transaction: tx)
            message.touchStoryMessageIfNecessary(replyCountIncrement: .replyDeleted, transaction: tx)
        }
    }
}

// MARK: - Mock

#if TESTABLE_BUILD

open class MockInteractionDeleteManager: InteractionDeleteManager {
    var deleteInteractionsMock: ((
        _ interactions: [TSInteraction],
        _ sideEffects: SideEffects
    ) -> Void)?
    open func delete(interactions: [TSInteraction], sideEffects: SideEffects, tx: DBWriteTransaction) {
        deleteInteractionsMock!(interactions, sideEffects)
    }

    var deleteAlongsideCallRecordsMock: ((
        _ callRecords: [CallRecord],
        _ sideEffects: SideEffects
    ) -> Void)?
    open func delete(alongsideAssociatedCallRecords callRecords: [CallRecord], sideEffects: SideEffects, tx: DBWriteTransaction) {
        deleteAlongsideCallRecordsMock!(callRecords, sideEffects)
    }
}

#endif
