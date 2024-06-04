//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum InteractionDelete {
    public struct SideEffects {
        /// Specifies what should happen with the ``CallRecord`` associated with
        /// a ``TSInteraction`` being deleted, if one exists.
        public enum AssociatedCallDeleteBehavior {
            /// Delete any ``CallRecord`` associated with the interaction, and
            /// send a sync message about that deletion.
            case localDeleteAndSendSyncMessage
            /// Delete any ``CallRecord`` associated with the interaction.
            case localDeleteOnly
        }

        let associatedCallDelete: AssociatedCallDeleteBehavior
        let updateThreadOnEachDeletedInteraction: Bool

        private init(
            associatedCallDelete: AssociatedCallDeleteBehavior,
            updateThreadOnEachDeletedInteraction: Bool
        ) {
            self.associatedCallDelete = associatedCallDelete
            self.updateThreadOnEachDeletedInteraction = updateThreadOnEachDeletedInteraction
        }

        public static func `default`() -> SideEffects {
            return .custom()
        }

        public static func custom(
            associatedCallDelete: AssociatedCallDeleteBehavior = .localDeleteAndSendSyncMessage,
            updateThreadOnEachDeletedInteraction: Bool = true
        ) -> SideEffects {
            return SideEffects(
                associatedCallDelete: associatedCallDelete,
                updateThreadOnEachDeletedInteraction: updateThreadOnEachDeletedInteraction
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
public protocol InteractionDeleteManager {
    typealias SideEffects = InteractionDelete.SideEffects

    /// Remove the given interaction.
    func delete(
        _ interaction: TSInteraction,
        sideEffects: SideEffects,
        tx: any DBWriteTransaction
    )

    /// Deletes the given call records and their associated interactions.
    func delete(
        alongsideAssociatedCallRecords callRecords: [CallRecord],
        sideEffects: SideEffects,
        tx: any DBWriteTransaction
    )

    /// Remove all interactions with the default side-effects.
    func deleteAll(tx: any DBWriteTransaction)
}

final class InteractionDeleteManagerImpl: InteractionDeleteManager {
    private let callRecordStore: CallRecordStore
    private let callRecordDeleteManager: CallRecordDeleteManager
    private let databaseStorage: SDSDatabaseStorage
    private let interactionReadCache: InteractionReadCache
    private let interactionStore: InteractionStore
    private let mediaGalleryResourceManager: MediaGalleryResourceManager
    private let messageSendLog: MessageSendLog

    init(
        callRecordStore: CallRecordStore,
        callRecordDeleteManager: CallRecordDeleteManager,
        databaseStorage: SDSDatabaseStorage,
        interactionReadCache: InteractionReadCache,
        interactionStore: InteractionStore,
        mediaGalleryResourceManager: MediaGalleryResourceManager,
        messageSendLog: MessageSendLog
    ) {
        self.callRecordStore = callRecordStore
        self.callRecordDeleteManager = callRecordDeleteManager
        self.databaseStorage = databaseStorage
        self.interactionReadCache = interactionReadCache
        self.interactionStore = interactionStore
        self.mediaGalleryResourceManager = mediaGalleryResourceManager
        self.messageSendLog = messageSendLog
    }

    func delete(
        _ interaction: TSInteraction,
        sideEffects: SideEffects,
        tx: any DBWriteTransaction
    ) {
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

    func delete(
        alongsideAssociatedCallRecords callRecords: [CallRecord],
        sideEffects: SideEffects,
        tx: any DBWriteTransaction
    ) {
        for callRecord in callRecords {
            guard
                let associatedInteraction: TSInteraction = interactionStore
                    .fetchAssociatedInteraction(callRecord: callRecord, tx: tx)
            else { continue }

            CallRecord.assertDebugIsCallRecordInteraction(associatedInteraction)

            _deleteInternal(
                interaction: associatedInteraction,
                knownAssociatedCallRecord: callRecord,
                sideEffects: sideEffects,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    func deleteAll(tx: any DBWriteTransaction) {
        let allUniqueIds = interactionStore.fetchAllUniqueIds(tx: tx)

        for uniqueId in allUniqueIds {
            autoreleasepool {
                guard let interaction = interactionStore.fetchInteraction(
                    uniqueId: uniqueId, tx: tx
                ) else { return }

                _deleteInternal(
                    interaction: interaction,
                    knownAssociatedCallRecord: nil,
                    sideEffects: .default(),
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            }
        }
    }

    // MARK: -

    private func _deleteInternal(
        interaction: TSInteraction,
        knownAssociatedCallRecord: CallRecord?,
        sideEffects: SideEffects,
        tx: SDSAnyWriteTransaction
    ) {
        willRemove(
            interaction: interaction,
            knownAssociatedCallRecord: knownAssociatedCallRecord,
            sideEffects: sideEffects,
            tx: tx
        )

        tx.unwrapGrdbWrite.executeAndCacheStatement(
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
        tx: SDSAnyWriteTransaction
    ) {
        databaseStorage.updateIdMapping(interaction: interaction, transaction: tx)

        if
            let callInteraction = interaction as? CallRecordAssociatedInteraction,
            let interactionRowId = callInteraction.sqliteRowId,
            let associatedCallRecord = knownAssociatedCallRecord ?? callRecordStore.fetch(
                interactionRowId: interactionRowId, tx: tx.asV2Read
            )
        {
            let sendSyncMessage = switch sideEffects.associatedCallDelete {
            case .localDeleteOnly: false
            case .localDeleteAndSendSyncMessage: true
            }

            callRecordDeleteManager.deleteCallRecord(
                associatedCallRecord,
                sendSyncMessageOnDelete: sendSyncMessage,
                tx: tx.asV2Write
            )
        }

        if let message = interaction as? TSMessage {
            // Ensure any associated edits are removed before removing.
            message.removeEdits(transaction: tx)

            if
                let sticker = message.messageSticker,
                interactionStore.exists(uniqueId: message.uniqueId, tx: tx.asV2Write)
            {
                // StickerManager does ref-counting of known sticker packs. If this
                // message is persisted – i.e., if there will in fact be a deletion
                // downstream of this call – we should make sure that refcount gets
                // updated.
                //
                // In a better world we wouldn't be unsure if the message was
                // actually going to be deleted when we call this, but that's a
                // problem for another day.
                StickerManager.removeKnownStickerInfo(sticker.info, transaction: tx)
            }
        }
    }

    private func didRemove(
        interaction: TSInteraction,
        sideEffects: SideEffects,
        tx: SDSAnyWriteTransaction
    ) {
        if
            sideEffects.updateThreadOnEachDeletedInteraction,
            let associatedThread = interaction.thread(tx: tx)
        {
            associatedThread.update(withRemovedMessage: interaction, transaction: tx)
        }

        messageSendLog.deleteAllPayloadsForInteraction(interaction, tx: tx)
        interactionReadCache.didRemove(interaction: interaction, transaction: tx)

        if let message = interaction as? TSMessage {
            FullTextSearchIndexer.delete(message, tx: tx)

            if !message.attachmentIds.isEmpty {
                mediaGalleryResourceManager.didRemove(message: message, tx: tx.asV2Write)
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
    var deleteInteractionMock: ((
        _ interaction: TSInteraction,
        _ sideEffects: SideEffects
    ) -> Void)?
    open func delete(_ interaction: TSInteraction, sideEffects: SideEffects, tx: any DBWriteTransaction) {
        deleteInteractionMock!(interaction, sideEffects)
    }

    var deleteAlongsideCallRecordsMock: ((
        _ callRecords: [CallRecord],
        _ sideEffects: SideEffects
    ) -> Void)?
    open func delete(alongsideAssociatedCallRecords callRecords: [CallRecord], sideEffects: SideEffects, tx: any DBWriteTransaction) {
        deleteAlongsideCallRecordsMock!(callRecords, sideEffects)
    }

    var deleteAllMock: (() -> Void)?
    open func deleteAll(tx: any DBWriteTransaction) {
        deleteAllMock!()
    }
}

#endif
