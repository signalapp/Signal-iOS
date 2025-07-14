//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public enum BackupAttachmentDownloadQueueStatus: Equatable {
    /// The queue is running, and attachments are downloading.
    case running

    /// Downloads may be available, but are pending user action to start running.
    case suspended

    /// There's nothing to download.
    case empty

    /// Must be registered and the app ready to download.
    case notRegisteredAndReady
    /// Wifi is required for downloads, but not available.
    case noWifiReachability
    /// Internet access is required for downloads, but not available.
    case noReachability
    /// The device has low battery or is in low power mode.
    case lowBattery
    /// There is not enough disk space to finish downloading.
    /// Note that we require a minimum amount of space and will continue
    /// greedily downloading until this minimum is reached even if we know
    /// ahead of time we will hit the threshold before finishing.
    /// Does not apply to upload.
    case lowDiskSpace
}

public extension Notification.Name {
    static let backupAttachmentDownloadQueueStatusDidChange = Notification.Name(rawValue: "BackupAttachmentDownloadQueueStatusDidChange")
}

// MARK: -

/// Reports whether we are able to download Backup attachments, via various
/// consolidated inputs.
///
/// `@MainActor`-isolated because most of the inputs are themselves isolated.
@MainActor
public protocol BackupAttachmentDownloadQueueStatusReporter {
    func currentStatus() -> BackupAttachmentDownloadQueueStatus

    /// Synchronously returns the minimum required disk space for downloads.
    nonisolated func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64

    /// Re-triggers disk space checks and clears any in-memory state for past disk space errors,
    /// in order to attempt download resumption.
    func reattemptDiskSpaceChecks()
}

extension BackupAttachmentDownloadQueueStatusReporter {
    func notifyStatusDidChange() {
        NotificationCenter.default.postOnMainThread(
            name: .backupAttachmentDownloadQueueStatusDidChange,
            object: nil,
        )
    }
}

// MARK: -

/// API for callers to manage the `StatusReporter` in response to relevant
/// external events.
@MainActor
public protocol BackupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusReporter {

    /// Begin observing status updates, if necessary.
    func beginObservingIfNecessary() -> BackupAttachmentDownloadQueueStatus

    /// Synchronously check remaining disk space.
    /// If there is sufficient space, early exit.
    /// Otherwise, await a full state update.
    nonisolated func quickCheckDiskSpaceForDownloads() async

    /// Checks if the error should change the status (e.g. out of disk space errors should stop subsequent downloads)
    /// Returns nil if the error has no effect on the status (though note the status may be changed for any other concurrent
    /// reason unrelated to the error).
    nonisolated func jobDidExperienceError(_ error: Error) async -> BackupAttachmentDownloadQueueStatus?

    /// Call when the download queue is emptied.
    func didEmptyQueue()
}

// MARK: -

@MainActor
public class BackupAttachmentDownloadQueueStatusManagerImpl: BackupAttachmentDownloadQueueStatusManager {

    // MARK: - BackupAttachmentDownloadQueueStatusReporter

    public func currentStatus() -> BackupAttachmentDownloadQueueStatus {
        return state.asQueueStatus
    }

    public nonisolated func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64 {
        return getRequiredDiskSpace()
    }

    public func reattemptDiskSpaceChecks() {
        // Check for disk space available now in case the user freed up space.
        availableDiskSpaceMaybeDidChange()
        // Also, if we had experienced an error for some individual download before,
        // clear that now. If our check for disk space says we've got space but then
        // actual downloads fail with a disk space error...this will put us in a
        // loop of attempting over and over when the user acks. But if we don't do
        // this, the user has no (obvious) way to get out of running out of space.
        state.downloadDidExperienceOutOfSpaceError = false
    }

    // MARK: - BackupAttachmentDownloadQueueStatusManager

    public func beginObservingIfNecessary() -> BackupAttachmentDownloadQueueStatus {
        observeDeviceAndLocalStatesIfNecessary()
        return currentStatus()
    }

    public nonisolated func jobDidExperienceError(_ error: Error) async -> BackupAttachmentDownloadQueueStatus? {
        // We only care about out of disk space errors for downloads.
        guard (error as NSError).code == NSFileWriteOutOfSpaceError else {
            // Return nil to avoid having to thread-hop to the main thread just to get
            // the current status when we know it won't change due to this error.
            return nil
        }

        return await MainActor.run {
            return downloadDidExperienceOutOfSpaceError()
        }
    }

    public nonisolated func quickCheckDiskSpaceForDownloads() async {
        let requiredDiskSpace = getRequiredDiskSpace()
        if
            let availableDiskSpace = getAvailableDiskSpace(),
            availableDiskSpace < requiredDiskSpace
        {
            await availableDiskSpaceMaybeDidChange()
        }
    }

    public func didEmptyQueue() {
        state.isQueueEmpty = true
        stopObservingDeviceAndLocalStates()
    }

    // MARK: - Init

    private let appContext: AppContext
    private let appReadiness: AppReadiness
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private var batteryLevelMonitor: DeviceBatteryLevelMonitor?
    private let dateProvider: DateProvider
    private let db: DB
    private let deviceBatteryLevelManager: (any DeviceBatteryLevelManager)?
    private let reachabilityManager: SSKReachabilityManager
    private nonisolated let remoteConfigManager: RemoteConfigManager
    private let tsAccountManager: TSAccountManager

    init(
        appContext: AppContext,
        appReadiness: AppReadiness,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        deviceBatteryLevelManager: (any DeviceBatteryLevelManager)?,
        reachabilityManager: SSKReachabilityManager,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) {
        self.appContext = appContext
        self.appReadiness = appReadiness
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.deviceBatteryLevelManager = deviceBatteryLevelManager
        self.reachabilityManager = reachabilityManager
        self.remoteConfigManager = remoteConfigManager
        self.tsAccountManager = tsAccountManager

        self.state = State(
            isQueueEmpty: nil,
            areDownloadsSuspended: nil,
            isMainApp: appContext.isMainApp,
            isAppReady: false,
            isRegistered: nil,
            shouldAllowBackupDownloadsOnCellular: nil,
            isWifiReachable: nil,
            isReachable: nil,
            batteryLevel: nil,
            isLowPowerMode: nil,
            availableDiskSpace: nil,
            requiredDiskSpace: nil,
            downloadDidExperienceOutOfSpaceError: false
        )

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.appReadinessDidChange()
        }
    }

    // MARK: - Private

    private struct State {
        var isQueueEmpty: Bool?
        var areDownloadsSuspended: Bool?

        var isMainApp: Bool
        var isAppReady: Bool
        var isRegistered: Bool?

        var shouldAllowBackupDownloadsOnCellular: Bool?
        var isWifiReachable: Bool?
        var isReachable: Bool?

        // Value from 0 to 1
        var batteryLevel: Float?
        var isLowPowerMode: Bool?

        // Both in bytes
        var availableDiskSpace: UInt64?
        var requiredDiskSpace: UInt64?
        var downloadDidExperienceOutOfSpaceError: Bool

        init(
            isQueueEmpty: Bool?,
            areDownloadsSuspended: Bool?,
            isMainApp: Bool,
            isAppReady: Bool,
            isRegistered: Bool?,
            shouldAllowBackupDownloadsOnCellular: Bool?,
            isWifiReachable: Bool?,
            isReachable: Bool?,
            batteryLevel: Float?,
            isLowPowerMode: Bool?,
            availableDiskSpace: UInt64?,
            requiredDiskSpace: UInt64?,
            downloadDidExperienceOutOfSpaceError: Bool,
        ) {
            self.isQueueEmpty = isQueueEmpty
            self.areDownloadsSuspended = areDownloadsSuspended
            self.isMainApp = isMainApp
            self.isAppReady = isAppReady
            self.isRegistered = isRegistered
            self.shouldAllowBackupDownloadsOnCellular = shouldAllowBackupDownloadsOnCellular
            self.isWifiReachable = isWifiReachable
            self.isReachable = isReachable
            self.batteryLevel = batteryLevel
            self.isLowPowerMode = isLowPowerMode
            self.availableDiskSpace = availableDiskSpace
            self.requiredDiskSpace = requiredDiskSpace
            self.downloadDidExperienceOutOfSpaceError = downloadDidExperienceOutOfSpaceError
        }

        var asQueueStatus: BackupAttachmentDownloadQueueStatus {
            if isQueueEmpty == true {
                return .empty
            }

            guard
                isMainApp,
                isAppReady,
                isRegistered == true
            else {
                return .notRegisteredAndReady
            }

            if areDownloadsSuspended == true {
                return .suspended
            }

            if downloadDidExperienceOutOfSpaceError {
                return .lowDiskSpace
            }

            if
                let availableDiskSpace,
                let requiredDiskSpace,
                availableDiskSpace < requiredDiskSpace
            {
                return .lowDiskSpace
            }

            if
                shouldAllowBackupDownloadsOnCellular != true,
                isWifiReachable != true
            {
                return .noWifiReachability
            }

            if isReachable != true {
                return .noReachability
            }

            if let batteryLevel, batteryLevel < 0.1 {
                return .lowBattery
            }

            if isLowPowerMode == true {
                return .lowBattery
            }

            return .running
        }
    }

    private var state: State {
        didSet {
            if oldValue.asQueueStatus != state.asQueueStatus {
                notifyStatusDidChange()
            }
        }
    }

    // MARK: State Observation

    private func observeDeviceAndLocalStatesIfNecessary() {
        // For change logic, treat nil as empty (if nil, observation is unstarted)
        let wasQueueEmpty = state.isQueueEmpty ?? true

        let (isQueueEmpty, areDownloadsSuspended) = db.read { tx in
            return (
                (try? backupAttachmentDownloadStore.hasAnyReadyDownloads(tx: tx))?.negated ?? true,
                backupSettingsStore.isBackupAttachmentDownloadQueueSuspended(tx: tx)
            )

        }
        state.isQueueEmpty = isQueueEmpty
        state.areDownloadsSuspended = areDownloadsSuspended

        // Only observe if the queue is non-empty, so as to not waste resources;
        // for example, by telling the OS we want battery level updates.
        if isQueueEmpty, !wasQueueEmpty {
            stopObservingDeviceAndLocalStates()
        } else if !isQueueEmpty, wasQueueEmpty {
            observeDeviceAndLocalStates()
        }
    }

    private func observeDeviceAndLocalStates() {
        let (isRegistered, shouldAllowBackupDownloadsOnCellular) = db.read { tx in
            return (
                tsAccountManager.registrationState(tx: tx).isRegistered,
                backupSettingsStore.shouldAllowBackupDownloadsOnCellular(tx: tx)
            )
        }

        let notificationsToObserve: [(Notification.Name, Selector)] = [
            (.registrationStateDidChange, #selector(registrationStateDidChange)),
            (.reachabilityChanged, #selector(reachabilityDidChange)),
            (UIDevice.batteryLevelDidChangeNotification, #selector(batteryLevelDidChange)),
            (Notification.Name.NSProcessInfoPowerStateDidChange, #selector(lowPowerModeDidChange)),
            (.OWSApplicationWillEnterForeground, #selector(willEnterForeground)),
            (.backupAttachmentDownloadQueueSuspensionStatusDidChange, #selector(suspensionStatusDidChange)),
            (.shouldAllowBackupDownloadsOnCellularChanged, #selector(shouldAllowBackupDownloadsOnCellularDidChange)),
        ]
        for (name, selector) in notificationsToObserve {
            NotificationCenter.default.addObserver(
                self,
                selector: selector,
                name: name,
                object: nil
            )
        }

        // Don't worry about this changing during an app lifetime; just check it once up front.
        let requiredDiskSpace = getRequiredDiskSpace()

        self.batteryLevelMonitor = deviceBatteryLevelManager?.beginMonitoring(reason: "BackupDownloadQueue")
        self.state = State(
            isQueueEmpty: state.isQueueEmpty,
            areDownloadsSuspended: state.areDownloadsSuspended,
            isMainApp: appContext.isMainApp,
            isAppReady: appReadiness.isAppReady,
            isRegistered: isRegistered,
            shouldAllowBackupDownloadsOnCellular: shouldAllowBackupDownloadsOnCellular,
            isWifiReachable: reachabilityManager.isReachable(via: .wifi),
            isReachable: reachabilityManager.isReachable(via: .any),
            batteryLevel: batteryLevelMonitor?.batteryLevel,
            isLowPowerMode: deviceBatteryLevelManager?.isLowPowerModeEnabled,
            availableDiskSpace: getAvailableDiskSpace(),
            requiredDiskSpace: requiredDiskSpace,
            downloadDidExperienceOutOfSpaceError: state.downloadDidExperienceOutOfSpaceError
        )
    }

    private func stopObservingDeviceAndLocalStates() {
        NotificationCenter.default.removeObserver(self)
        batteryLevelMonitor.map { deviceBatteryLevelManager?.endMonitoring($0) }
    }

    // MARK: Per state changes

    private func appReadinessDidChange() {
        state.isAppReady = appReadiness.isAppReady
    }

    @objc
    private func registrationStateDidChange() {
        state.isRegistered = db.read { tx in
            tsAccountManager.registrationState(tx: tx) .isRegistered
        }
    }

    @objc
    private func reachabilityDidChange() {
        state.isWifiReachable = reachabilityManager.isReachable(via: .wifi)
        state.isReachable = reachabilityManager.isReachable(via: .any)
    }

    @objc
    private func batteryLevelDidChange() {
        state.batteryLevel = batteryLevelMonitor?.batteryLevel
    }

    @objc
    private func lowPowerModeDidChange() {
        state.isLowPowerMode = deviceBatteryLevelManager?.isLowPowerModeEnabled
    }

    @objc
    private func suspensionStatusDidChange() {
        state.areDownloadsSuspended = db.read { tx in
            backupSettingsStore.isBackupAttachmentDownloadQueueSuspended(tx: tx)
        }
    }

    @objc
    private func shouldAllowBackupDownloadsOnCellularDidChange() {
        state.shouldAllowBackupDownloadsOnCellular = db.read { tx in
            backupSettingsStore.shouldAllowBackupDownloadsOnCellular(tx: tx)
        }
    }

    private nonisolated func getAvailableDiskSpace() -> UInt64? {
        do {
            OWSFileSystem.ensureDirectoryExists(AttachmentStream.attachmentsDirectory().path)
            return try OWSFileSystem.freeSpaceInBytes(
                forPath: AttachmentStream.attachmentsDirectory()
            )
        } catch {
            owsFailDebug("Unable to determine disk space \(error)")
            return nil
        }
    }

    private nonisolated func getRequiredDiskSpace() -> UInt64 {
        return UInt64(remoteConfigManager.currentConfig().maxAttachmentDownloadSizeBytes) * 5
    }

    @objc
    private func availableDiskSpaceMaybeDidChange() {
        state.availableDiskSpace = getAvailableDiskSpace()
    }

    @objc
    private func willEnterForeground() {
        // Besides errors we get when writing downloaded attachment files to disk,
        // there isn't a good trigger for available disk space changes (and it
        // would be overkill to learn about every byte, anyway). Just check
        // when the app is foregrounded, so we can be proactive about stopping
        // downloads before we use up the last sliver of disk space.
        availableDiskSpaceMaybeDidChange()
    }

    private func downloadDidExperienceOutOfSpaceError() -> BackupAttachmentDownloadQueueStatus {
        state.downloadDidExperienceOutOfSpaceError = true
        return state.asQueueStatus
    }
}

// MARK: -

#if TESTABLE_BUILD

class MockBackupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager {
    var currentStatusMock: BackupAttachmentDownloadQueueStatus?
    func currentStatus() -> BackupAttachmentDownloadQueueStatus {
        currentStatusMock ?? .empty
    }

    func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64 {
        0
    }

    func reattemptDiskSpaceChecks() {
        // Nothing
    }

    func beginObservingIfNecessary() -> BackupAttachmentDownloadQueueStatus {
        return currentStatus()
    }

    func quickCheckDiskSpaceForDownloads() async {
        // Nothing
    }

    func jobDidExperienceError(_ error: any Error) async -> BackupAttachmentDownloadQueueStatus? {
        return nil
    }

    func didEmptyQueue() {
        // Nothing
    }
}

#endif
