//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupExportLockError: BGProcessingTaskRescheduleOnCatch {
    case remoteBackupInProgress
    case localBackupInProgress
}

public final class BackupExportLock {
    public enum Holder {
        case remote
        case local
    }

    public enum ClaimResult {
        case alreadyHeld(Task<Void, Error>)
        case blockedBy(Holder)
        case claimed(Task<Void, Error>)
    }

    private struct State {
        var current: (holder: Holder, task: Task<Void, Error>)?
    }

    private let state = AtomicValue(State(), lock: .init())

    public init() {}

    /// Attempt to claim the lock for `holder` to run a backup.
    /// Returns:
    /// - `.claimed(task)`: closure ran and produced a new task
    /// - `.alreadyHeld`: same holder already has a task
    /// - `.blockedBy(holder)`: the other holder is running. Caller decides what to do.
    public func tryClaim(
        asHolder holder: Holder,
        start: () -> Task<Void, Error>,
    ) -> ClaimResult {
        return state.update { state in
            if let current = state.current {
                if current.holder == holder {
                    return .alreadyHeld(current.task)
                } else {
                    return .blockedBy(current.holder)
                }
            }
            let task = start()
            state.current = (holder, task)
            return .claimed(task)
        }
    }

    /// Called when the currently-running job finishes.
    public func release(holder: Holder) {
        state.update { state in
            if state.current?.holder == holder {
                state.current = nil
            }
        }
    }
}
