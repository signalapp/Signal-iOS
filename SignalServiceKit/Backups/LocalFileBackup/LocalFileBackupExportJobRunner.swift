//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum LocalFileBackupExportJobRunnerUpdate {
    case progress(OWSSequentialProgress<LocalFileBackupExportJobStage>)
    case completion(Result<Void, Error>)
}

/// A wrapper around ``LocalFileBackupExportJob`` that prevents overlapping job runs and
/// tracks progress updates for the currently-running job.
public protocol LocalFileBackupExportJobRunner {

    /// An `AsyncStream` that yields updates on the status of the running local file backup
    /// export job, if one exists.
    ///
    /// An update will be yielded once with the current status, and again any
    /// time a new update is available. A `nil` update indicates that no export
    /// job is running.
    func updates() -> AsyncStream<LocalFileBackupExportJobRunnerUpdate?>

    /// Resume an interrupted ``LocalFileBackupExportJob`` from a previous launch, if
    /// one exists. Resumed jobs are run using ``LocalFileBackupExportJob/manual``.
    ///
    /// - Returns
    /// A optional `Task` tracking a `LocalFileBackupExportJob` being resumed.
    ///
    /// - SeeAlso ``LocalFileBackupExportJobStore``
    func resumeIfNecessary() -> Task<Void, Error>?

    /// Cancel the in-progress `LocalFileBackupExportJob`, if one exists.
    ///
    /// - Returns
    /// A `Task` tracking the teardown of the canceled `LocalFileBackupExportJob`, if one
    /// was running.
    func cancelIfRunning() -> Task<Void, Error>?

    /// Run a ``LocalFileBackupExportJob``, if one is not already running.
    ///
    /// - Returns
    /// A `Task` tracking a `LocalFileBackupExportJob` run, which may be freshly started
    /// or preexisting.
    func startIfNecessary(mode: LocalFileBackupExportJobMode) -> Task<Void, Error>
}

// MARK: -

public class LocalFileBackupExportJobRunnerImpl: LocalFileBackupExportJobRunner {
    private struct State {
        struct UpdateObserver {
            let id = UUID()
            let block: (LocalFileBackupExportJobRunnerUpdate?) -> Void
        }

        var updateObservers: [UpdateObserver] = []
        var currentExportJobTask: Task<Void, Error>?

        var nextProgressUpdate: OWSSequentialProgress<LocalFileBackupExportJobStage>?
        var latestUpdate: LocalFileBackupExportJobRunnerUpdate? {
            didSet {
                for observer in updateObservers {
                    observer.block(latestUpdate)
                }
            }
        }
    }

    private let localFileBackupExportJob: LocalFileBackupExportJob
    private let localFileBackupExportJobStore: LocalFileBackupExportJobStore
    private let db: DB

    private let backupExportLock: BackupExportLock
    private let state: AtomicValue<State>

    init(
        localFileBackupExportJob: LocalFileBackupExportJob,
        localFileBackupExportJobStore: LocalFileBackupExportJobStore,
        db: DB,
        backupExportLock: BackupExportLock,
    ) {
        self.localFileBackupExportJob = localFileBackupExportJob
        self.localFileBackupExportJobStore = localFileBackupExportJobStore
        self.db = db
        self.backupExportLock = backupExportLock
        self.state = AtomicValue(State(), lock: .init())
    }

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

    public func updates() -> AsyncStream<LocalFileBackupExportJobRunnerUpdate?> {
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
        block: @escaping (LocalFileBackupExportJobRunnerUpdate?) -> Void,
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

    public func resumeIfNecessary() -> Task<Void, Error>? {
        let resumptionPoint: LocalFileBackupExportJobStore.ResumptionPoint? = db.read { tx in
            localFileBackupExportJobStore.lastReachedResumptionPoint(tx: tx)
        }

        if let resumptionPoint {
            return _startIfNecessary(
                mode: .manual,
                resumptionPoint: resumptionPoint,
            )
        }
        return nil
    }

    // MARK: -

    public func cancelIfRunning() -> Task<Void, Error>? {
        return state.update { _state in
            _state.currentExportJobTask?.cancel()
            return _state.currentExportJobTask
        }
    }

    // MARK: -

    public func startIfNecessary(mode: LocalFileBackupExportJobMode) -> Task<Void, Error> {
        return _startIfNecessary(mode: mode, resumptionPoint: nil)
    }

    private func _startIfNecessary(
        mode: LocalFileBackupExportJobMode,
        resumptionPoint: LocalFileBackupExportJobStore.ResumptionPoint?,
    ) -> Task<Void, Error> {
        let claim = backupExportLock.tryClaim(asHolder: .local, start: {
            return state.update { [self] _state in
                if let currentExportJobTask = _state.currentExportJobTask {
                    return currentExportJobTask
                }

                let newExportJobTask = Task { [self] () async throws -> Void in
                    let result = await Result(catching: { [self] in
                        let progressSink = OWSSequentialProgress<LocalFileBackupExportJobStage>
                            .createSink { [weak self] exportJobProgress in
                                self?.exportJobDidUpdateProgress(exportJobProgress)
                            }

                        try await localFileBackupExportJob.run(
                            mode: mode,
                            resumptionPoint: resumptionPoint,
                            progress: progressSink,
                        )
                    })

                    backupExportLock.release(holder: .local)
                    exportJobDidComplete(result: result)
                    try result.get()
                }

                _state.currentExportJobTask = newExportJobTask
                return newExportJobTask
            }
        })

        switch claim {
        case .claimed(let task), .alreadyHeld(let task):
            return task
        case .blockedBy:
            return Task { throw BackupExportLockError.remoteBackupInProgress }
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

    private func exportJobDidUpdateProgress(_ exportJobProgress: OWSSequentialProgress<LocalFileBackupExportJobStage>) {
        state.update { [weak self] _state in
            guard let self else { return }

            // Stash this update for our next debounce
            _state.nextProgressUpdate = exportJobProgress
            progressUpdateDebouncer.requestNotify()
        }
    }
}
