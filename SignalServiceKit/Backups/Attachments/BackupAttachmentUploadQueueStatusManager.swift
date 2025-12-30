//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupAttachmentUploadQueueMode {
    case fullsize
    case thumbnail
}

public enum BackupAttachmentUploadQueueStatus {
    /// The queue is running, and attachment are uploading.
    case running

    /// The queue was paused by the user.
    case suspended

    /// There's nothing to upload.
    case empty

    /// Must be registered and the app ready to upload.
    case notRegisteredAndReady
    /// Wifi is required for uploads, but not available.
    case noWifiReachability
    /// Internet access is required for uploads, but not available.
    case noReachability
    /// The device has low battery.
    case lowBattery
    /// The device is in low power mode.
    case lowPowerMode
    /// The app is running in the background.
    case appBackgrounded
    /// Out of space on media tier; uploads suspended until we can free space.
    case hasConsumedMediaTierCapacity
}

public extension Notification.Name {
    static func backupAttachmentUploadQueueStatusDidChange(for mode: BackupAttachmentUploadQueueMode) -> Notification.Name {
        switch mode {
        case .fullsize:
            return Notification.Name(rawValue: "BackupAttachmentUploadQueueStatusDidChange_fullsize")
        case .thumbnail:
            return Notification.Name(rawValue: "BackupAttachmentUploadQueueStatusDidChange_thumbnail")
        }
    }
}

// MARK: -

/// Reports whether we are able to upload Backup attachments, via various
/// consolidated inputs.
///
/// `@MainActor`-isolated because most of the inputs are themselves isolated.
@MainActor
public protocol BackupAttachmentUploadQueueStatusReporter {
    func currentStatus(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus
}

extension BackupAttachmentUploadQueueStatusReporter {
    fileprivate func notifyStatusDidChange(for mode: BackupAttachmentUploadQueueMode) {
        NotificationCenter.default.postOnMainThread(
            name: .backupAttachmentUploadQueueStatusDidChange(for: mode),
            object: nil,
        )
    }
}

// MARK: -

/// API for callers to manage the `StatusReporter` in response to relevant
/// external events.
@MainActor
protocol BackupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusReporter {

    /// Begin observing status updates, if necessary.
    func beginObservingIfNecessary(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus

    /// Notifies the status manager that the upload queue was emptied.
    func didEmptyQueue(for mode: BackupAttachmentUploadQueueMode)

    func setIsMainAppAndActiveOverride(_ newValue: Bool)
}

// MARK: -

@MainActor
public class BackupAttachmentUploadQueueStatusManagerImpl: BackupAttachmentUploadQueueStatusManager {

    // MARK: - BackupAttachmentUploadQueueStatusReporter

    public func currentStatus(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus {
        return state.asQueueStatus(for: mode)
    }

    // MARK: - BackupAttachmentUploadQueueStatusManager

    public func beginObservingIfNecessary(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus {
        observeDeviceAndLocalStatesIfNecessary()
        return currentStatus(for: mode)
    }

    public func didEmptyQueue(for mode: BackupAttachmentUploadQueueMode) {
        switch mode {
        case .fullsize:
            state.isFullsizeQueueEmpty = true
        case .thumbnail:
            state.isThumbnailQueueEmpty = true
        }
        if state.isFullsizeQueueEmpty == true, state.isThumbnailQueueEmpty == true {
            stopObservingDeviceAndLocalStates()
        }
    }

    public func setIsMainAppAndActiveOverride(_ newValue: Bool) {
        state.isMainAppAndActiveOverride = newValue
    }

    // MARK: - Init

    private let appContext: AppContext
    private let appReadiness: AppReadiness
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
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
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        deviceBatteryLevelManager: (any DeviceBatteryLevelManager)?,
        reachabilityManager: SSKReachabilityManager,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.appContext = appContext
        self.appReadiness = appReadiness
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.deviceBatteryLevelManager = deviceBatteryLevelManager
        self.reachabilityManager = reachabilityManager
        self.remoteConfigManager = remoteConfigManager
        self.tsAccountManager = tsAccountManager

        self.state = State(
            isFullsizeQueueEmpty: nil,
            isThumbnailQueueEmpty: nil,
            isMainApp: appContext.isMainApp,
            isAppReady: false,
            isRegistered: nil,
            backupPlan: nil,
            hasConsumedMediaTierCapacity: nil,
            shouldAllowBackupUploadsOnCellular: nil,
            isWifiReachable: nil,
            isReachable: nil,
            batteryLevel: nil,
            isLowPowerMode: nil,
            isMainAppAndActive: appContext.isMainAppAndActive,
            areUploadsSuspended: false,
        )

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.appReadinessDidChange()
        }
    }

    // MARK: - Private

    private struct State {
        var isFullsizeQueueEmpty: Bool?
        var isThumbnailQueueEmpty: Bool?

        var isMainApp: Bool
        var isAppReady: Bool
        var isRegistered: Bool?

        var backupPlan: BackupPlan?

        var hasConsumedMediaTierCapacity: Bool?

        var shouldAllowBackupUploadsOnCellular: Bool?
        var isWifiReachable: Bool?
        var isReachable: Bool?
        var areUploadsSuspended: Bool?

        // Value from 0 to 1
        var batteryLevel: Float?
        var isLowPowerMode: Bool?

        var isMainAppAndActive: Bool
        var isMainAppAndActiveOverride: Bool = false

        init(
            isFullsizeQueueEmpty: Bool?,
            isThumbnailQueueEmpty: Bool?,
            isMainApp: Bool,
            isAppReady: Bool,
            isRegistered: Bool?,
            backupPlan: BackupPlan?,
            hasConsumedMediaTierCapacity: Bool?,
            shouldAllowBackupUploadsOnCellular: Bool?,
            isWifiReachable: Bool?,
            isReachable: Bool?,
            batteryLevel: Float?,
            isLowPowerMode: Bool?,
            isMainAppAndActive: Bool,
            areUploadsSuspended: Bool?,
        ) {
            self.isFullsizeQueueEmpty = isFullsizeQueueEmpty
            self.isThumbnailQueueEmpty = isThumbnailQueueEmpty
            self.isMainApp = isMainApp
            self.isAppReady = isAppReady
            self.isRegistered = isRegistered
            self.backupPlan = backupPlan
            self.hasConsumedMediaTierCapacity = hasConsumedMediaTierCapacity
            self.shouldAllowBackupUploadsOnCellular = shouldAllowBackupUploadsOnCellular
            self.isWifiReachable = isWifiReachable
            self.isReachable = isReachable
            self.batteryLevel = batteryLevel
            self.isLowPowerMode = isLowPowerMode
            self.isMainAppAndActive = isMainAppAndActive
            self.areUploadsSuspended = areUploadsSuspended
        }

        func asQueueStatus(for mode: BackupAttachmentUploadQueueMode) -> BackupAttachmentUploadQueueStatus {
            switch mode {
            case .fullsize:
                if isFullsizeQueueEmpty == true {
                    return .empty
                }
            case .thumbnail:
                if isThumbnailQueueEmpty == true {
                    return .empty
                }
            }

            switch backupPlan {
            case nil, .disabled, .disabling, .free:
                return .empty
            case .paid, .paidExpiringSoon, .paidAsTester:
                break
            }

            guard
                isMainApp,
                isAppReady,
                isRegistered == true
            else {
                return .notRegisteredAndReady
            }

            if hasConsumedMediaTierCapacity == true {
                return .hasConsumedMediaTierCapacity
            }

            if areUploadsSuspended == true {
                return .suspended
            }

            if
                shouldAllowBackupUploadsOnCellular != true,
                isWifiReachable != true
            {
                return .noWifiReachability
            }

            if isReachable != true {
                return .noReachability
            }

            if (batteryLevel ?? 0) < 0.1 {
                return .lowBattery
            }

            if isLowPowerMode == true {
                return .lowPowerMode
            }

            if !isMainAppAndActive, !isMainAppAndActiveOverride {
                return .appBackgrounded
            }

            return .running
        }
    }

    private var state: State {
        didSet {
            if oldValue.asQueueStatus(for: .fullsize) != state.asQueueStatus(for: .fullsize) {
                notifyStatusDidChange(for: .fullsize)
            }
            if oldValue.asQueueStatus(for: .thumbnail) != state.asQueueStatus(for: .thumbnail) {
                notifyStatusDidChange(for: .thumbnail)
            }
        }
    }

    // MARK: State Observation

    private func observeDeviceAndLocalStatesIfNecessary() {
        // For change logic, treat nil as empty (if nil, observation is unstarted)
        let wasQueueEmpty: Bool
        if
            let wasFullsizeQueueEmpty = state.isFullsizeQueueEmpty,
            let wasThumbnailQueueEmpty = state.isThumbnailQueueEmpty
        {
            wasQueueEmpty = wasFullsizeQueueEmpty && wasThumbnailQueueEmpty
        } else {
            wasQueueEmpty = true
        }

        let (isFullsizeQueueEmpty, isThumbnailQueueEmpty) = db.read { tx in
            return (
                ((try? backupAttachmentUploadStore.fetchNextUploads(count: 1, isFullsize: true, tx: tx)) ?? []).isEmpty,
                ((try? backupAttachmentUploadStore.fetchNextUploads(count: 1, isFullsize: false, tx: tx)) ?? []).isEmpty,
            )
        }
        state.isFullsizeQueueEmpty = isFullsizeQueueEmpty
        state.isThumbnailQueueEmpty = isThumbnailQueueEmpty
        let isQueueEmpty = isFullsizeQueueEmpty && isThumbnailQueueEmpty

        // Only observe if the queue is non-empty, so as to not waste resources;
        // for example, by telling the OS we want battery level updates.
        if isQueueEmpty, !wasQueueEmpty {
            stopObservingDeviceAndLocalStates()
        } else if !isQueueEmpty, wasQueueEmpty {
            observeDeviceAndLocalStates()
        }
    }

    private func observeDeviceAndLocalStates() {
        let (
            backupPlan,
            hasConsumedMediaTierCapacity,
            shouldAllowBackupUploadsOnCellular,
            areUploadsSuspended,
        ) = db.read { tx in
            (
                backupSettingsStore.backupPlan(tx: tx),
                backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx),
                backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx),
                backupSettingsStore.isBackupAttachmentUploadQueueSuspended(tx: tx),
            )
        }

        let notificationsToObserve: [(Notification.Name, Selector)] = [
            (.registrationStateDidChange, #selector(registrationStateDidChange)),
            (.backupPlanChanged, #selector(backupPlanDidChange)),
            (.hasConsumedMediaTierCapacityStatusDidChange, #selector(hasConsumedMediaTierCapacityDidChange)),
            (.shouldAllowBackupUploadsOnCellularChanged, #selector(shouldAllowBackupUploadsOnCellularDidChange)),
            (.reachabilityChanged, #selector(reachabilityDidChange)),
            (.backupAttachmentUploadQueueSuspensionStatusDidChange, #selector(suspensionStatusDidChange)),
            (.batteryLevelChanged, #selector(batteryLevelDidChange)),
            (.batteryLowPowerModeChanged, #selector(lowPowerModeDidChange)),
            (.OWSApplicationDidEnterBackground, #selector(isMainAppAndActiveDidChange)),
            (.OWSApplicationDidBecomeActive, #selector(isMainAppAndActiveDidChange)),
        ]
        for (name, selector) in notificationsToObserve {
            NotificationCenter.default.addObserver(
                self,
                selector: selector,
                name: name,
                object: nil,
            )
        }

        self.batteryLevelMonitor = deviceBatteryLevelManager?.beginMonitoring(reason: "BackupDownloadQueue")
        self.state = State(
            isFullsizeQueueEmpty: state.isFullsizeQueueEmpty,
            isThumbnailQueueEmpty: state.isThumbnailQueueEmpty,
            isMainApp: appContext.isMainApp,
            isAppReady: appReadiness.isAppReady,
            isRegistered: tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered,
            backupPlan: backupPlan,
            hasConsumedMediaTierCapacity: hasConsumedMediaTierCapacity,
            shouldAllowBackupUploadsOnCellular: shouldAllowBackupUploadsOnCellular,
            isWifiReachable: reachabilityManager.isReachable(via: .wifi),
            isReachable: reachabilityManager.isReachable(via: .any),
            batteryLevel: batteryLevelMonitor?.batteryLevel,
            isLowPowerMode: deviceBatteryLevelManager?.isLowPowerModeEnabled,
            isMainAppAndActive: appContext.isMainAppAndActive,
            areUploadsSuspended: areUploadsSuspended,
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
            tsAccountManager.registrationState(tx: tx).isRegistered
        }
    }

    @objc
    private func backupPlanDidChange() {
        state.backupPlan = db.read { tx in
            backupSettingsStore.backupPlan(tx: tx)
        }
    }

    @objc
    private func hasConsumedMediaTierCapacityDidChange() {
        state.hasConsumedMediaTierCapacity = db.read { tx in
            backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx)
        }
    }

    @objc
    private func shouldAllowBackupUploadsOnCellularDidChange() {
        state.shouldAllowBackupUploadsOnCellular = db.read { tx in
            backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx)
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
        self.state.isLowPowerMode = deviceBatteryLevelManager?.isLowPowerModeEnabled
    }

    @objc
    private func isMainAppAndActiveDidChange() {
        self.state.isMainAppAndActive = appContext.isMainAppAndActive
    }

    @objc
    public func suspensionStatusDidChange() {
        self.state.areUploadsSuspended = db.read { tx in
            backupSettingsStore.isBackupAttachmentUploadQueueSuspended(tx: tx)
        }
    }
}
