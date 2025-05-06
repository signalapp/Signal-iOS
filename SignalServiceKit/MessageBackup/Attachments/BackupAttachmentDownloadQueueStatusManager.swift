//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public enum BackupAttachmentDownloadQueueStatus: Equatable {
    /// Running and downloading attachments off the queue
    case running

    /// There's nothing to download!
    case empty

    /// Must be registered and isAppReady to download.
    case notRegisteredAndReady
    /// Wifi (not cellular) is required to download.
    case noWifiReachability
    /// The device has low battery or is in low power mode.
    case lowBattery
    /// There is not enough disk space to finish downloading.
    /// Note that we require a minimum amount of space and will continue
    /// greedily downloading until this minimum is reached even if we know
    /// ahead of time we will hit the threshold before finishing.
    case lowDiskSpace

    public static let didChangeNotification = Notification.Name(rawValue: "BackupAttachmentDownloadQueueStatusDidChange")
}

/// Observes various inputs that determine whether we are abke to download backup-sourced
/// attachments and emits consolidated status updates.
/// Main actor isolated because most of its inputs are themselves main actor isolated.
@MainActor
public protocol BackupAttachmentDownloadQueueStatusManager {
    func currentStatus() -> BackupAttachmentDownloadQueueStatus

    nonisolated func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64

    /// Re-triggers disk space checks and clears any in-memory state for past disk space errors,
    /// in order to attempt download resumption.
    func reattemptDiskSpaceChecks()
}

@MainActor
/// API just for BackupAttachmentDownloadManager to update the state in this class.
public protocol BackupAttachmentDownloadQueueStatusUpdates: BackupAttachmentDownloadQueueStatusManager {

    /// Check the current state _and_ begin observing state changes if the queue of backup downloads is not empty.
    func beginObservingIfNeeded() -> BackupAttachmentDownloadQueueStatus

    /// Synchronously check remaining disk space.
    /// If there is sufficient space, early exit and return nil.
    /// Otherwise, await a full state update and return the updated status.
    nonisolated func quickCheckDiskSpace() async -> BackupAttachmentDownloadQueueStatus?

    /// Checks if the error should change the status (e.g. out of disk space errors should stop subsequent downloads)
    /// Returns nil if the error has no effect on the status (though note the status may be changed for any other concurrent
    /// reason unrelated to the error).
    nonisolated func downloadDidExperienceError(_ error: Error) async -> BackupAttachmentDownloadQueueStatus?

    /// Call when the QueuedBackupAttachmentRecord table is emptied.
    func didEmptyQueue()
}

@MainActor
public class BackupAttachmentDownloadQueueStatusManagerImpl: BackupAttachmentDownloadQueueStatusUpdates {

    // MARK: - API

    public func currentStatus() -> BackupAttachmentDownloadQueueStatus {
        return state.status
    }

    public nonisolated func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64 {
        return getRequiredDiskSpace()
    }

    public func reattemptDiskSpaceChecks() {
        // Check for disk space available now in case the user freed up space.
        self.availableDiskSpaceMaybeDidChange()
        // Also, if we had experienced an error for some individual download before,
        // clear that now. If our check for disk space says we've got space but then
        // actual downloads fail with a disk space error...this will put us in a
        // loop of attempting over and over when the user acks. But if we don't do
        // this, the user has no (obvious) way to get out of running out of space.
        self.state.downloadDidExperienceOutOfSpaceError = false
    }

    public func beginObservingIfNeeded() -> BackupAttachmentDownloadQueueStatus {
        observeDeviceAndLocalStatesIfNeeded()
        return currentStatus()
    }

    public nonisolated func downloadDidExperienceError(_ error: Error) async -> BackupAttachmentDownloadQueueStatus? {
        // We only care about out of disk space errors.
        guard (error as NSError).code == NSFileWriteOutOfSpaceError else {
            // Return nil to avoid having to thread-hop to the main thread just to get
            // the current status when we know it won't change due to this error.
            return nil
        }
        return await MainActor.run {
            return self.downloadDidExperienceOutOfSpaceError()
        }
    }

    public nonisolated func quickCheckDiskSpace() async -> BackupAttachmentDownloadQueueStatus? {
        let requiredDiskSpace = self.getRequiredDiskSpace()
        if
            let availableDiskSpace = self.getAvailableDiskSpace(),
            availableDiskSpace < requiredDiskSpace
        {
            await self.availableDiskSpaceMaybeDidChange()
            return await self.state.status
        } else {
            return nil
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
    private let db: DB
    private let deviceBatteryLevelManager: (any DeviceBatteryLevelManager)?
    private let reachabilityManager: SSKReachabilityManager
    private nonisolated let remoteConfigManager: RemoteConfigManager
    private let tsAccountManager: TSAccountManager

    init(
        appContext: AppContext,
        appReadiness: AppReadiness,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        db: DB,
        deviceBatteryLevelManager: (any DeviceBatteryLevelManager)?,
        reachabilityManager: SSKReachabilityManager,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) {
        self.appContext = appContext
        self.appReadiness = appReadiness
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.db = db
        self.deviceBatteryLevelManager = deviceBatteryLevelManager
        self.reachabilityManager = reachabilityManager
        self.remoteConfigManager = remoteConfigManager
        self.tsAccountManager = tsAccountManager

        self.state = State(isMainApp: appContext.isMainApp)

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.appReadinessDidChange()
        }
    }

    // MARK: - Private

    private struct State {
        var isQueueEmpty: Bool?
        var isMainApp: Bool
        var isAppReady = false
        var isRegistered: Bool?
        var isWifiReachable: Bool?
        // Value from 0 to 1
        var batteryLevel: Float?
        var isLowPowerMode: Bool?
        // Both in bytes
        var availableDiskSpace: UInt64?
        var requiredDiskSpace: UInt64?
        var downloadDidExperienceOutOfSpaceError = false

        var status: BackupAttachmentDownloadQueueStatus {
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

            guard isWifiReachable == true else {
                return .noWifiReachability
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
            if oldValue.status != state.status {
                fireNotification()
            }
        }
    }

    // MARK: State Observation

    private func observeDeviceAndLocalStatesIfNeeded() {
        let isQueueEmpty = self.isQueueEmpty()
        defer { state.isQueueEmpty = isQueueEmpty }
        if isQueueEmpty, state.isQueueEmpty == false {
            // Stop observing all others
            stopObservingDeviceAndLocalStates()
        } else if !isQueueEmpty, state.isQueueEmpty != false {
            // Start observing all others.
            // We don't want to waste resources (in particular, tell
            // the OS we want battery level updates) unless we have to
            // so only observe if we have things in the queue.
            observeDeviceAndLocalStates()
        }
    }

    private func observeDeviceAndLocalStates() {
        let notificationsToObserve: [(NSNotification.Name, Selector)] = [
            (.registrationStateDidChange, #selector(registrationStateDidChange)),
            (.reachabilityChanged, #selector(reachabilityDidChange)),
            (UIDevice.batteryLevelDidChangeNotification, #selector(batteryLevelDidChange)),
            (Notification.Name.NSProcessInfoPowerStateDidChange, #selector(lowPowerModeDidChange)),
            (.OWSApplicationWillEnterForeground, #selector(willEnterForeground)),
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
            isMainApp: appContext.isMainApp,
            isAppReady: appReadiness.isAppReady,
            isRegistered: tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered,
            isWifiReachable: reachabilityManager.isReachable(via: .wifi),
            batteryLevel: batteryLevelMonitor?.batteryLevel,
            isLowPowerMode: deviceBatteryLevelManager?.isLowPowerModeEnabled,
            availableDiskSpace: getAvailableDiskSpace(),
            requiredDiskSpace: requiredDiskSpace
        )
    }

    private func stopObservingDeviceAndLocalStates() {
        NotificationCenter.default.removeObserver(self)
        batteryLevelMonitor.map { deviceBatteryLevelManager?.endMonitoring($0) }
    }

    // MARK: Per state changes

    private func isQueueEmpty() -> Bool {
        return db.read { tx in
            do {
                return try backupAttachmentDownloadStore.peek(count: 1, tx: tx).isEmpty
            } catch {
                owsFailDebug("Unable to read queue!")
                return true
            }
        }
    }

    private func appReadinessDidChange() {
        self.state.isAppReady = appReadiness.isAppReady
    }

    @objc
    private func registrationStateDidChange() {
        self.state.isRegistered = tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
    }

    @objc
    private func reachabilityDidChange() {
        self.state.isWifiReachable = reachabilityManager.isReachable(via: .wifi)
    }

    private var batteryLevelMonitor: DeviceBatteryLevelMonitor?

    @objc
    private func batteryLevelDidChange() {
        self.state.batteryLevel = batteryLevelMonitor?.batteryLevel
    }

    @objc
    private func lowPowerModeDidChange() {
        self.state.isLowPowerMode = deviceBatteryLevelManager?.isLowPowerModeEnabled
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
        return state.status
    }

    private func fireNotification() {
        NotificationCenter.default.post(
            name: BackupAttachmentDownloadQueueStatus.didChangeNotification,
            object: nil
        )
    }
}
