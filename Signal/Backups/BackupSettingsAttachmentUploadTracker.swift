//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SwiftUI

@MainActor
class BackupSettingsAttachmentUploadTracker {
    struct UploadUpdate {
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
    }

    private struct State {
        var lastReportedUploadProgress: OWSProgress = .zero
        var lastReportedQueueStatus: BackupAttachmentQueueStatus?

        var isTracking: Bool = false
        var uploadQueueStatusObserver: NotificationCenter.Observer?
        var uploadProgressObserver: BackupAttachmentUploadProgress.Observer?
        var streamContinuation: AsyncStream<UploadUpdate?>.Continuation?
    }

    private let backupAttachmentQueueStatusManager: BackupAttachmentQueueStatusManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let state: AsyncAtomic<State>

    init(
        backupAttachmentQueueStatusManager: BackupAttachmentQueueStatusManager,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
    ) {
        self.backupAttachmentQueueStatusManager = backupAttachmentQueueStatusManager
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.state = AsyncAtomic(State())
    }

    func start() async -> AsyncStream<UploadUpdate?> {
        return await state.update { _state in
            owsPrecondition(!_state.isTracking, "Multiple simultaneous trackings not supported.")
            _state.isTracking = true

            return AsyncStream { continuation in
                _state.streamContinuation = continuation
                _state.uploadQueueStatusObserver = observeUploadQueueStatus()

                continuation.onTermination = { [weak self] reason in
                    guard let self else { return }

                    switch reason {
                    case .finished: return
                    case .cancelled: break
                    @unknown default: break
                    }

                    Task {
                        await self.stop()
                    }
                }
            }
        }
    }

    func stop() async {
        await state.update { _state in
            if let uploadQueueStatusObserver = _state.uploadQueueStatusObserver {
                NotificationCenter.default.removeObserver(uploadQueueStatusObserver)
            }

            if let uploadProgressObserver = _state.uploadProgressObserver {
                await backupAttachmentUploadProgress.removeObserver(uploadProgressObserver)
            }

            if let streamContinuation = _state.streamContinuation {
                streamContinuation.finish()
            }

            _state = State()
        }
    }

    // MARK: -

    private func observeUploadQueueStatus() -> NotificationCenter.Observer {
        let uploadQueueStatusObserver = NotificationCenter.default.addObserver(
            name: BackupAttachmentQueueStatus.didChangeNotification
        ) { [weak self] notification in
            guard
                let self,
                let userInfo = notification.userInfo,
                let queueType = userInfo[BackupAttachmentQueueStatus.notificationQueueTypeKey] as? BackupAttachmentQueueType,
                queueType == .upload
            else { return }

            Task {
                await self.handleQueueStatusUpdate()
            }
        }

        // Now that we're observing updates, handle the initial value as if we'd
        // just gotten it in an update.
        Task {
            await handleQueueStatusUpdate()
        }

        return uploadQueueStatusObserver
    }

    private func handleQueueStatusUpdate() async {
        await state.update { _state in
            _state.lastReportedQueueStatus = backupAttachmentQueueStatusManager.currentStatus(type: .upload)

            switch _state.lastReportedQueueStatus! {
            case .running:
                // If the queue is running, add an observer. It's important that
                // we not do this until the queue is running, since the observer
                // only operates on a snapshot of the queue and we want that
                // snapshot to represent a running queue.
                let observer = try? await backupAttachmentUploadProgress
                    .addObserver { [weak self] progressUpdate in
                        guard let self else { return }

                        Task {
                            await self.handleUploadProgressUpdate(progressUpdate)
                        }
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

            case .noWifiReachability, .lowBattery, .suspended, .lowDiskSpace:
                break
            }

            yieldCurrentUploadUpdate(state: _state)
        }
    }

    private func handleUploadProgressUpdate(_ uploadProgress: OWSProgress) async {
        await state.update { _state in
            _state.lastReportedUploadProgress = uploadProgress

            yieldCurrentUploadUpdate(state: _state)
        }
    }

    // MARK: -

    private func yieldCurrentUploadUpdate(state: State) {
        guard let streamContinuation = state.streamContinuation else {
            return
        }

        let lastReportedQueueStatus = state.lastReportedQueueStatus
        let lastReportedUploadProgress = state.lastReportedUploadProgress

        switch lastReportedQueueStatus {
        case .running:
            streamContinuation.yield(UploadUpdate(state: .running, progress: lastReportedUploadProgress))
        case .noWifiReachability:
            streamContinuation.yield(UploadUpdate(state: .pausedNeedsWifi, progress: lastReportedUploadProgress))
        case .lowBattery:
            streamContinuation.yield(UploadUpdate(state: .pausedLowBattery, progress: lastReportedUploadProgress))
        case .empty, .notRegisteredAndReady:
            streamContinuation.yield(nil)
        case nil, .suspended, .lowDiskSpace:
            owsFailDebug("Unexpected upload queue status! \(lastReportedQueueStatus as Any)")
            streamContinuation.yield(nil)
        }
    }
}
