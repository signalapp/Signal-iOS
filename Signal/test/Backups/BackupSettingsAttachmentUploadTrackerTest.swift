//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import SignalServiceKit
@testable import Signal

@MainActor
@Suite(.serialized)
class BackupSettingsAttachmentUploadTrackerTest {

    /// Simulates "launching with uploads enqueued from a previous launch".
    @Test
    func testLaunchingWithQueuePopulated() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgressImpl(db: db)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.running)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress
        )

        let uploadRecords: [QueuedBackupAttachmentUpload] = db.write { tx in
            [
                insertUploadRecord(bytes: 100, tx: tx),
                insertUploadRecord(bytes: 300, tx: tx),
            ]
        }

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: (.running, 0), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[0])
            }),
            ExpectedUpdate(update: (.running, 0.25), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[1])
            }),
            ExpectedUpdate(update: (.running, 1), nextSteps: {
                uploadQueueStatusReporter.currentStatusMock = .empty
            }),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]

        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates "enabling paid-tier Backups" by starting with an empty queue
    /// that begins running.
    @Test
    func testQueueStartsEmptyThenStartsRunning() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgressImpl(db: db)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.empty)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress
        )

        let uploadRecords: [QueuedBackupAttachmentUpload] = db.write { tx in
            [
                insertUploadRecord(bytes: 100, tx: tx),
                insertUploadRecord(bytes: 300, tx: tx),
            ]
        }

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: nil, nextSteps: {
                uploadQueueStatusReporter.currentStatusMock = .running
            }),
            ExpectedUpdate(update: (.running, 0), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[0])
            }),
            ExpectedUpdate(update: (.running, 0.25), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[1])
            }),
            ExpectedUpdate(update: (.running, 1), nextSteps: {
                uploadQueueStatusReporter.currentStatusMock = .empty
            }),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]

        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates uploads running, and a caller tracking (e.g., BackupSettings
    /// being presented), then stopping (e.g., dismissing), then starting again.
    @Test
    func testTrackingStoppingAndReTracking() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgressImpl(db: db)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.empty)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress
        )

        let uploadRecords: [QueuedBackupAttachmentUpload] = db.write { tx in
            [
                insertUploadRecord(bytes: 100, tx: tx),
            ]
        }

        let firstExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: nil, nextSteps: {
                uploadQueueStatusReporter.currentStatusMock = .running
            }),
            ExpectedUpdate(update: (.running, 0), nextSteps: {}),
        ]
        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: firstExpectedUpdates)

        let secondExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: (.running, 0), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[0])
            }),
            ExpectedUpdate(update: (.running, 1), nextSteps: {
                uploadQueueStatusReporter.currentStatusMock = .empty
            }),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]
        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: secondExpectedUpdates)
    }

    @Test
    func testTrackingStopsWhenStreamCancelled() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgressImpl(db: db)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.empty)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress
        )

        await confirmation { confirmation in
            let trackingTask = Task {
                for await _ in uploadTracker.updates() {}
                confirmation.confirm()
            }

            trackingTask.cancel()
            await trackingTask.value
        }
    }

    @Test
    func testTrackingMultipleStreamInstances() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgressImpl(db: db)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.empty)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress
        )

        let uploadRecords: [QueuedBackupAttachmentUpload] = db.write { tx in
            [
                insertUploadRecord(bytes: 100, tx: tx),
            ]
        }

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: nil, nextSteps: {
                uploadQueueStatusReporter.currentStatusMock = .running
            }),
            ExpectedUpdate(update: (.running, 0), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[0])
            }),
            ExpectedUpdate(update: (.running, 1), nextSteps: {
                uploadQueueStatusReporter.currentStatusMock = .empty
            }),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]

        await runTest(
            updateStreams: [uploadTracker.updates(), uploadTracker.updates()],
            expectedUpdates: expectedUpdates
        )
    }

    // MARK: -

    struct ExpectedUpdate {
        let update: (
            state: BackupSettingsAttachmentUploadTracker.UploadUpdate.State,
            percentage: Float
        )?
        let nextSteps: () async -> Void
    }

    func runTest(
        updateStream: AsyncStream<BackupSettingsAttachmentUploadTracker.UploadUpdate?>,
        expectedUpdates: [ExpectedUpdate]
    ) async {
        await runTest(updateStreams: [updateStream], expectedUpdates: expectedUpdates)
    }

    func runTest(
        updateStreams: [AsyncStream<BackupSettingsAttachmentUploadTracker.UploadUpdate?>],
        expectedUpdates: [ExpectedUpdate]
    ) async {
        let completedExpectedUpdateIndexes: AtomicValue<[UUID: Int]> = AtomicValue(
            [:],
            lock: .init()
        )
        var streamTasks: [Task<Void, Never>] = []

        for updateStream in updateStreams {
            let uuid = UUID()

            completedExpectedUpdateIndexes.update { $0[uuid] = -1 }
            streamTasks.append(Task {
                for await trackedUploadUpdate in updateStream {
                    let nextExpectedUpdateIndex = completedExpectedUpdateIndexes.update {
                        let nextValue = $0[uuid]! + 1
                        $0[uuid] = nextValue
                        return nextValue
                    }
                    let nextExpectedUpdate = expectedUpdates[nextExpectedUpdateIndex]

                    #expect(trackedUploadUpdate?.state == nextExpectedUpdate.update?.state)
                    #expect(trackedUploadUpdate?.percentageUploaded == nextExpectedUpdate.update?.percentage)
                }

                if Task.isCancelled {
                    return
                }

                Issue.record("Finished stream without cancellation!")
            })
        }

        let exhaustedExpectedUpdatesTask = Task {
            var lastCompletedIndex = -1

            while true {
                switch completedExpectedUpdateIndexes.get().values.areAllEqual() {
                case .no:
                    break
                case .yes(let completedIndex) where lastCompletedIndex == completedIndex:
                    break
                case .yes(let completedIndex):
                    if completedIndex == expectedUpdates.count - 1 {
                        streamTasks.forEach { $0.cancel() }
                        return
                    }

                    await expectedUpdates[completedIndex].nextSteps()
                    lastCompletedIndex = completedIndex
                }

                await Task.yield()
            }
        }

        await exhaustedExpectedUpdatesTask.value
        for streamTask in streamTasks {
            await streamTask.value
        }
    }

    // MARK: -

    private var nextRowId: Int64 = 1

    private func insertUploadRecord(bytes: UInt32, tx: DBWriteTransaction) -> QueuedBackupAttachmentUpload {
        defer { nextRowId += 1 }

        try! tx.database.execute(sql: """
            INSERT INTO Attachment (id, mimeType, encryptionKey)
            VALUES (\(nextRowId), 'text/plain', X'aabbccdd')
        """)

        var uploadRecord = QueuedBackupAttachmentUpload(
            attachmentRowId: nextRowId,
            highestPriorityOwnerType: .threadWallpaper,
            isFullsize: false,
            estimatedByteCount: bytes
        )
        try! uploadRecord.insert(tx.database)
        return uploadRecord
    }
}

// MARK: -

private extension Dictionary.Values where Element: Equatable {
    enum AllEqualResult {
        case yes(Element)
        case no
    }

    func areAllEqual() -> AllEqualResult {
        guard let first else { return .no }

        if allSatisfy({ $0 == first }) {
            return .yes(first)
        }

        return .no
    }
}

// MARK: -

private class MockUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter {
    var currentStatusMock: BackupAttachmentUploadQueueStatus {
        didSet { notifyStatusDidChange() }
    }

    init(_ initialStatus: BackupAttachmentUploadQueueStatus) {
        self.currentStatusMock = initialStatus
    }

    func currentStatus() -> BackupAttachmentUploadQueueStatus {
        return currentStatusMock
    }
}
