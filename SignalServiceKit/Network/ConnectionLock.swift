//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct ConnectionLock {
    /// Byte offsets in this file are locked as follows:
    /// - Byte 0: The connection lock.
    /// - Bytes 1...(N-1): A lock indicating the process with priority N wants
    /// the connection lock. (The byte for the lowest priority process (i.e.,
    /// priority == priorityCount) isn't locked because it's not contested.)
    private let fileLock: Result<FileLock, POSIXError>
    private let priority: Int
    private let priorityCount: Int

    init(filePath: String, priority: Int, of priorityCount: Int) {
        self.fileLock = Result(catching: { () throws(POSIXError) in
            return try FileLock(filePath: filePath)
        })
        self.priority = priority
        self.priorityCount = priorityCount
    }

    func close() {
        try? self.fileLock.get().close()
    }

    struct HeldLock {
        fileprivate var observerToken: DarwinNotificationCenter.ObserverToken?
    }

    /// Acquires a cross-process lock for this process.
    ///
    /// When a more important (i.e., lower priority number) process requests a
    /// lock, less important processes are notified (via `onInterrupt`) and are
    /// expected to quickly release the lock.
    ///
    /// - Throws: A POSIXError or a CancellationError
    func lock(onInterrupt: (queue: DispatchQueue, callback: () -> Void)) async throws -> HeldLock {
        let fileLock = try self.fileLock.get()

        var observerToken: DarwinNotificationCenter.ObserverToken?

        defer {
            if let observerToken {
                DarwinNotificationCenter.removeObserver(observerToken)
            }
        }

        // If we're not the most important, listen for interruptions & make sure
        // we're not racing with a more important process.
        if self.priority > 1 {
            observerToken = DarwinNotificationCenter.addObserver(
                name: .connectionLock(for: self.priority),
                queue: onInterrupt.queue,
                block: { _ in onInterrupt.callback() }
            )
            // More important processes hold this lock from BEFORE they post a
            // notification until AFTER they've acquired the connection lock. By
            // immediately locking & unlocking, we either run before they acquire this
            // lock (and will observe the notification they send) or strictly after
            // they acquire this lock (and will fail to acquire the connection lock).
            try await fileLock.lockWithCancellationHandler(range: 1..<self.priority)
            do throws(POSIXError) {
                try fileLock.unlock(range: 1..<self.priority)
            } catch {
                owsFail("Must be able to unlock held lock.")
            }
        }

        // If we're more important than some other process, make sure that process
        // doesn't miss our notification to disconnect. (See above comment.)
        if self.priority < self.priorityCount {
            try await fileLock.lock(at: self.priority)
            for lessImportantPriority in (self.priority + 1)...self.priorityCount {
                DarwinNotificationCenter.postNotification(name: .connectionLock(for: lessImportantPriority))
            }
        }
        defer {
            if self.priority < self.priorityCount {
                do throws(POSIXError) {
                    try fileLock.unlock(at: self.priority)
                } catch {
                    owsFail("Must be able to unlock held lock.")
                }
            }
        }

        try await fileLock.lockWithCancellationHandler(at: 0)

        let result = HeldLock(observerToken: observerToken)
        observerToken = nil
        return result
    }

    func unlock(_ heldLock: HeldLock) {
        if let observerToken = heldLock.observerToken {
            DarwinNotificationCenter.removeObserver(observerToken)
        }
        do throws(POSIXError) {
            try fileLock.get().unlock(at: 0)
        } catch {
            owsFail("Must be able to unlock held lock.")
        }
    }
}

private struct FileLock {
    private let fd: Int32

    init(filePath: String) throws(POSIXError) {
        let result = open(filePath, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        guard result > 0 else {
            throw errorForErrno()
        }
        self.fd = result
    }

    func close() {
        _ = unistd.close(self.fd)
    }

    /// See `man fcntl`.
    private func fcntl(range: Range<Int>, shouldLock: Bool, shouldBlock: Bool) -> Result<Void, POSIXError> {
        owsPrecondition(shouldLock || !shouldBlock)
        var req = flock()
        req.l_start = off_t(range.lowerBound)
        req.l_len = off_t(range.upperBound - range.lowerBound)
        req.l_whence = Int16(SEEK_SET)
        req.l_type = Int16(shouldLock ? F_WRLCK : F_UNLCK)
        let result = Darwin.fcntl(self.fd, shouldBlock ? F_SETLKW : F_SETLK, &req)
        if result == -1 {
            return .failure(errorForErrno())
        }
        return .success(())
    }

    func lock(at offset: Int) async throws(POSIXError) {
        try await self.lock(range: offset..<(offset + 1))
    }

    func lock(range: Range<Int>) async throws(POSIXError) {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, POSIXError>, Never>) in
            // We're going to block, so don't block the cooperative thread pool.
            DispatchQueue.global().async {
                continuation.resume(returning: self.fcntl(range: range, shouldLock: true, shouldBlock: true))
            }
        }.get()
    }

    func lockWithCancellationHandler(at offset: Int, maxAveragePollingInterval: TimeInterval = 3) async throws {
        try await self.lockWithCancellationHandler(range: offset..<(offset + 1), maxAveragePollingInterval: maxAveragePollingInterval)
    }

    func lockWithCancellationHandler(range: Range<Int>, maxAveragePollingInterval: TimeInterval = 3) async throws {
        // In most cases, we don't expect contention. But it is possible, and we
        // want to remain cancellable during times of contention, so we poll.
        try await Retry.performWithBackoff(
            maxAttempts: .max,
            minAverageBackoff: 0.1,
            maxAverageBackoff: maxAveragePollingInterval,
            isRetryable: { $0.code == .EAGAIN },
            block: { () throws(POSIXError) in
                try self.tryLock(range: range)
            },
        )
    }

    func tryLock(at offset: Int) throws(POSIXError) {
        try self.tryLock(range: offset..<(offset + 1))
    }

    func tryLock(range: Range<Int>) throws(POSIXError) {
        try self.fcntl(range: range, shouldLock: true, shouldBlock: false).get()
    }

    func unlock(at offset: Int) throws(POSIXError) {
        try self.unlock(range: offset..<(offset + 1))
    }

    func unlock(range: Range<Int>) throws(POSIXError) {
        try self.fcntl(range: range, shouldLock: false, shouldBlock: false).get()
    }
}

private func errorForErrno() -> POSIXError {
    return POSIXError(POSIXErrorCode(rawValue: errno)!)
}
