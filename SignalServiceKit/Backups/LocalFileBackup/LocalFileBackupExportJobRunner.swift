//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A wrapper around ``LocalFileBackupExportJob`` that prevents overlapping job runs and
/// tracks progress updates for the currently-running job.
public protocol LocalFileBackupExportJobRunner {

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
        var currentExportJobTask: Task<Void, Error>?
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

                let newExportJobTask = Task { () async throws -> Void in
                    let result = await Result(catching: {
                        try await localFileBackupExportJob.run(
                            mode: mode,
                            resumptionPoint: resumptionPoint,
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
        }
    }
}
