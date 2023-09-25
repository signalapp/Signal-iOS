//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

private struct MergePair<T> {
    let fromValue: T
    let intoValue: T

    func map<Result>(block: (T) throws -> Result) rethrows -> MergePair<Result> {
        return MergePair<Result>(
            fromValue: try block(fromValue),
            intoValue: try block(intoValue)
        )
    }
}

final class ThreadMerger: RecipientMergeObserver {
    private let chatColorSettingStore: ChatColorSettingStore
    private let disappearingMessagesConfigurationManager: Shims.DisappearingMessagesConfigurationManager
    private let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    private let interactionStore: InteractionStore
    private let pinnedThreadManager: Shims.PinnedThreadManager
    private let sdsThreadMerger: Shims.SDSThreadMerger
    private let threadAssociatedDataManager: Shims.ThreadAssociatedDataManager
    private let threadAssociatedDataStore: ThreadAssociatedDataStore
    private let threadRemover: ThreadRemover
    private let threadReplyInfoStore: ThreadReplyInfoStore
    private let threadStore: ThreadStore
    private let wallpaperStore: WallpaperStore

    init(
        chatColorSettingStore: ChatColorSettingStore,
        disappearingMessagesConfigurationManager: Shims.DisappearingMessagesConfigurationManager,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        interactionStore: InteractionStore,
        pinnedThreadManager: Shims.PinnedThreadManager,
        sdsThreadMerger: Shims.SDSThreadMerger,
        threadAssociatedDataManager: Shims.ThreadAssociatedDataManager,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadRemover: ThreadRemover,
        threadReplyInfoStore: ThreadReplyInfoStore,
        threadStore: ThreadStore,
        wallpaperStore: WallpaperStore
    ) {
        self.chatColorSettingStore = chatColorSettingStore
        self.disappearingMessagesConfigurationManager = disappearingMessagesConfigurationManager
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.interactionStore = interactionStore
        self.pinnedThreadManager = pinnedThreadManager
        self.sdsThreadMerger = sdsThreadMerger
        self.threadAssociatedDataManager = threadAssociatedDataManager
        self.threadAssociatedDataStore = threadAssociatedDataStore
        self.threadRemover = threadRemover
        self.threadReplyInfoStore = threadReplyInfoStore
        self.threadStore = threadStore
        self.wallpaperStore = wallpaperStore
    }

    private func mergeThread(_ thread: TSContactThread, into targetThread: TSContactThread, tx: DBWriteTransaction) {
        let threadPair = MergePair<TSContactThread>(fromValue: thread, intoValue: targetThread)
        mergeDisappearingMessagesConfiguration(threadPair, tx: tx)
        mergePinnedThreads(threadPair, tx: tx)
        mergeThreadAssociatedData(threadPair, tx: tx)
        mergeThreadReplyInfo(threadPair, tx: tx)
        mergeChatColors(threadPair, tx: tx)
        mergeWallpaper(threadPair, tx: tx)
        sdsThreadMerger.mergeThread(thread, into: targetThread, tx: tx)
        let shouldInsertEvent = shouldInsertThreadMergeEvent(threadPair)
        targetThread.merge(from: thread)
        threadStore.updateThread(targetThread, tx: tx)
        threadRemover.remove(thread, tx: tx)
        if shouldInsertEvent {
            insertThreadMergeEvent(threadPair, tx: tx)
        }
        // TODO: [optional] Merge `lastVisibleInteractionStore` (we use `targetThread`s right now).
        // TODO: [optional] Merge BroadcastMediaMessageJobRecord (they are canceled right now).
        // TODO: [optional] Merge MessageSenderJobRecord (they are canceled right now).
        // TODO: [optional] Merge SessionResetJobRecord (they are canceled right now).
        // TODO: [optional] Merge SendGiftBadgeJobRecord (they are canceled right now).
    }

    private func mergeThreadAssociatedData(_ threadPair: MergePair<TSContactThread>, tx: DBWriteTransaction) {
        let valuePair = threadPair.map { threadAssociatedDataStore.fetchOrDefault(for: $0.uniqueId, tx: tx) }

        // Create a new object so that the compiler complains if you add a new
        // property but don't update this call site.
        let resolvedValue = ThreadAssociatedData(
            threadUniqueId: valuePair.intoValue.threadUniqueId,

            // If either thread isn't archived, the merged thread shouldn't be
            // archived.
            isArchived: valuePair.fromValue.isArchived && valuePair.intoValue.isArchived,

            // If either thread is marked as unread, the merged thread should be marked
            // as unread.
            isMarkedUnread: valuePair.fromValue.isMarkedUnread || valuePair.intoValue.isMarkedUnread,

            // If either thread is muted, choose the longer mute duration.
            mutedUntilTimestamp: max(valuePair.fromValue.mutedUntilTimestamp, valuePair.intoValue.mutedUntilTimestamp),

            // Prefer audio playback rates that have been changed from the default. If
            // they have both been changed, prefer the one from the thread we're
            // merging into.
            audioPlaybackRate: (
                valuePair.intoValue.audioPlaybackRate != 1
                ? valuePair.intoValue.audioPlaybackRate
                : valuePair.fromValue.audioPlaybackRate
            )
        )

        func newValueIfChanged<T: Equatable>(_ keyPath: KeyPath<ThreadAssociatedData, T>) -> T? {
            let oldValue = valuePair.intoValue[keyPath: keyPath]
            let newValue = resolvedValue[keyPath: keyPath]
            return newValue != oldValue ? newValue : nil
        }

        threadAssociatedDataManager.updateValue(
            valuePair.intoValue,
            isArchived: newValueIfChanged(\.isArchived),
            isMarkedUnread: newValueIfChanged(\.isMarkedUnread),
            mutedUntilTimestamp: newValueIfChanged(\.mutedUntilTimestamp),
            audioPlaybackRate: newValueIfChanged(\.audioPlaybackRate),
            updateStorageService: true,
            tx: tx
        )
    }

    private func mergeDisappearingMessagesConfiguration(_ threadPair: MergePair<TSContactThread>, tx: DBWriteTransaction) {
        let configPair = threadPair.map { disappearingMessagesConfigurationStore.fetchOrBuildDefault(for: .thread($0), tx: tx) }
        let valuePair = configPair.map { $0.isEnabled ? $0.durationSeconds : nil }

        // If any thread has disappearing messages enabled, the merged result
        // should have disappearing messages enabled. If both threads have
        // disappearing messages enabled, pick the shorter value.
        let resolvedValue = [valuePair.fromValue, valuePair.intoValue].compacted().min()

        // If neither thread had disappearing messages enabled, don't change anything.
        guard let resolvedValue else {
            return
        }

        let oldConfig = configPair.intoValue
        let newConfig = oldConfig.copyAsEnabled(withDurationSeconds: resolvedValue)

        if newConfig == oldConfig {
            return
        }

        disappearingMessagesConfigurationManager.setToken(newConfig.asToken, for: threadPair.intoValue, tx: tx)
    }

    private func mergePinnedThreads(_ threadPair: MergePair<TSContactThread>, tx: DBWriteTransaction) {
        var pinnedThreadIds = pinnedThreadManager.fetchPinnedThreadIds(tx: tx)
        let pinnedIndexPair = threadPair.map { pinnedThreadIds.firstIndex(of: $0.uniqueId) }

        // If the old thread was pinned, unpin it.
        if let fromPinnedIndex = pinnedIndexPair.fromValue {
            pinnedThreadIds.remove(at: fromPinnedIndex)

            // If the new thread *wasn't* pinned, pin it.
            if pinnedIndexPair.intoValue == nil {
                pinnedThreadIds.insert(threadPair.intoValue.uniqueId, at: fromPinnedIndex)
            }

            pinnedThreadManager.setPinnedThreadIds(pinnedThreadIds, tx: tx)
        }
    }

    private func mergeThreadReplyInfo(_ threadPair: MergePair<TSContactThread>, tx: DBWriteTransaction) {
        let replyInfoPair = threadPair.map { threadReplyInfoStore.fetch(for: $0.uniqueId, tx: tx) }
        if replyInfoPair.intoValue == nil, let fromValue = replyInfoPair.fromValue {
            threadReplyInfoStore.save(fromValue, for: threadPair.intoValue.uniqueId, tx: tx)
        }
    }

    private func mergeChatColors(_ threadPair: MergePair<TSContactThread>, tx: DBWriteTransaction) {
        let rawValuePair = threadPair.map { chatColorSettingStore.fetchRawSetting(for: $0.uniqueId, tx: tx) }
        if rawValuePair.intoValue == nil, let fromValue = rawValuePair.fromValue {
            chatColorSettingStore.setRawSetting(fromValue, for: threadPair.intoValue.uniqueId, tx: tx)
        }
    }

    private func mergeWallpaper(_ threadPair: MergePair<TSContactThread>, tx: DBWriteTransaction) {
        let settingPair = threadPair.map { wallpaperStore.fetchWallpaper(for: $0.uniqueId, tx: tx) }
        if settingPair.intoValue == nil, let fromSetting = settingPair.fromValue {
            wallpaperStore.setWallpaper(fromSetting, for: threadPair.intoValue.uniqueId, tx: tx)
            if let fromDimInDarkMode = wallpaperStore.fetchDimInDarkMode(for: threadPair.fromValue.uniqueId, tx: tx) {
                wallpaperStore.setDimInDarkMode(fromDimInDarkMode, for: threadPair.intoValue.uniqueId, tx: tx)
            }
            do {
                let photoUrlPair = try threadPair.map { try wallpaperStore.customPhotoUrl(for: $0.uniqueId) }
                try FileManager.default.copyItem(at: photoUrlPair.fromValue, to: photoUrlPair.intoValue)
            } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile, POSIXError.ENOENT {
                // not an error
            } catch {
                owsFailDebug("Couldn't copy custom wallpaper image.")
            }
        }
    }

    private func shouldInsertThreadMergeEvent(_ threadPair: MergePair<TSContactThread>) -> Bool {
        let isVisible = threadPair.map { $0.shouldThreadBeVisible }
        return isVisible.intoValue && isVisible.fromValue
    }

    private func insertThreadMergeEvent(_ threadPair: MergePair<TSContactThread>, tx: DBWriteTransaction) {
        var userInfo = [InfoMessageUserInfoKey: Any]()
        // We want to show the phone number only in the specific, very standardized
        // case where you have a conversation with the phone number/PNI and you
        // merge it into a chat with only the ACI. In all other cases, we show a
        // generic thread merge event.
        if let phoneNumber = threadPair.fromValue.contactPhoneNumber, threadPair.intoValue.contactPhoneNumber == nil {
            userInfo[.threadMergePhoneNumber] = phoneNumber
        }
        let message = TSInfoMessage(thread: threadPair.intoValue, messageType: .threadMerge, infoMessageUserInfo: userInfo)
        message.wasRead = true
        interactionStore.insertInteraction(message, tx: tx)
    }

    private func mergeAllThreads(_ threadsToMerge: [TSContactThread], tx: DBWriteTransaction) {
        // We merge threads in pairs, starting at the end and going back to the
        // beginning. We order the threads in descending priority order, so this
        // approach ensures we merge lower priority threads (ie with just a phone
        // number) into higher priority threads (ie with a stable ACI). If we have
        // threads A, B, and C to merge, we'll merge C into B, and then we'll merge
        // B into A (where B has become a combination of B and C).
        let reversedThreadsToMerge = threadsToMerge.reversed()
        for (threadToMerge, mergeDestination) in zip(reversedThreadsToMerge, reversedThreadsToMerge.dropFirst()) {
            mergeThread(threadToMerge, into: mergeDestination, tx: tx)
        }
    }

    private func mergeThreads(for recipient: SignalRecipient, tx: DBWriteTransaction) {
        // Fetch all the threads related to the new recipient. Because we don't
        // have UNIQUE constraints on the TSThread table, there might be many
        // duplicate threads that we need to merge. We fetch the ACI threads first
        // to ensure we merge *into* one of those threads where possible.

        let serviceId: ServiceId? = recipient.aci ?? recipient.pni
        let threadsToMerge: [TSContactThread] = UniqueRecipientObjectMerger.fetchAndExpunge(
            for: recipient,
            serviceIdField: \.contactUUID,
            phoneNumberField: \.contactPhoneNumber,
            uniqueIdField: \.uniqueId,
            fetchObjectsForServiceId: { threadStore.fetchContactThreads(serviceId: $0, tx: tx) },
            fetchObjectsForPhoneNumber: { threadStore.fetchContactThreads(phoneNumber: $0.stringValue, tx: tx) },
            updateObject: { threadStore.updateThread($0, tx: tx) }
        )

        mergeAllThreads(threadsToMerge, tx: tx)
        if threadsToMerge.count >= 2 {
            Logger.info("Merged \(threadsToMerge.count) threads for \(serviceId?.logString ?? "nil")")
        }

        // After we merge all threads, we're left with just one. Make sure that
        // that thread has the new (ACI/PNI, Phone Number) pair.
        if let finalThread = threadsToMerge.first {
            finalThread.contactUUID = serviceId?.serviceIdUppercaseString
            finalThread.contactPhoneNumber = recipient.phoneNumber
            threadStore.updateThread(finalThread, tx: tx)
        }
    }

    func willBreakAssociation(for recipient: SignalRecipient, tx: DBWriteTransaction) {
        mergeThreads(for: recipient, tx: tx)
    }

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        mergeThreads(for: mergedRecipient.newRecipient, tx: tx)
    }
}

// MARK: - SDS Merges

/// There are a bunch of types that can't be easily mocked out for testing
/// purposes. Until they can be, this serves as a dumping ground for code
/// that's skipped during unit tests.
class _ThreadMerger_SDSThreadMergerWrapper: _ThreadMerger_SDSThreadMergerShim {
    func mergeThread(_ thread: TSContactThread, into targetThread: TSContactThread, tx: DBWriteTransaction) {
        let threadPair = MergePair<TSContactThread>(fromValue: thread, intoValue: targetThread)
        mergeInteractions(threadPair, tx: SDSDB.shimOnlyBridge(tx))
        mergeMediaGalleryItems(threadPair, tx: SDSDB.shimOnlyBridge(tx))
        mergeReceiptsPendingMessageRequest(threadPair, tx: SDSDB.shimOnlyBridge(tx))
        mergeMessageSendLogPayloads(threadPair, tx: SDSDB.shimOnlyBridge(tx))
        // We might have changed something in the cache -- evacuate it.
        NSObject.modelReadCaches.evacuateAllCaches()
    }

    private func mergeInteractions(_ threadPair: MergePair<TSContactThread>, tx: SDSAnyWriteTransaction) {
        let uniqueIds = threadPair.map { $0.uniqueId }
        tx.unwrapGrdbWrite.execute(
            sql: """
                UPDATE "\(InteractionRecord.databaseTableName)"
                SET "\(interactionColumn: .threadUniqueId)" = ?
                WHERE "\(interactionColumn: .threadUniqueId)" = ?
            """,
            arguments: [uniqueIds.intoValue, uniqueIds.fromValue]
        )
    }

    private func mergeMediaGalleryItems(_ threadPair: MergePair<TSContactThread>, tx: SDSAnyWriteTransaction) {
        let threadRowIds = threadPair.map { $0.grdbId!.int64Value }
        tx.unwrapGrdbWrite.execute(
            sql: """
                UPDATE "media_gallery_items" SET "threadId" = ? WHERE "threadId" = ?
            """,
            arguments: [threadRowIds.intoValue, threadRowIds.fromValue]
        )
    }

    private func mergeReceiptsPendingMessageRequest(_ threadPair: MergePair<TSContactThread>, tx: SDSAnyWriteTransaction) {
        let threadRowIds = threadPair.map { $0.grdbId!.int64Value }
        tx.unwrapGrdbWrite.execute(
            sql: """
                UPDATE "\(PendingViewedReceiptRecord.databaseTableName)" SET "threadId" = ? WHERE "threadId" = ?
            """,
            arguments: [threadRowIds.intoValue, threadRowIds.fromValue]
        )
        tx.unwrapGrdbWrite.execute(
            sql: """
                UPDATE "\(PendingReadReceiptRecord.databaseTableName)" SET "threadId" = ? WHERE "threadId" = ?
            """,
            arguments: [threadRowIds.intoValue, threadRowIds.fromValue]
        )
    }

    private func mergeMessageSendLogPayloads(_ threadPair: MergePair<TSContactThread>, tx: SDSAnyWriteTransaction) {
        let threadUniqueIdPair = threadPair.map { $0.uniqueId }
        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        messageSendLog.mergePayloads(from: threadUniqueIdPair.fromValue, into: threadUniqueIdPair.intoValue, tx: tx)
    }
}

// MARK: - Shims

extension ThreadMerger {
    enum Shims {
        typealias DisappearingMessagesConfigurationManager = _ThreadMerger_DisappearingMessagesConfigurationManagerShim
        typealias PinnedThreadManager = _ThreadMerger_PinnedThreadManagerShim
        typealias ThreadAssociatedDataManager = _ThreadMerger_ThreadAssociatedDataManagerShim
        typealias SDSThreadMerger = _ThreadMerger_SDSThreadMergerShim
    }

    enum Wrappers {
        typealias DisappearingMessagesConfigurationManager = _ThreadMerger_DisappearingMessagesConfigurationManagerWrapper
        typealias PinnedThreadManager = _ThreadMerger_PinnedThreadManagerWrapper
        typealias ThreadAssociatedDataManager = _ThreadMerger_ThreadAssociatedDataManagerWrapper
        typealias SDSThreadMerger = _ThreadMerger_SDSThreadMergerWrapper
    }
}

protocol _ThreadMerger_PinnedThreadManagerShim {
    func fetchPinnedThreadIds(tx: DBReadTransaction) -> [String]
    func setPinnedThreadIds(_ pinnedThreadIds: [String], tx: DBWriteTransaction)
}

class _ThreadMerger_PinnedThreadManagerWrapper: _ThreadMerger_PinnedThreadManagerShim {
    func fetchPinnedThreadIds(tx: DBReadTransaction) -> [String] {
        return PinnedThreadManager.pinnedThreadIds
    }

    func setPinnedThreadIds(_ pinnedThreadIds: [String], tx: DBWriteTransaction) {
        PinnedThreadManager.updatePinnedThreadIds(pinnedThreadIds, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

protocol _ThreadMerger_DisappearingMessagesConfigurationManagerShim {
    func setToken(_ token: DisappearingMessageToken, for thread: TSContactThread, tx: DBWriteTransaction)
}

class _ThreadMerger_DisappearingMessagesConfigurationManagerWrapper: _ThreadMerger_DisappearingMessagesConfigurationManagerShim {
    func setToken(_ token: DisappearingMessageToken, for thread: TSContactThread, tx: DBWriteTransaction) {
        GroupManager.localUpdateDisappearingMessageToken(token, inContactThread: thread, tx: SDSDB.shimOnlyBridge(tx))
    }
}

protocol _ThreadMerger_ThreadAssociatedDataManagerShim {
    func updateValue(
        _ threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool?,
        isMarkedUnread: Bool?,
        mutedUntilTimestamp: UInt64?,
        audioPlaybackRate: Float?,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    )
}

class _ThreadMerger_ThreadAssociatedDataManagerWrapper: _ThreadMerger_ThreadAssociatedDataManagerShim {
    func updateValue(
        _ threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool?,
        isMarkedUnread: Bool?,
        mutedUntilTimestamp: UInt64?,
        audioPlaybackRate: Float?,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        guard isArchived != nil || isMarkedUnread != nil || mutedUntilTimestamp != nil || audioPlaybackRate != nil else {
            return
        }
        threadAssociatedData.updateWith(
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp,
            audioPlaybackRate: audioPlaybackRate,
            updateStorageService: updateStorageService,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

protocol _ThreadMerger_SDSThreadMergerShim {
    func mergeThread(_ thread: TSContactThread, into targetThread: TSContactThread, tx: DBWriteTransaction)
}
