//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import Signal
@testable import SignalServiceKit

@MainActor
@Suite(.serialized)
final class BackupAttachmentUploadTrackerTest: BackupAttachmentTrackerTest<
    BackupAttachmentUploadTracker.UploadUpdate,
> {
    typealias UploadUpdate = BackupAttachmentUploadTracker.UploadUpdate

    /// Simulates "launching with uploads enqueued from a previous launch".
    @Test
    func testLaunchingWithQueuePopulated() async {
        let uploadProgress = BackupAttachmentUploadProgressMock(
            initialCompleted: 0,
            total: 4,
        )
        let uploadQueueStatusManager = MockUploadQueueStatusManager(.running)
        let uploadTracker = BackupAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusManager: uploadQueueStatusManager,
            backupAttachmentUploadProgress: uploadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 0, total: 4),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 1, total: 4),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 4, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 4, total: 4),
                nextSteps: {
                    await uploadQueueStatusManager.setCurrentStatusMock(.empty)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.noUploadsToReport, uploaded: 4, total: 4),
                nextSteps: {},
            ),
        ]

        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates uploads running, and a caller tracking (e.g., BackupSettings
    /// being presented), then stopping (e.g., dismissing), then starting again.
    @Test
    func testTrackingStoppingAndReTracking() async {
        let uploadProgress = BackupAttachmentUploadProgressMock(
            initialCompleted: 0,
            total: 4,
        )
        let uploadQueueStatusManager = MockUploadQueueStatusManager(.running)
        let uploadTracker = BackupAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusManager: uploadQueueStatusManager,
            backupAttachmentUploadProgress: uploadProgress,
        )

        let firstExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 0, total: 4),
                nextSteps: {},
            ),
        ]
        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: firstExpectedUpdates)

        let secondExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 0, total: 4),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 4, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 4, total: 4),
                nextSteps: {
                    await uploadQueueStatusManager.setCurrentStatusMock(.empty)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.noUploadsToReport, uploaded: 4, total: 4),
                nextSteps: {},
            ),
        ]
        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: secondExpectedUpdates)
    }

    @Test
    func testTrackingMultipleStreamInstances() async {
        let uploadProgress = BackupAttachmentUploadProgressMock(
            initialCompleted: 0,
            total: 1,
        )
        let uploadQueueStatusManager = MockUploadQueueStatusManager(.running)
        let uploadTracker = BackupAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusManager: uploadQueueStatusManager,
            backupAttachmentUploadProgress: uploadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 0, total: 1),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 1)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.uploading, uploaded: 1, total: 1),
                nextSteps: {
                    await uploadQueueStatusManager.setCurrentStatusMock(.empty)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.noUploadsToReport, uploaded: 1, total: 1),
                nextSteps: {},
            ),
        ]

        await runTest(
            updateStreams: [uploadTracker.updates(), uploadTracker.updates()],
            expectedUpdates: expectedUpdates,
        )
    }

    @Test
    func testTrackingIgnoresZeroBytesToUpload() async {
        let uploadProgress = BackupAttachmentUploadProgressMock(
            initialCompleted: 0,
            total: 0,
        )
        let uploadQueueStatusManager = MockUploadQueueStatusManager(.running)
        let uploadTracker = BackupAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusManager: uploadQueueStatusManager,
            backupAttachmentUploadProgress: uploadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.noUploadsToReport, uploaded: 0, total: 0),
                nextSteps: {},
            ),
        ]

        await runTest(
            updateStreams: [uploadTracker.updates()],
            expectedUpdates: expectedUpdates,
        )
    }
}

// MARK: -

private extension BackupAttachmentUploadTracker.UploadUpdate {
    init(_ state: State, uploaded: UInt64, total: UInt64) {
        self.init(state: state, bytesUploaded: uploaded, totalBytesToUpload: total)
    }
}

// MARK: -

private class MockUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager {
    private var _currentStatusMock: BackupAttachmentUploadQueueStatus
    func setCurrentStatusMock(_ currentMock: BackupAttachmentUploadQueueStatus) {
        _currentStatusMock = currentMock
        NotificationCenter.default.postOnMainThread(
            name: .backupAttachmentUploadQueueStatusDidChange(for: .fullsize),
            object: nil,
        )
    }

    init(_ initialStatus: BackupAttachmentUploadQueueStatus) {
        self._currentStatusMock = initialStatus
    }

    func currentStatus(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus {
        return _currentStatusMock
    }

    func beginObservingIfNecessary(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus {
        return _currentStatusMock
    }

    func didEmptyQueue(for mode: BackupAttachmentUploadQueueMode) {
        // Nothing
    }

    func setIsMainAppAndActiveOverride(_ newValue: Bool) {
        // Nothing
    }
}
