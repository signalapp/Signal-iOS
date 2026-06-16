//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Responsible for periodically checking the device's available disk space, and
/// taking remedial action if we're running low.
public final class LowDiskSpaceWarningManager {
    private enum Constants {
        /// The minimum available space required to let the app launch.
        static let minBytesAvailableToLaunch: UInt64 = 500 * .megabyte
        /// The minimum available space required to let the running app continue
        /// to run.
        static let minBytesAvailableToContinueRunning: UInt64 = 400 * .megabyte
        /// The minimum availabe space required before we'll show a warning.
        static func minBytesAvailableBeforeWarning(totalBytes: UInt64) -> UInt64 {
            let percentageThreshold = UInt64(clamping: Double(totalBytes) * 0.05)
            let absoluteThreshold = 2 * .gigabyte

            // Warn at 2GB, or 5% of total storage (as 2GB may be too high for
            // low-total-space devices).
            return min(percentageThreshold, absoluteThreshold)
        }
    }

    private enum StoreKeys {
        static let lastWarningDate = "lastWarningDate"
    }

    private struct State {
        var diskSpaceCheckTask: Task<Void, Never>?
    }

    private static let logger: PrefixedLogger = PrefixedLogger(prefix: "[DiskSpace]")

    private let db: DB
    private let kvStore: NewKeyValueStore

    private let diskSpaceCheckInterval: TimeInterval
    private let state: AtomicValue<State>

    public init(
        db: DB,
        diskSpaceCheckInterval: TimeInterval = 5 * .second,
    ) {
        self.db = db
        self.kvStore = NewKeyValueStore(collection: "LowDiskSpaceWarningManager")

        self.diskSpaceCheckInterval = diskSpaceCheckInterval
        self.state = AtomicValue(State(), lock: .init())
    }

    public static func hasEnoughDiskSpaceToLaunch() -> Bool {
        guard let diskSpace = Self.checkDiskSpace() else {
            // Err on the side of blocking app launch if we're having trouble
            // checking disk space. This should never happen!
            return false
        }

        return diskSpace.available > Constants.minBytesAvailableToLaunch
    }

    // MARK: -

    public func getNeedsWarning(now: Date, tx: DBReadTransaction) -> Bool {
        guard let diskSpace = Self.checkDiskSpace() else {
            return false
        }

        if
            let lastWarningDate = kvStore.fetchValue(Date.self, forKey: StoreKeys.lastWarningDate, tx: tx),
            now < lastWarningDate.addingTimeInterval(3 * .day)
        {
            return false
        }

        let minBytesWarningThreshold = Constants.minBytesAvailableBeforeWarning(totalBytes: diskSpace.total)
        return diskSpace.available < minBytesWarningThreshold
    }

    public func setShowedWarning(now: Date, tx: DBWriteTransaction) {
        kvStore.writeValue(now, forKey: StoreKeys.lastWarningDate, tx: tx)
    }

    // MARK: -

    public func startMonitoringDiskSpace() {
        state.update {
            $0.diskSpaceCheckTask = $0.diskSpaceCheckTask ?? Task {
                await continuouslyMonitorDiskSpace()
            }
        }
    }

    public func stopMonitoringDiskSpace() {
        state.update {
            $0.diskSpaceCheckTask.take()?.cancel()
        }
    }

    // MARK: -

    private struct DiskSpace {
        let total: UInt64
        let available: UInt64
    }

    private func continuouslyMonitorDiskSpace() async {
        while true {
            if
                let diskSpace = Self.checkDiskSpace(),
                diskSpace.available < Constants.minBytesAvailableToContinueRunning
            {
                let availableHundredMBs = diskSpace.available / (100 * .megabyte)
                let totalGBs = diskSpace.total / .gigabyte
                owsFail(
                    "Disk space is dangerously low: crashing. \(availableHundredMBs)00 MB / \(totalGBs) GB",
                    logger: Self.logger,
                )
            }

            do {
                try await Task.sleep(nanoseconds: diskSpaceCheckInterval.clampedNanoseconds)
            } catch {
                return
            }
        }
    }

    /// Fetches the device's total capacity and remaining space and logs them.
    private static func checkDiskSpace(
        function: String = #function,
        line: Int = #line,
    ) -> DiskSpace? {
        // Check the volume that holds the database, matching the on-launch check
        // in `AppDelegate.checkEnoughDiskSpaceAvailable()`.
        let path = SDSDatabaseStorage.grdbDatabaseFileUrl
        do {
            let totalBytes = try OWSFileSystem.totalSpaceInBytes(forPath: path)
            let availableBytes = try OWSFileSystem.freeSpaceInBytes(forPath: path)

            return DiskSpace(
                total: totalBytes,
                available: availableBytes,
            )
        } catch {
            owsFailDebug(
                "Failed to determine disk space! \(error)",
                logger: logger,
                function: function,
                line: line,
            )
            return nil
        }
    }
}
