//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ThreadMergerTest: XCTestCase {
    private var chatColorSettingStore: ChatColorSettingStore!
    private var db: MockDB!
    private var disappearingMessagesConfigurationManager: MockDisappearingMessagesConfigurationManager!
    private var disappearingMessagesConfigurationStore: MockDisappearingMessagesConfigurationStore!
    private var pinnedThreadManager: MockPinnedThreadManager!
    private var threadAssociatedDataManager: MockThreadAssociatedDataManager!
    private var threadAssociatedDataStore: MockThreadAssociatedDataStore!
    private var threadStore: MockThreadStore!
    private var threadRemover: ThreadRemover!
    private var threadReplyInfoStore: ThreadReplyInfoStore!
    private var threadMerger: ThreadMerger!
    private var wallpaperStore: WallpaperStore!

    private var _signalServiceAddressCache: SignalServiceAddressCache!

    private let serviceId = FutureAci.constantForTesting("00000000-0000-4000-8000-000000000000")
    private let phoneNumber = E164("+16505550100")!

    private var serviceIdThread: TSContactThread!
    private var phoneNumberThread: TSContactThread!

    override func setUp() {
        let keyValueStoreFactory = InMemoryKeyValueStoreFactory()

        _signalServiceAddressCache = SignalServiceAddressCache()

        chatColorSettingStore = ChatColorSettingStore(keyValueStoreFactory: keyValueStoreFactory)
        db = MockDB()
        disappearingMessagesConfigurationStore = MockDisappearingMessagesConfigurationStore()
        disappearingMessagesConfigurationManager = MockDisappearingMessagesConfigurationManager(disappearingMessagesConfigurationStore)
        pinnedThreadManager = MockPinnedThreadManager()
        threadAssociatedDataStore = MockThreadAssociatedDataStore()
        threadAssociatedDataManager = MockThreadAssociatedDataManager(threadAssociatedDataStore)
        threadReplyInfoStore = ThreadReplyInfoStore(keyValueStoreFactory: keyValueStoreFactory)
        threadStore = MockThreadStore()
        wallpaperStore = WallpaperStore(keyValueStoreFactory: keyValueStoreFactory, notificationScheduler: SyncScheduler())
        threadRemover = ThreadRemoverImpl(
            chatColorSettingStore: chatColorSettingStore,
            databaseStorage: MockDatabaseStorage(),
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            fullTextSearchFinder: MockFullTextSearchFinder(),
            interactionRemover: MockInteractionRemover(),
            sdsThreadRemover: MockSDSThreadRemover(),
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadReadCache: MockThreadReadCache(),
            threadReplyInfoStore: threadReplyInfoStore,
            threadStore: threadStore,
            wallpaperStore: wallpaperStore
        )
        threadMerger = ThreadMerger(
            chatColorSettingStore: chatColorSettingStore,
            disappearingMessagesConfigurationManager: disappearingMessagesConfigurationManager,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            pinnedThreadManager: pinnedThreadManager,
            sdsThreadMerger: MockSDSThreadMerger(),
            threadAssociatedDataManager: threadAssociatedDataManager,
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadRemover: threadRemover,
            threadReplyInfoStore: threadReplyInfoStore,
            threadStore: threadStore,
            wallpaperStore: wallpaperStore
        )

        serviceIdThread = makeThread(serviceId: serviceId, phoneNumber: nil)
        phoneNumberThread = makeThread(serviceId: nil, phoneNumber: phoneNumber)
    }

    // MARK: - Pinned Threads

    private class MockPinnedThreadManager: _ThreadMerger_PinnedThreadManagerShim {
        var pinnedThreadIds = [String]()
        func fetchPinnedThreadIds(tx: DBReadTransaction) -> [String] { pinnedThreadIds }
        func setPinnedThreadIds(_ pinnedThreadIds: [String], tx: DBWriteTransaction) { self.pinnedThreadIds = pinnedThreadIds }
    }

    func testPinnedThreadsNeither() {
        let otherPinnedThreadId = "00000000-0000-4000-8000-000000000ABC"
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        pinnedThreadManager.pinnedThreadIds = [otherPinnedThreadId]
        performDefaultMerge()
        XCTAssertEqual(pinnedThreadManager.pinnedThreadIds, [otherPinnedThreadId])
    }

    func testPinnedThreadsJustServiceId() {
        let otherPinnedThreadId = "00000000-0000-4000-8000-000000000ABC"
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        pinnedThreadManager.pinnedThreadIds = [otherPinnedThreadId, serviceIdThread.uniqueId]
        performDefaultMerge()
        XCTAssertEqual(pinnedThreadManager.pinnedThreadIds, [otherPinnedThreadId, serviceIdThread.uniqueId])
    }

    func testPinnedThreadsJustPhoneNumber() {
        let otherPinnedThreadId = "00000000-0000-4000-8000-000000000ABC"
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        pinnedThreadManager.pinnedThreadIds = [phoneNumberThread.uniqueId, otherPinnedThreadId]
        performDefaultMerge()
        XCTAssertEqual(pinnedThreadManager.pinnedThreadIds, [serviceIdThread.uniqueId, otherPinnedThreadId])
    }

    func testPinnedThreadsBoth() {
        let otherPinnedThreadId = "00000000-0000-4000-8000-000000000ABC"
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        pinnedThreadManager.pinnedThreadIds = [phoneNumberThread.uniqueId, serviceIdThread.uniqueId, otherPinnedThreadId]
        performDefaultMerge()
        XCTAssertEqual(pinnedThreadManager.pinnedThreadIds, [serviceIdThread.uniqueId, otherPinnedThreadId])
    }

    // MARK: - Disappearing Messages

    private class MockDisappearingMessagesConfigurationManager: _ThreadMerger_DisappearingMessagesConfigurationManagerShim {
        private let store: MockDisappearingMessagesConfigurationStore
        init(_ disappearingMessagesConfigurationStore: MockDisappearingMessagesConfigurationStore) {
            self.store = disappearingMessagesConfigurationStore
        }
        func setToken(_ token: DisappearingMessageToken, for thread: TSContactThread, tx: DBWriteTransaction) {
            self.store.set(token: token, for: .thread(thread), tx: tx)
        }
    }

    private func setDisappearingMessageIntervals(serviceIdValue: UInt32?, phoneNumberValue: UInt32?) {
        disappearingMessagesConfigurationStore.values = [
            serviceIdThread.uniqueId: OWSDisappearingMessagesConfiguration(
                threadId: serviceIdThread.uniqueId,
                enabled: serviceIdValue != nil,
                durationSeconds: serviceIdValue ?? 0
            ),
            phoneNumberThread.uniqueId: OWSDisappearingMessagesConfiguration(
                threadId: phoneNumberThread.uniqueId,
                enabled: phoneNumberValue != nil,
                durationSeconds: phoneNumberValue ?? 0
            )
        ]
    }

    private func getDisappearingMessageIntervals() -> [String: UInt32?] {
        disappearingMessagesConfigurationStore.values.mapValues { $0.isEnabled ? $0.durationSeconds : nil }
    }

    func testDisappearingMessagesNeither() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setDisappearingMessageIntervals(serviceIdValue: nil, phoneNumberValue: nil)
        performDefaultMerge()
        XCTAssertEqual(getDisappearingMessageIntervals(), [serviceIdThread.uniqueId: nil])
    }

    func testDisappearingMessagesJustServiceId() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setDisappearingMessageIntervals(serviceIdValue: 5, phoneNumberValue: nil)
        performDefaultMerge()
        XCTAssertEqual(getDisappearingMessageIntervals(), [serviceIdThread.uniqueId: 5])
    }

    func testDisappearingMessagesJustPhoneNumber() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setDisappearingMessageIntervals(serviceIdValue: nil, phoneNumberValue: 5)
        performDefaultMerge()
        XCTAssertEqual(getDisappearingMessageIntervals(), [serviceIdThread.uniqueId: 5])
    }

    func testDisappearingMessagesBothShorterPhoneNumber() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setDisappearingMessageIntervals(serviceIdValue: 5, phoneNumberValue: 3)
        performDefaultMerge()
        XCTAssertEqual(getDisappearingMessageIntervals(), [serviceIdThread.uniqueId: 3])
    }

    func testDisappearingMessagesBothShorterServiceId() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setDisappearingMessageIntervals(serviceIdValue: 2, phoneNumberValue: 3)
        performDefaultMerge()
        XCTAssertEqual(getDisappearingMessageIntervals(), [serviceIdThread.uniqueId: 2])
    }

    // MARK: - Thread Associated Data

    private class MockThreadAssociatedDataManager: _ThreadMerger_ThreadAssociatedDataManagerShim {
        private let store: MockThreadAssociatedDataStore
        init(_ threadAssociatedDataStore: MockThreadAssociatedDataStore) {
            self.store = threadAssociatedDataStore
        }
        func updateValue(
            _ threadAssociatedData: ThreadAssociatedData,
            isArchived: Bool?,
            isMarkedUnread: Bool?,
            mutedUntilTimestamp: UInt64?,
            audioPlaybackRate: Float?,
            updateStorageService: Bool,
            tx: DBWriteTransaction
        ) {
            self.store.values[threadAssociatedData.threadUniqueId] = ThreadAssociatedData(
                threadUniqueId: threadAssociatedData.threadUniqueId,
                isArchived: isArchived ?? threadAssociatedData.isArchived,
                isMarkedUnread: isMarkedUnread ?? threadAssociatedData.isMarkedUnread,
                mutedUntilTimestamp: mutedUntilTimestamp ?? threadAssociatedData.mutedUntilTimestamp,
                audioPlaybackRate: audioPlaybackRate ?? threadAssociatedData.audioPlaybackRate
            )
        }
    }

    private func setThreadAssociatedData(for thread: TSContactThread, isArchived: Bool, isMarkedUnread: Bool, mutedUntilTimestamp: UInt64, audioPlaybackRate: Float) {
        threadAssociatedDataStore.values[thread.uniqueId] = ThreadAssociatedData(
            threadUniqueId: thread.uniqueId,
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp,
            audioPlaybackRate: audioPlaybackRate
        )
    }

    private func getThreadAssociatedDatas() -> [String: String] {
        threadAssociatedDataStore.values.mapValues {
            "\($0.isArchived)-\($0.isMarkedUnread)-\($0.mutedUntilTimestamp)-\($0.audioPlaybackRate)"
        }
    }

    func testThreadAssociatedDataNeither() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        performDefaultMerge()
        XCTAssertEqual(getThreadAssociatedDatas(), [serviceIdThread.uniqueId: "false-false-0-1.0"])
    }

    func testThreadAssociatedDataJustServiceId() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setThreadAssociatedData(for: serviceIdThread, isArchived: true, isMarkedUnread: false, mutedUntilTimestamp: 1, audioPlaybackRate: 2)
        performDefaultMerge()
        XCTAssertEqual(getThreadAssociatedDatas(), [serviceIdThread.uniqueId: "false-false-1-2.0"])
    }

    func testThreadAssociatedDataJustPhoneNumber() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setThreadAssociatedData(for: phoneNumberThread, isArchived: false, isMarkedUnread: true, mutedUntilTimestamp: 2, audioPlaybackRate: 3)
        performDefaultMerge()
        XCTAssertEqual(getThreadAssociatedDatas(), [serviceIdThread.uniqueId: "false-true-2-3.0"])
    }

    func testThreadAssociatedDataBoth() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        setThreadAssociatedData(for: serviceIdThread, isArchived: true, isMarkedUnread: false, mutedUntilTimestamp: 4, audioPlaybackRate: 1)
        setThreadAssociatedData(for: phoneNumberThread, isArchived: true, isMarkedUnread: false, mutedUntilTimestamp: 5, audioPlaybackRate: 0.5)
        performDefaultMerge()
        XCTAssertEqual(getThreadAssociatedDatas(), [serviceIdThread.uniqueId: "true-false-5-0.5"])
    }

    // MARK: - Thread Reply Info

    func testThreadReplyInfoNeither() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        performDefaultMerge()
        db.read { tx in
            XCTAssertNil(threadReplyInfoStore.fetch(for: serviceIdThread.uniqueId, tx: tx))
            XCTAssertNil(threadReplyInfoStore.fetch(for: phoneNumberThread.uniqueId, tx: tx))
        }
    }

    func testThreadReplyInfoJustPhoneNumber() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        db.write { tx in
            threadReplyInfoStore.save(ThreadReplyInfo(timestamp: 2, author: serviceId), for: phoneNumberThread.uniqueId, tx: tx)
        }
        performDefaultMerge()
        db.read { tx in
            XCTAssertEqual(threadReplyInfoStore.fetch(for: serviceIdThread.uniqueId, tx: tx)?.timestamp, 2)
            XCTAssertNil(threadReplyInfoStore.fetch(for: phoneNumberThread.uniqueId, tx: tx))
        }
    }

    func testThreadReplyInfoBoth() {
        threadStore.threads = [serviceIdThread, phoneNumberThread]
        db.write { tx in
            threadReplyInfoStore.save(ThreadReplyInfo(timestamp: 3, author: serviceId), for: serviceIdThread.uniqueId, tx: tx)
            threadReplyInfoStore.save(ThreadReplyInfo(timestamp: 4, author: serviceId), for: phoneNumberThread.uniqueId, tx: tx)
        }
        performDefaultMerge()
        db.read { tx in
            XCTAssertEqual(threadReplyInfoStore.fetch(for: serviceIdThread.uniqueId, tx: tx)?.timestamp, 3)
            XCTAssertNil(threadReplyInfoStore.fetch(for: phoneNumberThread.uniqueId, tx: tx))
        }
    }

    // MARK: - Raw SDS Migrations

    class MockSDSThreadRemover: ThreadRemoverImpl.Shims.SDSThreadRemover {
        func didRemove(thread: TSThread, tx: DBWriteTransaction) {}
    }

    class MockSDSThreadMerger: ThreadMerger.Shims.SDSThreadMerger {
        func mergeThread(_ thread: TSContactThread, into targetThread: TSContactThread, tx: DBWriteTransaction) {}
    }

    // MARK: - Helpers

    private func performDefaultMerge() {
        db.write { tx in
            threadMerger.didLearnAssociation(
                mergedRecipient: MergedRecipient(
                    serviceId: serviceId,
                    oldPhoneNumber: nil,
                    newPhoneNumber: phoneNumber,
                    isLocalRecipient: false,
                    signalRecipient: SignalRecipient(serviceId: serviceId, phoneNumber: phoneNumber)
                ),
                transaction: tx
            )
        }
    }

    private func makeThread(serviceId: ServiceId?, phoneNumber: E164?) -> TSContactThread {
        let result = TSContactThread(contactAddress: SignalServiceAddress(
            uuid: serviceId?.uuidValue,
            phoneNumber: phoneNumber?.stringValue,
            cache: _signalServiceAddressCache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        ))
        threadAssociatedDataStore.values[result.uniqueId] = ThreadAssociatedData(threadUniqueId: result.uniqueId)
        return result
    }

    // MARK: - Mock Classes

    private class MockInteractionRemover: ThreadRemoverImpl.Shims.InteractionRemover {
        func removeAllInteractions(in thread: TSThread, tx: DBWriteTransaction) {}
    }

    private class MockFullTextSearchFinder: ThreadRemoverImpl.Shims.FullTextSearchFinder {
        func modelWasRemoved(model: SDSIndexableModel, tx: DBWriteTransaction) {}
    }

    private class MockThreadReadCache: ThreadRemoverImpl.Shims.ThreadReadCache {
        func didRemove(thread: TSThread, tx: DBWriteTransaction) {}
    }

    private class MockDatabaseStorage: ThreadRemoverImpl.Shims.DatabaseStorage {
        func updateIdMapping(thread: TSThread, tx: DBWriteTransaction) {}
    }
}
