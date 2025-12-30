//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import Signal
@testable import SignalServiceKit

@MainActor
@Suite(.serialized)
final class BackupSettingsAttachmentUploadTrackerTest: BackupSettingsAttachmentTrackerTest<
    BackupSettingsAttachmentUploadTracker.UploadUpdate,
> {
    typealias UploadUpdate = BackupSettingsAttachmentUploadTracker.UploadUpdate

    /// Simulates "launching with uploads enqueued from a previous launch".
    @Test
    func testLaunchingWithQueuePopulated() async {
        let uploadProgress = MockAttachmentUploadProgress(total: 4)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.running)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 0, total: 4),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 1, total: 4),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 4, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 4, total: 4),
                nextSteps: {
                    uploadQueueStatusReporter.currentStatusMock = .empty
                },
            ),
            ExpectedUpdate(update: nil, nextSteps: {}),
        ]

        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates uploads running, and a caller tracking (e.g., BackupSettings
    /// being presented), then stopping (e.g., dismissing), then starting again.
    @Test
    func testTrackingStoppingAndReTracking() async {
        let uploadProgress = MockAttachmentUploadProgress(total: 4)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.running)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress,
        )

        let firstExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 0, total: 4),
                nextSteps: {},
            ),
        ]
        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: firstExpectedUpdates)

        let secondExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 0, total: 1),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 1)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 1, total: 1),
                nextSteps: {
                    uploadQueueStatusReporter.currentStatusMock = .empty
                },
            ),
            ExpectedUpdate(
                update: nil,
                nextSteps: {},
            ),
        ]
        await runTest(updateStream: uploadTracker.updates(), expectedUpdates: secondExpectedUpdates)
    }

    @Test
    func testTrackingMultipleStreamInstances() async {
        let uploadProgress = MockAttachmentUploadProgress(total: 1)
        let uploadQueueStatusReporter = MockUploadQueueStatusReporter(.running)
        let uploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: uploadQueueStatusReporter,
            backupAttachmentUploadProgress: uploadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 0, total: 1),
                nextSteps: {
                    uploadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 1)
                },
            ),
            ExpectedUpdate(
                update: UploadUpdate(.running, uploaded: 1, total: 1),
                nextSteps: {
                    uploadQueueStatusReporter.currentStatusMock = .empty
                },
            ),
            ExpectedUpdate(
                update: nil,
                nextSteps: {},
            ),
        ]

        await runTest(
            updateStreams: [uploadTracker.updates(), uploadTracker.updates()],
            expectedUpdates: expectedUpdates,
        )
    }
}

// MARK: -

private extension BackupSettingsAttachmentUploadTracker.UploadUpdate {
    init(_ state: State, uploaded: UInt64, total: UInt64) {
        self.init(state: state, bytesUploaded: uploaded, totalBytesToUpload: total)
    }
}

// MARK: -

private class MockAttachmentUploadProgress: BackupAttachmentUploadProgressMock {
    var progressMock: OWSProgress {
        didSet {
            mockObserverBlocks.get().forEach { $0(progressMock) }
        }
    }

    private let mockObserverBlocks: AtomicValue<[(OWSProgress) -> Void]>

    init(total: UInt64) {
        self.mockObserverBlocks = AtomicValue([], lock: .init())
        self.progressMock = OWSProgress(completedUnitCount: 0, totalUnitCount: total)
    }

    override func addObserver(_ block: @escaping (OWSProgress) -> Void) async throws -> BackupAttachmentUploadProgressObserver {
        mockObserverBlocks.update { $0.append(block) }
        return try await super.addObserver(block)
    }
}

// MARK: -

private class MockUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter {
    var currentStatusMock: BackupAttachmentUploadQueueStatus {
        didSet {
            NotificationCenter.default.postOnMainThread(
                name: .backupAttachmentUploadQueueStatusDidChange(for: .fullsize),
                object: nil,
            )
        }
    }

    init(_ initialStatus: BackupAttachmentUploadQueueStatus) {
        self.currentStatusMock = initialStatus
    }

    func currentStatus(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus {
        switch mode {
        case .fullsize:
            break
        case .thumbnail:
            fatalError("Only use fullsize in these tests")
        }
        return currentStatusMock
    }
}
