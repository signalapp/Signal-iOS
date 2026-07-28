//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Responsible for periodically checking the device's available disk space, and
/// taking remedial action if we're running low.
public final class LowDiskSpaceManager {
    private enum Constants {
        /// The minimum available space required to let the app launch.
        static let minBytesAvailableToLaunch: UInt64 = 500 * .megabyte

        /// The minimum available space before we are "critically" low.
        static let minBytesAvailableBeforeCriticallyLow: UInt64 = 400 * .megabyte

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

    private static let logger: PrefixedLogger = PrefixedLogger(prefix: "[DiskSpace]")
    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "LowDiskSpaceWarningManager")
    }

    public static func hasEnoughDiskSpaceToLaunch() -> Bool {
        guard let diskSpace = Self.checkDiskSpace() else {
            // Err on the side of blocking app launch if we're having trouble
            // checking disk space. This should never happen!
            return false
        }

        guard diskSpace.available > Constants.minBytesAvailableToLaunch else {
            logger.warn("Not enough disk space to launch: \(diskSpace.logDescription)")
            return false
        }

        return true
    }

    // MARK: -

    public func isDiskSpaceCriticallyLow() -> Bool {
        if
            let diskSpace = Self.checkDiskSpace(),
            diskSpace.available < Constants.minBytesAvailableBeforeCriticallyLow
        {
            Self.logger.warn("Disk space is dangerously low: \(diskSpace.logDescription)")
            return true
        }

        return false
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

    private struct DiskSpace {
        let total: UInt64
        let available: UInt64

        /// A deliberately coarse, human-readable summary for logging.
        var logDescription: String {
            let availableHundredMBs = available / (100 * .megabyte)
            let totalGBs = total / .gigabyte
            return "\(availableHundredMBs)00 MB / \(totalGBs) GB"
        }
    }

    /// Fetches the device's total capacity and remaining space and logs them.
    private static func checkDiskSpace() -> DiskSpace? {
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
            owsFailDebug("Failed to determine disk space! \(error)", logger: logger)
            return nil
        }
    }
}
