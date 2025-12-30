//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SwiftUI

final class BackupSettingsAttachmentUploadTracker {
    struct UploadUpdate: Equatable {
        enum State {
            case running
            case pausedLowBattery
            case pausedLowPowerMode
            case pausedNeedsWifi
            case pausedNeedsInternet
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
            return lhs.state == rhs.state && lhs.percentageUploaded == rhs.percentageUploaded
        }
    }

    private let backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress

    init(
        backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
    ) {
        self.backupAttachmentUploadQueueStatusReporter = backupAttachmentUploadQueueStatusReporter
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
    }

    func updates() -> AsyncStream<UploadUpdate?> {
        return AsyncStream { continuation in
            let tracker = Tracker(
                backupAttachmentUploadQueueStatusReporter: backupAttachmentUploadQueueStatusReporter,
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
    typealias UploadUpdate = BackupSettingsAttachmentUploadTracker.UploadUpdate

    private struct State {
        var lastReportedUploadProgress: OWSProgress = .zero
        var lastReportedUploadQueueStatus: BackupAttachmentUploadQueueStatus?

        var uploadQueueStatusObserver: NotificationCenter.Observer?
        var uploadProgressObserver: BackupAttachmentUploadProgress.Observer?

        let streamContinuation: AsyncStream<UploadUpdate?>.Continuation
    }

    private let backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let state: SeriallyAccessedState<State>

    init(
        backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        continuation: AsyncStream<UploadUpdate?>.Continuation,
    ) {
        self.backupAttachmentUploadQueueStatusReporter = backupAttachmentUploadQueueStatusReporter
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
                await backupAttachmentUploadProgress.removeObserver(uploadProgressObserver)
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
                backupAttachmentUploadQueueStatusReporter.currentStatus(for: .fullsize),
            )
        }

        // Now that we're observing updates, handle the initial value as if we'd
        // just gotten it in an update.
        handleQueueStatusUpdate(
            backupAttachmentUploadQueueStatusReporter.currentStatus(for: .fullsize),
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
                    await backupAttachmentUploadProgress.removeObserver(existingObserver)
                }

                _state.uploadProgressObserver = try? await backupAttachmentUploadProgress
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
        let lastReportedUploadProgress = state.lastReportedUploadProgress

        guard let lastReportedUploadQueueStatus = state.lastReportedUploadQueueStatus else {
            return
        }

        guard lastReportedUploadProgress.totalUnitCount > 0 else {
            // We have no meaningful progress to report on.
            return
        }

        let uploadUpdateState: UploadUpdate.State? = {
            switch lastReportedUploadQueueStatus {
            case .empty:
                return nil
            case .notRegisteredAndReady, .appBackgrounded, .suspended:
                return nil
            case .running:
                return .running
            case .noReachability:
                return .pausedNeedsInternet
            case .noWifiReachability:
                return .pausedNeedsWifi
            case .lowBattery:
                return .pausedLowBattery
            case .lowPowerMode:
                return .pausedLowPowerMode
            case .hasConsumedMediaTierCapacity:
                // This gets bubbled up via other mechanisms; to the UI
                // this upload state doesn't show a bar so its nil.
                return nil
            }
        }()

        if let uploadUpdateState {
            streamContinuation.yield(UploadUpdate(state: uploadUpdateState, progress: lastReportedUploadProgress))
        } else {
            streamContinuation.yield(nil)
        }
    }
}
