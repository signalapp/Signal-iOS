//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupExportJobRunnerUpdate {
    case progress(OWSSequentialProgress<BackupExportJobStage>)
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

    /// Resume an interrupted ``BackupExportJob`` from a previous launch, if
    /// one exists. Resumed jobs are run using ``BackupExportJobMode/manual``.
    ///
    /// - SeeAlso ``BackupExportJobStore``
    func resumeIfNecessary()

    /// Cancel the in-progress `BackupExportJob`, if one exists.
    ///
    /// - Returns
    /// A `Task` tracking the teardown of the canceled `BackupExportJob`, if one
    /// was running.
    func cancelIfRunning() -> Task<Void, Error>?

    /// Run a ``BackupExportJob``, if one is not already running.
    ///
    /// - Note
    /// To receive granular updates on a running job, use ``updates()``.
    ///
    /// - Returns
    /// A `Task` tracking a `BackupExportJob` run, which may be freshly started
    /// or preexisting.
    func startIfNecessary(mode: BackupExportJobMode) -> Task<Void, Error>
}

// MARK: -

class BackupExportJobRunnerImpl: BackupExportJobRunner {
    private struct State {
        struct UpdateObserver {
            let id = UUID()
            let block: (BackupExportJobRunnerUpdate?) -> Void
        }

        var updateObservers: [UpdateObserver] = []
        var currentExportJobTask: Task<Void, Error>?

        var nextProgressUpdate: OWSSequentialProgress<BackupExportJobStage>?
        var latestUpdate: BackupExportJobRunnerUpdate? {
            didSet {
                for observer in updateObservers {
                    observer.block(latestUpdate)
                }
            }
        }
    }

    private let backupExportJob: BackupExportJob
    private let backupExportJobStore: BackupExportJobStore
    private let db: DB

    private let state: AtomicValue<State>

    init(
        backupExportJob: BackupExportJob,
        backupExportJobStore: BackupExportJobStore,
        db: DB,
    ) {
        self.backupExportJob = backupExportJob
        self.backupExportJobStore = backupExportJobStore
        self.db = db

        self.state = AtomicValue(State(), lock: .init())
    }

    // MARK: -

    private lazy var progressUpdateDebouncer = DebouncedEvents.build(
        mode: .firstLast,
        maxFrequencySeconds: 0.2,
        onQueue: .main,
        notifyBlock: { [weak self] in
            guard let self else { return }

            state.update { _state in
                guard let nextProgressUpdate = _state.nextProgressUpdate.take() else {
                    return
                }

                guard _state.currentExportJobTask != nil else {
                    // Our running job completed before this progress update was
                    // emitted, so ignore this late update.
                    return
                }

                _state.latestUpdate = .progress(nextProgressUpdate)
            }
        },
    )

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
        block: @escaping (BackupExportJobRunnerUpdate?) -> Void,
    ) -> State.UpdateObserver {
        let observer = State.UpdateObserver(block: block)

        state.update { _state in
            observer.block(_state.latestUpdate)
            _state.updateObservers.append(observer)
        }

        return observer
    }

    private func removeUpdateObserver(_ observer: State.UpdateObserver) {
        state.update { _state in
            _state.updateObservers.removeAll { $0.id == observer.id }
        }
    }

    // MARK: -

    func resumeIfNecessary() {
        let resumptionPoint: BackupExportJobStore.ResumptionPoint? = db.read { tx in
            backupExportJobStore.lastReachedResumptionPoint(tx: tx)
        }

        if let resumptionPoint {
            _ = _startIfNecessary(
                mode: .manual,
                resumptionPoint: resumptionPoint,
            )
        }
    }

    // MARK: -

    func cancelIfRunning() -> Task<Void, Error>? {
        return state.update { _state in
            _state.currentExportJobTask?.cancel()
            return _state.currentExportJobTask
        }
    }

    // MARK: -

    func startIfNecessary(mode: BackupExportJobMode) -> Task<Void, Error> {
        return _startIfNecessary(mode: mode, resumptionPoint: nil)
    }

    private func _startIfNecessary(
        mode: BackupExportJobMode,
        resumptionPoint: BackupExportJobStore.ResumptionPoint?,
    ) -> Task<Void, Error> {
        return state.update { [self] _state in
            if let currentExportJobTask = _state.currentExportJobTask {
                return currentExportJobTask
            }

            let newExportJobTask = Task { () async throws -> Void in
                let result = await Result(catching: {
                    let progressSink = await OWSSequentialProgress<BackupExportJobStage>
                        .createSink { [weak self] exportJobProgress in
                            self?.exportJobDidUpdateProgress(exportJobProgress)
                        }

                    try await backupExportJob.run(
                        mode: mode,
                        resumptionPoint: resumptionPoint,
                        progress: progressSink,
                    )
                })

                exportJobDidComplete(result: result)
                try result.get()
            }

            _state.currentExportJobTask = newExportJobTask
            return newExportJobTask
        }
    }

    private func exportJobDidUpdateProgress(_ exportJobProgress: OWSSequentialProgress<BackupExportJobStage>) {
        state.update { [weak self] _state in
            guard let self else { return }

            // Stash this update for our next debounce
            _state.nextProgressUpdate = exportJobProgress
            progressUpdateDebouncer.requestNotify()
        }
    }

    private func exportJobDidComplete(result: Result<Void, Error>) {
        state.update { _state in
            _state.currentExportJobTask = nil

            // Push through the completion update...
            _state.latestUpdate = .completion(result)
            // ...then reset back to empty.
            _state.latestUpdate = nil
        }
    }
}
