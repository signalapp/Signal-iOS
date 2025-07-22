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
            case pausedNeedsWifi
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
                sourceProgresses: [:]
            ))
        }

        fileprivate init(state: State, progress: OWSProgress) {
            self.state = state
            self.progress = progress
        }

        static func == (lhs: UploadUpdate, rhs: UploadUpdate) -> Bool {
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
        continuation: AsyncStream<UploadUpdate?>.Continuation
    ) {
        self.backupAttachmentUploadQueueStatusReporter = backupAttachmentUploadQueueStatusReporter
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.state = SeriallyAccessedState(State(
            streamContinuation: continuation
        ))
    }

    func start() {
        state.enqueueUpdate { @MainActor [weak self] _state in
            guard let self else { return }
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
        let uploadQueueStatusObserver = NotificationCenter.default.addObserver(
            name: .backupAttachmentUploadQueueStatusDidChange
        ) { [weak self] notification in
            guard let self else { return }

            handleQueueStatusUpdate(
                backupAttachmentUploadQueueStatusReporter.currentStatus()
            )
        }

        // Now that we're observing updates, handle the initial value as if we'd
        // just gotten it in an update.
        handleQueueStatusUpdate(
            backupAttachmentUploadQueueStatusReporter.currentStatus()
        )

        return uploadQueueStatusObserver
    }

    private func handleQueueStatusUpdate(
        _ queueStatus: BackupAttachmentUploadQueueStatus,
    ) {
        state.enqueueUpdate { [self] _state in
            _state.lastReportedUploadQueueStatus = queueStatus

            switch queueStatus {
            case .running:
                // If the queue is running, add an observer. It's important that
                // we not do this until the queue is running, since the observer
                // only operates on a snapshot of the queue and we want that
                // snapshot to represent a running queue.
                let observer = try? await backupAttachmentUploadProgress
                    .addObserver { [weak self] progressUpdate in
                        guard let self else { return }

                        handleUploadProgressUpdate(progressUpdate)
                    }

                if let observer {
                    owsAssertDebug(_state.uploadProgressObserver == nil)
                    _state.uploadProgressObserver = observer
                }

                // We don't need to yield an upload update here: the progress
                // observer we just added will do so.
                return

            case .empty, .notRegisteredAndReady:
                if let uploadProgressObserver = _state.uploadProgressObserver {
                    await backupAttachmentUploadProgress.removeObserver(uploadProgressObserver)
                }

                _state.uploadProgressObserver = nil

            case .noWifiReachability, .lowBattery:
                break
            }

            yieldCurrentUploadUpdate(state: _state)
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

        let uploadUpdateState: UploadUpdate.State? = {
            switch lastReportedUploadQueueStatus {
            case .running:
                return .running
            case .noWifiReachability:
                return .pausedNeedsWifi
            case .lowBattery:
                return .pausedLowBattery
            case .empty, .notRegisteredAndReady:
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
