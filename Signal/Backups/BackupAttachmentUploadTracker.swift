//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SwiftUI

/// Manages async streams of `UploadUpdate`s, which represent the state and
/// progress of Backup Attachment uploads.
///
/// - SeeAlso `BackupAttachmentUploadQueueStatusManager`
/// - SeeAlso `BackupAttachmentUploadProgress`
///
/// - SeeAlso ``BackupAttachmentDownloadTracker``
final class BackupAttachmentUploadTracker {
    struct UploadUpdate: Equatable {
        enum State {
            case uploading
            /// - Note
            /// We only include "attachments present locally when Backups was
            /// enabled" in upload progress. So, we may have a non-empty "upload
            /// queue" but have no uploads we need to track progress for; hence
            /// the cagey name.
            /// - SeeAlso `BackupAttachmentUploadProgress`
            case noUploadsToReport
            case suspended
            case notRegisteredAndReady
            case pausedLowBattery
            case pausedLowPowerMode
            case pausedNeedsWifi
            case pausedNeedsInternet
            case hasConsumedMediaTierCapacity
        }

        let state: State
        var bytesUploaded: UInt64 { progress.completedUnitCount }
        var totalBytesToUpload: UInt64 { progress.totalUnitCount }
        var percentageUploaded: Float { progress.percentComplete }

        private let progress: OWSProgress

        init(state: State, bytesUploaded: UInt64, totalBytesToUpload: UInt64) {
            self.init(state: state, progress: OWSProgress(
                completedUnitCount: bytesUploaded,
                totalUnitCount: totalBytesToUpload,
            ))
        }

        fileprivate init(state: State, progress: OWSProgress) {
            self.state = state
            self.progress = progress
        }

        static func ==(lhs: UploadUpdate, rhs: UploadUpdate) -> Bool {
            return lhs.state == rhs.state
                && lhs.bytesUploaded == rhs.bytesUploaded
                && lhs.totalBytesToUpload == rhs.totalBytesToUpload
        }
    }

    private let backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress

    init(
        backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
    ) {
        self.backupAttachmentUploadQueueStatusManager = backupAttachmentUploadQueueStatusManager
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
    }

    func updates() -> AsyncStream<UploadUpdate> {
        return AsyncStream { continuation in
            let tracker = Tracker(
                backupAttachmentUploadQueueStatusManager: backupAttachmentUploadQueueStatusManager,
                backupAttachmentUploadProgress: backupAttachmentUploadProgress,
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
    typealias UploadUpdate = BackupAttachmentUploadTracker.UploadUpdate

    private struct State {
        var lastReportedUploadProgress: OWSProgress?
        var lastReportedUploadQueueStatus: BackupAttachmentUploadQueueStatus?

        var uploadQueueStatusObserver: NotificationCenter.Observer?
        var uploadProgressObserver: BackupAttachmentUploadProgress.Observer?

        let streamContinuation: AsyncStream<UploadUpdate>.Continuation
    }

    private let backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let state: SeriallyAccessedState<State>

    init(
        backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        continuation: AsyncStream<UploadUpdate>.Continuation,
    ) {
        self.backupAttachmentUploadQueueStatusManager = backupAttachmentUploadQueueStatusManager
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.state = SeriallyAccessedState(State(
            streamContinuation: continuation,
        ))
    }

    func start() {
        state.enqueueUpdate { @MainActor [self] _state in
            _state.uploadQueueStatusObserver = observeUploadQueueStatus()
        }
    }

    func stop() {
        state.enqueueUpdate { [self] _state in
            if let uploadQueueStatusObserver = _state.uploadQueueStatusObserver {
                NotificationCenter.default.removeObserver(uploadQueueStatusObserver)
            }

            if let uploadProgressObserver = _state.uploadProgressObserver {
                backupAttachmentUploadProgress.removeObserver(uploadProgressObserver)
            }

            _state.streamContinuation.finish()
        }
    }

    // MARK: -

    @MainActor
    private func observeUploadQueueStatus() -> NotificationCenter.Observer {
        // We only care about fullsize uploads, ignore thumbnails
        let uploadQueueStatusObserver = NotificationCenter.default.addObserver(
            name: .backupAttachmentUploadQueueStatusDidChange(for: .fullsize),
        ) { [weak self] notification in
            guard let self else { return }

            handleQueueStatusUpdate(
                backupAttachmentUploadQueueStatusManager.currentStatus(for: .fullsize),
            )
        }

        // Now that we're observing updates, handle the initial value as if we'd
        // just gotten it in an update.
        handleQueueStatusUpdate(
            backupAttachmentUploadQueueStatusManager.beginObservingIfNecessary(for: .fullsize),
        )

        return uploadQueueStatusObserver
    }

    private func handleQueueStatusUpdate(
        _ queueStatus: BackupAttachmentUploadQueueStatus,
    ) {
        state.enqueueUpdate { [self] _state in
            _state.lastReportedUploadQueueStatus = queueStatus

            switch queueStatus {
            case .empty:
                yieldCurrentUploadUpdate(state: _state)
            case
                .running,
                .noWifiReachability, .lowBattery, .lowPowerMode, .noReachability,
                .notRegisteredAndReady, .appBackgrounded, .suspended, .hasConsumedMediaTierCapacity:
                // The queue isn't empty, so attach a new progress observer.
                //
                // Progress observers snapshot and filter the queue's state, so
                // any time the queue is non-empty we want to make sure we have
                // an observer with a filtered-snapshot of the latest state.
                //
                // For example, when we first enable paid-tier Backups the queue
                // starts empty and is populated when we run list-media for the
                // first time.
                //
                // The observer we attach will yield an update, so we don't need
                // to here.
                if let existingObserver = _state.uploadProgressObserver {
                    backupAttachmentUploadProgress.removeObserver(existingObserver)
                }

                _state.uploadProgressObserver = backupAttachmentUploadProgress
                    .addObserver { [weak self] progressUpdate in
                        guard let self else { return }
                        handleUploadProgressUpdate(progressUpdate)
                    }
            }
        }
    }

    private func handleUploadProgressUpdate(_ uploadProgress: OWSProgress) {
        state.enqueueUpdate { [self] _state in
            _state.lastReportedUploadProgress = uploadProgress
            yieldCurrentUploadUpdate(state: _state)
        }
    }

    // MARK: -

    private func yieldCurrentUploadUpdate(state: State) {
        let streamContinuation = state.streamContinuation

        guard
            let lastReportedUploadProgress = state.lastReportedUploadProgress,
            let lastReportedUploadQueueStatus = state.lastReportedUploadQueueStatus
        else {
            return
        }

        guard lastReportedUploadProgress.totalUnitCount > 0 else {
            // If our "total bytes" to upload is zero, then regardless of the
            // queue status we have nothing to report.
            streamContinuation.yield(UploadUpdate(
                state: .noUploadsToReport,
                progress: lastReportedUploadProgress,
            ))
            return
        }

        let uploadUpdateState: UploadUpdate.State
        switch lastReportedUploadQueueStatus {
        case .appBackgrounded:
            // Don't emit an update when the app is backgrounded, so callers are
            // left with the last update before backgrounding.
            return
        case .running:
            uploadUpdateState = .uploading
        case .suspended:
            uploadUpdateState = .suspended
        case .empty:
            uploadUpdateState = .noUploadsToReport
        case .notRegisteredAndReady:
            uploadUpdateState = .notRegisteredAndReady
        case .noReachability:
            uploadUpdateState = .pausedNeedsInternet
        case .noWifiReachability:
            uploadUpdateState = .pausedNeedsWifi
        case .lowBattery:
            uploadUpdateState = .pausedLowBattery
        case .lowPowerMode:
            uploadUpdateState = .pausedLowPowerMode
        case .hasConsumedMediaTierCapacity:
            uploadUpdateState = .hasConsumedMediaTierCapacity
        }

        streamContinuation.yield(UploadUpdate(
            state: uploadUpdateState,
            progress: lastReportedUploadProgress,
        ))
    }
}
