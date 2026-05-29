//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit
@testable import SignalUI

final class ThreadUtilSignalUITest: SignalBaseTest {

    private var thread: TSContactThread!

    @MainActor
    override func setUp() {
        super.setUp()

        ThreadUtil.enqueueSendQueue = SerialTaskQueue()
        ThreadUtil.sendFinalizationQueue = SerialTaskQueue()

        write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl)
                .registerForTests(localIdentifiers: .forUnitTests, tx: tx)
            SSKPreferences.setAreIntentDonationsEnabled(false, transaction: tx)

            self.thread = TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(Aci.randomForTesting()),
                transaction: tx,
            )
        }
    }

    @MainActor
    override func tearDown() {
        ThreadUtil.enqueueSendQueue = SerialTaskQueue()
        ThreadUtil.sendFinalizationQueue = SerialTaskQueue()

        super.tearDown()
    }

    func testPendingLinkPreviewDoesNotBlockOutgoingRowPersistence() async throws {
        let previewContinuation = AtomicValue<CheckedContinuation<OWSLinkPreviewDraft?, Never>?>(nil, lock: .init())
        let previewTask = Task<OWSLinkPreviewDraft?, Never> {
            await withCheckedContinuation { continuation in
                previewContinuation.set(continuation)
            }
        }
        let previewTaskIsWaiting = await waitUntil { previewContinuation.get() != nil }
        XCTAssertTrue(previewTaskIsWaiting)

        let firstMessageDidPersist = AtomicValue(false, lock: .init())
        ThreadUtil.enqueueMessage(
            body: MessageBody(text: "https://signal.org", ranges: .empty),
            thread: thread,
            linkPreviewDraftForSending: previewTask,
            persistenceCompletionHandler: { firstMessageDidPersist.set(true) },
        )

        let firstMessagePersisted = await waitUntil(firstMessageDidPersist.get)
        XCTAssertTrue(
            firstMessagePersisted,
            "The outgoing row should be visible before the pending preview resolves.",
        )
        if !firstMessagePersisted {
            return
        }

        var outgoingMessages = self.outgoingMessages()
        XCTAssertEqual(outgoingMessages.count, 1)
        XCTAssertNil(outgoingMessages.first?.linkPreview)

        let secondMessageDidPersist = AtomicValue(false, lock: .init())
        ThreadUtil.enqueueMessage(
            body: MessageBody(text: "second message", ranges: .empty),
            thread: thread,
            persistenceCompletionHandler: { secondMessageDidPersist.set(true) },
        )

        let secondMessagePersisted = await waitUntil(secondMessageDidPersist.get)
        XCTAssertTrue(
            secondMessagePersisted,
            "A pending preview finalization should not block later outgoing rows from appearing.",
        )
        if !secondMessagePersisted {
            return
        }
        outgoingMessages = self.outgoingMessages()
        XCTAssertEqual(outgoingMessages.count, 2)
        XCTAssertFalse(
            self.messageSenderJobMessageIds().contains(outgoingMessages[0].uniqueId),
            "The pending-preview message should hold an in-memory ordering barrier until finalization, not a runnable durable sender job.",
        )

        previewContinuation.swap(nil)?.resume(returning: OWSLinkPreviewDraft(
            url: try XCTUnwrap(URL(string: "https://signal.org")),
            title: "Signal",
            isForwarded: false,
        ))

        try await ThreadUtil.enqueueSendQueue.enqueue(operation: {}).value
        try await ThreadUtil.sendFinalizationQueue.enqueue(operation: {}).value

        outgoingMessages = self.outgoingMessages()
        XCTAssertEqual(outgoingMessages.count, 2)
        XCTAssertEqual(outgoingMessages.first?.linkPreview?.urlString, "https://signal.org")
        XCTAssertEqual(outgoingMessages.first?.linkPreview?.title, "Signal")
    }

    private func outgoingMessages() -> [TSOutgoingMessage] {
        read { tx in
            try! InteractionFinder(threadUniqueId: thread.uniqueId)
                .fetchAllInteractions(rowIdFilter: .newest, limit: Int.max, tx: tx)
                .compactMap { $0 as? TSOutgoingMessage }
                .sorted { $0.timestamp < $1.timestamp }
        }
    }

    private func messageSenderJobMessageIds() -> [String] {
        read { tx in
            MessageSenderJobRecord.anyFetchAll(transaction: tx)
                .sorted { ($0.id ?? 0) < ($1.id ?? 0) }
                .compactMap { jobRecord -> String? in
                    guard case .persisted(let messageId, _) = jobRecord.messageType else {
                        return nil
                    }
                    return messageId
                }
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping () -> Bool,
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10 * NSEC_PER_MSEC)
        }

        return predicate()
    }
}
