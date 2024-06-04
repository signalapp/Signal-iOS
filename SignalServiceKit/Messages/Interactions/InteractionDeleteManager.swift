//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum InteractionDelete {
    /// Specifies what should happen with the ``CallRecord`` associated with a
    /// ``TSInteraction`` being deleted, if one exists.
    public enum AssociatedCallDeleteBehavior {
        /// Delete any ``CallRecord`` associated with the interaction, and send
        /// a sync message about that deletion.
        case localDeleteAndSendSyncMessage
        /// Delete any ``CallRecord`` associated with the interaction.
        case localDeleteOnly

        fileprivate var sendSyncMessage: Bool {
            switch self {
            case .localDeleteAndSendSyncMessage: return true
            case .localDeleteOnly: return false
            }
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
    typealias AssociatedCallDeleteBehavior = InteractionDelete.AssociatedCallDeleteBehavior

    /// Remove the given interaction.
    ///
    /// - Parameter associatedCallDeleteBehavior
    /// What behavior this method should adopt when deleting a ``CallRecord``
    /// associated with the given interaction, if one exists.
    func delete(
        _ interaction: TSInteraction,
        associatedCallDeleteBehavior: AssociatedCallDeleteBehavior,
        tx: any DBWriteTransaction
    )

    /// Deletes the given call records and their associated interactions.
    ///
    /// - Parameter associatedCallDeleteBehavior
    /// What behavior this method should adopt when deleting a ``CallRecord``
    /// associated with the given interaction, if one exists.
    func delete(
        alongsideAssociatedCallRecords callRecords: [CallRecord],
        associatedCallDeleteBehavior: AssociatedCallDeleteBehavior,
        tx: any DBWriteTransaction
    )

    /// Remove all interactions.
    func deleteAll(tx: any DBWriteTransaction)
}

public extension InteractionDeleteManager {
    /// Remove the given interaction.
    ///
    /// - Important
    /// The ``CallRecord`` associated with this interaction will be deleted and
    /// a corresponding sync message sent, if one exists.
    ///
    /// - SeeAlso ``delete(_:associatedCallDeleteBehavior:tx:)``.
    func delete(
        _ interaction: TSInteraction,
        tx: any DBWriteTransaction
    ) {
        delete(
            interaction,
            associatedCallDeleteBehavior: .localDeleteAndSendSyncMessage,
            tx: tx
        )
    }
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
        associatedCallDeleteBehavior: AssociatedCallDeleteBehavior,
        tx: any DBWriteTransaction
    ) {
        guard interaction.shouldBeSaved else {
            return
        }

        _deleteInternal(
            interaction: interaction,
            knownAssociatedCallRecord: nil,
            associatedCallDeleteBehavior: associatedCallDeleteBehavior,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }

    func delete(
        alongsideAssociatedCallRecords callRecords: [CallRecord],
        associatedCallDeleteBehavior: AssociatedCallDeleteBehavior,
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
                associatedCallDeleteBehavior: associatedCallDeleteBehavior,
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
                    associatedCallDeleteBehavior: .localDeleteAndSendSyncMessage,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            }
        }
    }

    private func _deleteInternal(
        interaction: TSInteraction,
        knownAssociatedCallRecord: CallRecord?,
        associatedCallDeleteBehavior: AssociatedCallDeleteBehavior,
        tx: SDSAnyWriteTransaction
    ) {
        willRemove(
            interaction: interaction,
            knownAssociatedCallRecord: knownAssociatedCallRecord,
            associatedCallDeleteBehavior: associatedCallDeleteBehavior,
            tx: tx
        )

        tx.unwrapGrdbWrite.executeAndCacheStatement(
            sql: "DELETE FROM model_TSInteraction WHERE uniqueId = ?",
            arguments: [interaction.uniqueId]
        )

        didRemove(interaction: interaction, tx: tx)
    }

    // MARK: -

    private func willRemove(
        interaction: TSInteraction,
        knownAssociatedCallRecord: CallRecord?,
        associatedCallDeleteBehavior: AssociatedCallDeleteBehavior,
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
            callRecordDeleteManager.deleteCallRecord(
                associatedCallRecord,
                sendSyncMessageOnDelete: associatedCallDeleteBehavior.sendSyncMessage,
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

    private func didRemove(interaction: TSInteraction, tx: SDSAnyWriteTransaction) {
        if
            !tx.shouldIgnoreInteractionUpdates(forThreadUniqueId: interaction.uniqueThreadId),
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

// MARK: -

@objc
final class InteractionDeleteManagerObjcBridge: NSObject {
    @objc
    static func remove(_ interaction: TSInteraction, tx: SDSAnyWriteTransaction) {
        // [DeleteForMe] TODO: This is downstream of thread delete, which should go through DeleteForMe sync messages instead of call delete.
        DependenciesBridge.shared.interactionDeleteManager.delete(
            interaction,
            associatedCallDeleteBehavior: .localDeleteAndSendSyncMessage,
            tx: tx.asV2Write
        )
    }
}
