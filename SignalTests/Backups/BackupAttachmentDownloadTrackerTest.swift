//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import Signal
@testable import SignalServiceKit

@MainActor
@Suite(.serialized)
final class BackupAttachmentDownloadTrackerTest: BackupAttachmentTrackerTest<
    BackupAttachmentDownloadTracker.DownloadUpdate,
> {
    typealias DownloadUpdate = BackupAttachmentDownloadTracker.DownloadUpdate

    /// Simulates "launching with downloads enqueued from a previous launch".
    @Test
    func testLaunchingWithQueuePopulated() async {
        let downloadProgress = MockAttachmentDownloadProgress(total: 4)
        let downloadQueueStatusManager = MockDownloadQueueStatusManager(.running)

        let downloadTracker = BackupAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusManager: downloadQueueStatusManager,
            backupAttachmentDownloadProgress: downloadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 0, total: 4),
                nextSteps: {
                    downloadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 1, total: 4),
                nextSteps: {
                    downloadProgress.progressMock = OWSProgress(completedUnitCount: 4, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 4, total: 4),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.empty)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.empty, downloaded: 4, total: 4),
                nextSteps: {},
            ),
        ]

        await runTest(updateStream: downloadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates "taps Download Media" when "Optimize Media" is on, by starting
    /// with a suspended queue that starts running.
    @Test
    func testQueueStartsSuspendedThenStartsRunning() async {
        let downloadProgress = MockAttachmentDownloadProgress(total: 4)
        let downloadQueueStatusManager = MockDownloadQueueStatusManager(.suspended)

        let downloadTracker = BackupAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusManager: downloadQueueStatusManager,
            backupAttachmentDownloadProgress: downloadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: DownloadUpdate(.suspended, downloaded: 0, total: 4),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.running)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 0, total: 4),
                nextSteps: {
                    downloadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 1, total: 4),
                nextSteps: {
                    downloadProgress.progressMock = OWSProgress(completedUnitCount: 4, totalUnitCount: 4)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 4, total: 4),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.empty)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.empty, downloaded: 4, total: 4),
                nextSteps: {},
            ),
        ]

        await runTest(updateStream: downloadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates downloads running, and the device running out of storage.
    ///
    /// Specifically, running out of disk space when the remaining bytes to
    /// download (50) are more than our required minimum available (10).
    @Test
    func testQueueRunsIntoLowStorage_remainingMoreThanMin() async {
        let downloadProgress = MockAttachmentDownloadProgress(precompleted: 50, total: 100)
        let downloadQueueStatusManager = MockDownloadQueueStatusManager(.running, minimumRequiredDiskSpace: 10)

        let downloadTracker = BackupAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusManager: downloadQueueStatusManager,
            backupAttachmentDownloadProgress: downloadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 50, total: 100),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.lowDiskSpace)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.outOfDiskSpace(bytesRequired: 50), downloaded: 50, total: 100),
                nextSteps: {},
            ),
        ]

        await runTest(updateStream: downloadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates downloads running, and the device running out of storage.
    ///
    /// Specifically, running out of disk space when the remaining bytes to
    /// download (8) are less than our required minimum available (10).
    @Test
    func testQueueRunsIntoLowStorage_remainingLessThanMin() async {
        let downloadProgress = MockAttachmentDownloadProgress(precompleted: 4, total: 12)
        let downloadQueueStatusManager = MockDownloadQueueStatusManager(.running, minimumRequiredDiskSpace: 10)

        let downloadTracker = BackupAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusManager: downloadQueueStatusManager,
            backupAttachmentDownloadProgress: downloadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 4, total: 12),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.lowDiskSpace)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.outOfDiskSpace(bytesRequired: 10), downloaded: 4, total: 12),
                nextSteps: {},
            ),
        ]

        await runTest(updateStream: downloadTracker.updates(), expectedUpdates: expectedUpdates)
    }

    /// Simulates downloads running, and a caller tracking (e.g., BackupSettings
    /// being presented), then stopping (e.g., dismissing), then starting again.
    @Test
    func testTrackingStoppingAndReTracking() async {
        let downloadProgress = MockAttachmentDownloadProgress(total: 4)
        let downloadQueueStatusManager = MockDownloadQueueStatusManager(.empty)

        let downloadTracker = BackupAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusManager: downloadQueueStatusManager,
            backupAttachmentDownloadProgress: downloadProgress,
        )

        let firstExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: DownloadUpdate(.empty, downloaded: 0, total: 4),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.running)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 0, total: 4),
                nextSteps: {},
            ),
        ]
        await runTest(updateStream: downloadTracker.updates(), expectedUpdates: firstExpectedUpdates)

        let secondExpectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 0, total: 1),
                nextSteps: {
                    downloadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 1)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 1, total: 1),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.empty)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.empty, downloaded: 1, total: 1),
                nextSteps: {},
            ),
        ]
        await runTest(updateStream: downloadTracker.updates(), expectedUpdates: secondExpectedUpdates)
    }

    @Test
    func testTrackingMultipleStreamInstances() async {
        let downloadProgress = MockAttachmentDownloadProgress(total: 1)
        let downloadQueueStatusManager = MockDownloadQueueStatusManager(.empty)

        let downloadTracker = BackupAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusManager: downloadQueueStatusManager,
            backupAttachmentDownloadProgress: downloadProgress,
        )

        let expectedUpdates: [ExpectedUpdate] = [
            ExpectedUpdate(
                update: DownloadUpdate(.empty, downloaded: 0, total: 1),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.running)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 0, total: 1),
                nextSteps: {
                    downloadProgress.progressMock = OWSProgress(completedUnitCount: 1, totalUnitCount: 1)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.running, downloaded: 1, total: 1),
                nextSteps: {
                    await downloadQueueStatusManager.setCurrentStatusMock(.empty)
                },
            ),
            ExpectedUpdate(
                update: DownloadUpdate(.empty, downloaded: 1, total: 1),
                nextSteps: {},
            ),
        ]

        await runTest(
            updateStreams: [downloadTracker.updates(), downloadTracker.updates()],
            expectedUpdates: expectedUpdates,
        )
    }
}

// MARK: -

private extension BackupAttachmentDownloadTracker.DownloadUpdate {
    init(_ state: State, downloaded: UInt64, total: UInt64) {
        self.init(state: state, bytesDownloaded: downloaded, totalBytesToDownload: total)
    }
}

// MARK: -

private class MockAttachmentDownloadProgress: BackupAttachmentDownloadProgressMock {
    var progressMock: OWSProgress {
        didSet {
            mockObserverBlocks.get().forEach { $0(progressMock) }
        }
    }

    private let mockObserverBlocks: AtomicValue<[(OWSProgress) -> Void]>

    init(precompleted: UInt64 = 0, total: UInt64) {
        self.mockObserverBlocks = AtomicValue([], lock: .init())
        self.progressMock = OWSProgress(completedUnitCount: precompleted, totalUnitCount: total)
    }

    override func addObserver(_ block: @escaping (OWSProgress) -> Void) -> BackupAttachmentDownloadProgressObserver {
        block(progressMock)
        mockObserverBlocks.update { $0.append(block) }
        return super.addObserver(block)
    }
}

// MARK: -

private class MockDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager {
    init(
        _ initialStatus: BackupAttachmentDownloadQueueStatus,
        minimumRequiredDiskSpace: UInt64 = 0,
    ) {
        self._currentStatusMock = initialStatus
        self.minimumRequiredDiskSpaceMock = minimumRequiredDiskSpace
    }

    private var _currentStatusMock: BackupAttachmentDownloadQueueStatus
    func setCurrentStatusMock(_ currentStatusMock: BackupAttachmentDownloadQueueStatus) {
        _currentStatusMock = currentStatusMock
        NotificationCenter.default.postOnMainThread(
            name: .backupAttachmentDownloadQueueStatusDidChange(mode: .fullsize),
            object: nil,
        )
    }

    func currentStatus(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus {
        switch mode {
        case .fullsize:
            break
        case .thumbnail:
            fatalError("Only fullsize in this test")
        }
        return _currentStatusMock
    }

    func currentStatusAndToken(for mode: BackupAttachmentDownloadQueueMode) -> (BackupAttachmentDownloadQueueStatus, BackupAttachmentDownloadQueueStatusToken) {
        switch mode {
        case .fullsize:
            break
        case .thumbnail:
            fatalError("Only fullsize in this test")
        }
        return (_currentStatusMock, MockBackupAttachmentDownloadQueueStatusManager.BackupAttachmentDownloadQueueStatusTokenMock())
    }

    func beginObservingIfNecessary(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus {
        return _currentStatusMock
    }

    func jobDidExperienceError(_ error: any Error, token: any BackupAttachmentDownloadQueueStatusToken, mode: BackupAttachmentDownloadQueueMode) async -> BackupAttachmentDownloadQueueStatus? {
        return nil
    }

    func jobDidSucceed(token: any BackupAttachmentDownloadQueueStatusToken, mode: BackupAttachmentDownloadQueueMode) async {
        // Do nothing
    }

    func didEmptyQueue(for mode: BackupAttachmentDownloadQueueMode) {
        // Do nothing
    }

    func setIsMainAppAndActiveOverride(_ newValue: Bool) {
        // Do nothing
    }

    nonisolated let minimumRequiredDiskSpaceMock: UInt64
    func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64 {
        minimumRequiredDiskSpaceMock
    }

    func checkAvailableDiskSpace(clearPreviousOutOfSpaceErrors: Bool) {
        // Do nothing
    }
}
