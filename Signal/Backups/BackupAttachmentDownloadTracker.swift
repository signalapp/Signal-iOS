//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Manages async streams of `DownloadUpdate`s, which represent the state and
/// progress of Backup Attachment downloads.
///
/// - SeeAlso `BackupAttachmentDownloadQueueStatusManager`
/// - SeeAlso `BackupAttachmentDownloadProgress`
///
/// - SeeAlso ``BackupAttachmentUploadTracker``
final class BackupAttachmentDownloadTracker {
    struct DownloadUpdate: Equatable {
        enum State: Equatable {
            case empty
            case running
            case suspended
            case pausedLowBattery
            case pausedLowPowerMode
            case pausedNeedsWifi
            case pausedNeedsInternet
            case outOfDiskSpace(bytesRequired: UInt64)
            case notRegisteredAndReady
        }

        let state: State
        var bytesDownloaded: UInt64 { progress.completedUnitCount }
        var totalBytesToDownload: UInt64 { progress.totalUnitCount }
        var percentageDownloaded: Float { progress.percentComplete }

        private let progress: OWSProgress

        init(state: State, bytesDownloaded: UInt64, totalBytesToDownload: UInt64) {
            self.init(state: state, progress: OWSProgress(
                completedUnitCount: bytesDownloaded,
                totalUnitCount: totalBytesToDownload,
            ))
        }

        fileprivate init(state: State, progress: OWSProgress) {
            self.state = state
            self.progress = progress
        }

        static func ==(lhs: DownloadUpdate, rhs: DownloadUpdate) -> Bool {
            return lhs.state == rhs.state && lhs.percentageDownloaded == rhs.percentageDownloaded
        }
    }

    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress

    init(
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress,
    ) {
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupAttachmentDownloadProgress = backupAttachmentDownloadProgress
    }

    func updates() -> AsyncStream<DownloadUpdate> {
        return AsyncStream { continuation in
            let tracker = Tracker(
                backupAttachmentDownloadQueueStatusManager: backupAttachmentDownloadQueueStatusManager,
                backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
                continuation: continuation,
            )

            tracker.start()

            continuation.onTermination = { reason in
                switch reason {
                case .cancelled:
                    tracker.stop()
                case .finished:
                    owsFailDebug("How did we finish? We should've canceled first.")
                @unknown default:
                    owsFailDebug("Unexpected continuation termination reason: \(reason)")
                    tracker.stop()
                }
            }
        }
    }
}

// MARK: -

private class Tracker {
    typealias DownloadUpdate = BackupAttachmentDownloadTracker.DownloadUpdate

    private struct State {
        var lastReportedDownloadProgress: OWSProgress = .zero
        var lastReportedDownloadQueueStatus: BackupAttachmentDownloadQueueStatus?

        var downloadQueueStatusObserver: NotificationCenter.Observer?
        var downloadProgressObserver: BackupAttachmentDownloadProgress.Observer?

        let streamContinuation: AsyncStream<DownloadUpdate>.Continuation
    }

    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress
    private let state: SeriallyAccessedState<State>

    init(
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress,
        continuation: AsyncStream<DownloadUpdate>.Continuation,
    ) {
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupAttachmentDownloadProgress = backupAttachmentDownloadProgress
        self.state = SeriallyAccessedState(State(streamContinuation: continuation))
    }

    func start() {
        state.enqueueUpdate { @MainActor [self] _state in
            let (downloadQueueStatusObserver, downloadQueueStatus) = observeDownloadQueueStatus()
            let downloadProgressObserver = observeDownloadProgress()

            _state.downloadQueueStatusObserver = downloadQueueStatusObserver
            _state.lastReportedDownloadQueueStatus = downloadQueueStatus

            _state.downloadProgressObserver = downloadProgressObserver

            // We don't need to yield an "initial" update here, since the
            // download progress observer we just added will shortly be called
            // back with an initial value.
        }
    }

    func stop() {
        state.enqueueUpdate { [self] _state in
            if let downloadQueueStatusObserver = _state.downloadQueueStatusObserver {
                NotificationCenter.default.removeObserver(downloadQueueStatusObserver)
            }

            if let downloadProgressObserver = _state.downloadProgressObserver {
                backupAttachmentDownloadProgress.removeObserver(downloadProgressObserver)
            }

            _state.streamContinuation.finish()
        }
    }

    // MARK: -

    @MainActor
    private func observeDownloadQueueStatus() -> (
        NotificationCenter.Observer,
        BackupAttachmentDownloadQueueStatus,
    ) {
        let observer = NotificationCenter.default.addObserver(
            name: .backupAttachmentDownloadQueueStatusDidChange(mode: .fullsize),
        ) { [weak self] _ in
            guard let self else { return }

            handleDownloadQueueStatusUpdate()
        }

        return (
            observer,
            backupAttachmentDownloadQueueStatusManager.beginObservingIfNecessary(for: .fullsize),
        )
    }

    @MainActor
    private func handleDownloadQueueStatusUpdate() {
        let queueStatus = backupAttachmentDownloadQueueStatusManager.currentStatus(for: .fullsize)

        state.enqueueUpdate { [self] _state in
            _state.lastReportedDownloadQueueStatus = queueStatus
            yieldCurrentDownloadUpdate(state: _state)
        }
    }

    // MARK: -

    private func observeDownloadProgress() -> BackupAttachmentDownloadProgressObserver {
        return backupAttachmentDownloadProgress.addObserver { [weak self] progressUpdate in
            guard let self else { return }

            handleDownloadProgressUpdate(progressUpdate)
        }
    }

    private func handleDownloadProgressUpdate(_ downloadProgress: OWSProgress) {
        state.enqueueUpdate { [self] _state in
            _state.lastReportedDownloadProgress = downloadProgress
            yieldCurrentDownloadUpdate(state: _state)
        }
    }

    // MARK: -

    private func yieldCurrentDownloadUpdate(state: State) {
        let streamContinuation = state.streamContinuation
        let lastReportedDownloadProgress = state.lastReportedDownloadProgress

        guard let lastReportedDownloadQueueStatus = state.lastReportedDownloadQueueStatus else {
            return
        }

        let downloadUpdateState: DownloadUpdate.State
        switch lastReportedDownloadQueueStatus {
        case .appBackgrounded:
            // Don't emit an update when the app is backgrounded, so callers are
            // left with the last update before backgrounding.
            return
        case .empty:
            downloadUpdateState = .empty
        case .running:
            if lastReportedDownloadProgress == .zero {
                // Don't emit an update for the running queue with no progress.
                // We'll emit an update when we have something more meaningful.
                return
            }

            downloadUpdateState = .running
        case .suspended:
            downloadUpdateState = .suspended
        case .noWifiReachability:
            downloadUpdateState = .pausedNeedsWifi
        case .noReachability:
            downloadUpdateState = .pausedNeedsInternet
        case .lowBattery:
            downloadUpdateState = .pausedLowBattery
        case .lowPowerMode:
            downloadUpdateState = .pausedLowPowerMode
        case .lowDiskSpace:
            downloadUpdateState = .outOfDiskSpace(bytesRequired: max(
                lastReportedDownloadProgress.remainingUnitCount,
                backupAttachmentDownloadQueueStatusManager.minimumRequiredDiskSpaceToCompleteDownloads(),
            ))
        case .notRegisteredAndReady:
            downloadUpdateState = .notRegisteredAndReady
        }

        streamContinuation.yield(DownloadUpdate(
            state: downloadUpdateState,
            progress: lastReportedDownloadProgress,
        ))
    }
}
