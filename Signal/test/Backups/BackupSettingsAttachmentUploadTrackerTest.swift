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
        let uploadProgress = BackupAttachmentUploadProgress(db: db)
        let uploadQueueStatusManager = MockQueueStatusManager()
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentQueueStatusManager: uploadQueueStatusManager,
            backupAttachmentUploadProgress: uploadProgress
        )

        let uploadRecords: [QueuedBackupAttachmentUpload] = db.write { tx in
            [
                insertUploadRecord(bytes: 100, tx: tx),
                insertUploadRecord(bytes: 300, tx: tx),
            ]
        }

        // Simulate launching with uploads queued.
        uploadQueueStatusManager.currentStatusMock = .running

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: (.running, 0), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[0])
            }),
            ExpectedUpdate(update: (.running, 0.25), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[1])
            }),
            ExpectedUpdate(update: (.running, 1), nextSteps: {
                uploadQueueStatusManager.currentStatusMock = .empty
            }),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]

        await runTest(uploadTracker: uploadTracker, expectedUpdates: expectedUpdates)
    }

    /// Simulates "enabling paid-tier Backups" by starting with an empty queue
    /// that begins running.
    @Test
    func testQueueStartsEmptyThenStartsRunning() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgress(db: db)
        let uploadQueueStatusManager = MockQueueStatusManager()
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentQueueStatusManager: uploadQueueStatusManager,
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
                uploadQueueStatusManager.currentStatusMock = .running
            }),
            ExpectedUpdate(update: (.running, 0), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[0])
            }),
            ExpectedUpdate(update: (.running, 0.25), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[1])
            }),
            ExpectedUpdate(update: (.running, 1), nextSteps: {
                uploadQueueStatusManager.currentStatusMock = .empty
            }),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]

        await runTest(uploadTracker: uploadTracker, expectedUpdates: expectedUpdates)
    }

    /// Simulates uploads running, and a caller tracking (e.g., BackupSettings
    /// being presented), then stopping (e.g., dismissing), then starting again.
    @Test
    func testTrackingStoppingAndReTracking() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgress(db: db)
        let uploadQueueStatusManager = MockQueueStatusManager()
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentQueueStatusManager: uploadQueueStatusManager,
            backupAttachmentUploadProgress: uploadProgress
        )

        let uploadRecords: [QueuedBackupAttachmentUpload] = db.write { tx in
            [
                insertUploadRecord(bytes: 100, tx: tx),
            ]
        }

        let firstExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: nil, nextSteps: {
                uploadQueueStatusManager.currentStatusMock = .running
            }),
            ExpectedUpdate(update: (.running, 0), nextSteps: {}),
        ]
        await runTest(uploadTracker: uploadTracker, expectedUpdates: firstExpectedUpdates)

        let secondExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(update: (.running, 0), nextSteps: {
                await uploadProgress.didFinishUploadOfAttachment(uploadRecord: uploadRecords[0])
            }),
            ExpectedUpdate(update: (.running, 1), nextSteps: {
                uploadQueueStatusManager.currentStatusMock = .empty
            }),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]
        await runTest(uploadTracker: uploadTracker, expectedUpdates: secondExpectedUpdates)
    }

    @Test
    func testTrackingStopsWhenStreamCancelled() async {
        let db = InMemoryDB()
        let uploadProgress = BackupAttachmentUploadProgress(db: db)
        let uploadQueueStatusManager = MockQueueStatusManager()
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentQueueStatusManager: uploadQueueStatusManager,
            backupAttachmentUploadProgress: uploadProgress
        )

        await confirmation { confirmation in
            let trackingTask = Task {
                for await _ in await uploadTracker.start() {}
                confirmation.confirm()
            }

            trackingTask.cancel()
            await trackingTask.value
        }
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
        uploadTracker: BackupSettingsAttachmentUploadTracker,
        expectedUpdates: [ExpectedUpdate]
    ) async {
        var expectedUpdates = expectedUpdates

        for await trackedUploadUpdate in await uploadTracker.start() {
            let nextExpectedUpdate = expectedUpdates.popFirst()!

            #expect(trackedUploadUpdate?.state == nextExpectedUpdate.update?.state)
            #expect(trackedUploadUpdate?.percentageUploaded == nextExpectedUpdate.update?.percentage)

            await nextExpectedUpdate.nextSteps()

            if expectedUpdates.isEmpty {
                await uploadTracker.stop()
            }
        }

        #expect(expectedUpdates.isEmpty)
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

private class MockQueueStatusManager: BackupAttachmentQueueStatusManager {
    var currentStatusMock: BackupAttachmentQueueStatus = .empty {
        didSet { notifyStatusDidChange(type: .upload) }
    }

    func currentStatus(type: BackupAttachmentQueueType) -> BackupAttachmentQueueStatus {
        owsPrecondition(type == .upload)
        return currentStatusMock
    }

    func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64 { owsFail("") }
    func reattemptDiskSpaceChecks() { owsFail("") }
}
