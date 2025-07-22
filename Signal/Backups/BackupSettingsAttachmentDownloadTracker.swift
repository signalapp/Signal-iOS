//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

final class BackupSettingsAttachmentDownloadTracker {
    struct DownloadUpdate: Equatable {
        enum State: Equatable {
            case suspended
            case running
            case pausedLowBattery
            case pausedNeedsWifi
            case pausedNeedsInternet
            case outOfDiskSpace(bytesRequired: UInt64)
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
                sourceProgresses: [:]
            ))
        }

        fileprivate init(state: State, progress: OWSProgress) {
            self.state = state
            self.progress = progress
        }

        static func == (lhs: DownloadUpdate, rhs: DownloadUpdate) -> Bool {
            return lhs.state == rhs.state && lhs.percentageDownloaded == rhs.percentageDownloaded
        }
    }

    private let backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter
    private let backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress

    init(
        backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter,
        backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress,
    ) {
        self.backupAttachmentDownloadQueueStatusReporter = backupAttachmentDownloadQueueStatusReporter
        self.backupAttachmentDownloadProgress = backupAttachmentDownloadProgress
    }

    func updates() -> AsyncStream<DownloadUpdate?> {
        return AsyncStream { continuation in
            let tracker = Tracker(
                backupAttachmentDownloadQueueStatusReporter: backupAttachmentDownloadQueueStatusReporter,
                backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
                continuation: continuation
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
    typealias DownloadUpdate = BackupSettingsAttachmentDownloadTracker.DownloadUpdate

    private struct State {
        var lastReportedDownloadProgress: OWSProgress = .zero
        var lastReportedDownloadQueueStatus: BackupAttachmentDownloadQueueStatus?

        var downloadQueueStatusObserver: NotificationCenter.Observer?
        var downloadProgressObserver: BackupAttachmentDownloadProgress.Observer?

        let streamContinuation: AsyncStream<DownloadUpdate?>.Continuation
    }

    private let backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter
    private let backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress
    private let state: SeriallyAccessedState<State>

    init(
        backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter,
        backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress,
        continuation: AsyncStream<DownloadUpdate?>.Continuation
    ) {
        self.backupAttachmentDownloadQueueStatusReporter = backupAttachmentDownloadQueueStatusReporter
        self.backupAttachmentDownloadProgress = backupAttachmentDownloadProgress
        self.state = SeriallyAccessedState(State(streamContinuation: continuation))
    }

    func start() {
        state.enqueueUpdate { @MainActor [self] _state in
            let (downloadQueueStatusObserver, downloadQueueStatus) = observeDownloadQueueStatus()
            let downloadProgressObserver = await observeDownloadProgress()

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
                await backupAttachmentDownloadProgress.removeObserver(downloadProgressObserver)
            }

            _state.streamContinuation.finish()
        }
    }

    // MARK: -

    @MainActor
    private func observeDownloadQueueStatus() -> (
        NotificationCenter.Observer,
        BackupAttachmentDownloadQueueStatus
    ) {
        let observer = NotificationCenter.default.addObserver(
            name: .backupAttachmentDownloadQueueStatusDidChange
        ) { [weak self] _ in
            guard let self else { return }

            handleDownloadQueueStatusUpdate()
        }

        return (
            observer,
            backupAttachmentDownloadQueueStatusReporter.currentStatus()
        )
    }

    @MainActor
    private func handleDownloadQueueStatusUpdate() {
        let queueStatus = backupAttachmentDownloadQueueStatusReporter.currentStatus()

        state.enqueueUpdate { [self] _state in
            _state.lastReportedDownloadQueueStatus = queueStatus
            yieldCurrentDownloadUpdate(state: _state)
        }
    }

    // MARK: -

    private func observeDownloadProgress() async -> BackupAttachmentDownloadProgressObserver {
        return await backupAttachmentDownloadProgress.addObserver { [weak self] progressUpdate in
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

        let downloadUpdateState: DownloadUpdate.State? = {
            switch lastReportedDownloadQueueStatus {
            case .suspended:
                return .suspended
            case .running:
                return .running
            case .noWifiReachability:
                return .pausedNeedsWifi
            case .noReachability:
                return .pausedNeedsInternet
            case .lowBattery:
                return .pausedLowBattery
            case .lowDiskSpace:
                return .outOfDiskSpace(bytesRequired: max(
                    lastReportedDownloadProgress.remainingUnitCount,
                    backupAttachmentDownloadQueueStatusReporter.minimumRequiredDiskSpaceToCompleteDownloads()
                ))
            case .empty, .notRegisteredAndReady:
                return nil
            }
        }()

        if let downloadUpdateState {
            streamContinuation.yield(DownloadUpdate(
                state: downloadUpdateState,
                progress: lastReportedDownloadProgress
            ))
        } else {
            streamContinuation.yield(nil)
        }
    }
}
