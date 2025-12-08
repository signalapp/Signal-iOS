//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupExportJobRunnerUpdate {
    case progress(OWSSequentialProgress<BackupExportJobStep>)
    case completion(Result<Void, Error>)
}

/// A wrapper around ``BackupExportJob`` that prevents overlapping job runs and
/// tracks progress updates for the currently-running job.
public protocol BackupExportJobRunner {

    /// An `AsyncStream` that yields updates on the status of the running Backup
    /// export job, if one exists.
    ///
    /// An update will be yielded once with the current status, and again any
    /// time a new update is available. A `nil` update indicates that no export
    /// job is running.
    func updates() -> AsyncStream<BackupExportJobRunnerUpdate?>

    /// Cooperatively cancel the running export job, if one exists.
    func cancelIfRunning()

    /// Run a ``BackupExportJob``, if one is not already running.
    ///
    /// Only one export job is allowed to run at once, so calls to this method
    /// will only start new async work if there is no job running. Callers who
    /// wish to cancel a running job must use ``cancelIfRunning()``.
    ///
    /// - Note
    /// Callers should use ``updates()`` for status notifications about the
    /// running job.
    ///
    /// - SeeAlso ``BackupExportJob/exportAndUploadBackup(onProgressUpdate:)``
    func startIfNecessary()
}

// MARK: -

class BackupExportJobRunnerImpl: BackupExportJobRunner {
    private struct State {
        struct UpdateObserver {
            let id = UUID()
            let block: (BackupExportJobRunnerUpdate?) -> Void
        }

        var updateObservers: [UpdateObserver] = []
        var currentExportJobTask: Task<Void, Never>?

        var progressUpdateDebounceUntil: [BackupExportJobStep: MonotonicDate] = [:]

        var latestUpdate: BackupExportJobRunnerUpdate? {
            didSet {
                for observer in updateObservers {
                    observer.block(latestUpdate)
                }
            }
        }
    }

    private let backupExportJob: BackupExportJob
    private let state: SeriallyAccessedState<State>

    init(backupExportJob: BackupExportJob) {
        self.backupExportJob = backupExportJob
        self.state = SeriallyAccessedState(State())
    }

    // MARK: -

    func updates() -> AsyncStream<BackupExportJobRunnerUpdate?> {
        return AsyncStream { continuation in
            let observer = addUpdateObserver { update in
                continuation.yield(update)
            }

            continuation.onTermination = { [weak self] reason in
                guard let self else { return }
                removeUpdateObserver(observer)
            }
        }
    }

    private func addUpdateObserver(
        block: @escaping (BackupExportJobRunnerUpdate?) -> Void
    ) -> State.UpdateObserver {
        let observer = State.UpdateObserver(block: block)

        state.enqueueUpdate { _state in
            observer.block(_state.latestUpdate)
            _state.updateObservers.append(observer)
        }

        return observer
    }

    private func removeUpdateObserver(_ observer: State.UpdateObserver) {
        state.enqueueUpdate { _state in
            _state.updateObservers.removeAll { $0.id == observer.id }
        }
    }

    // MARK: -

    func cancelIfRunning() {
        state.enqueueUpdate { _state in
            if let currentExportJobTask = _state.currentExportJobTask {
                currentExportJobTask.cancel()
            }
        }
    }

    // MARK: -

    func startIfNecessary() {
        state.enqueueUpdate { [self] _state in
            if _state.currentExportJobTask != nil {
                return
            }

            _state.currentExportJobTask = Task { () async -> Void in
                let result = await Result(catching: {
                    try await backupExportJob.exportAndUploadBackup(
                        mode: .manual(OWSSequentialProgress<BackupExportJobStep>
                            .createSink { [weak self] exportJobProgress in
                                self?.exportJobDidUpdateProgress(exportJobProgress)
                            }
                        )
                    )
                })

                exportJobDidComplete(result: result)
            }
        }
    }

    private func exportJobDidUpdateProgress(_ exportJobProgress: OWSSequentialProgress<BackupExportJobStep>) {
        self.state.enqueueUpdate { _state in
            guard _state.currentExportJobTask != nil else {
                // Our running job completed before this progress update was
                // emitted, so ignore this late update.
                return
            }

            let currentStep = exportJobProgress.currentStep
            let now = MonotonicDate()
            let shortDebounceUntil = now.adding(0.1)
            let longDebounceUntil = now.adding(0.5)

            // If this is our first update, publish immediately.
            if _state.progressUpdateDebounceUntil.isEmpty {
                _state.progressUpdateDebounceUntil[currentStep] = shortDebounceUntil
                _state.latestUpdate = .progress(exportJobProgress)
                return
            }

            if let debounceUntil = _state.progressUpdateDebounceUntil[currentStep] {
                if now > debounceUntil {
                    _state.progressUpdateDebounceUntil[currentStep] = shortDebounceUntil
                    _state.latestUpdate = .progress(exportJobProgress)
                } else {
                    // We're debounced: ignore this update.
                }
            } else {
                // Skip updates for a longer debounce the first time we start a
                // new step. This helps prevent short-lived steps from flashing
                // on and then off screen.
                _state.progressUpdateDebounceUntil[currentStep] = longDebounceUntil
            }
        }
    }

    private func exportJobDidComplete(result: Result<Void, Error>) {
        self.state.enqueueUpdate { _state in
            _state.currentExportJobTask = nil

            // Reset all debounces.
            _state.progressUpdateDebounceUntil = [:]

            // Push through the completion update...
            _state.latestUpdate = .completion(result)
            // ...then reset back to empty.
            _state.latestUpdate = nil
        }
    }
}
