//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupAttachmentUploadQueueStatus {
    /// The queue is running, and attachment are uploading.
    case running

    /// There's nothing to upload.
    case empty

    /// Must be registered and the app ready to upload.
    case notRegisteredAndReady
    /// Wifi is required for uploads, but not available.
    case noWifiReachability
    /// The device has low battery or is in low power mode.
    case lowBattery
}

public extension Notification.Name {
    static let backupAttachmentUploadQueueStatusDidChange = Notification.Name(rawValue: "BackupAttachmentUploadQueueStatusDidChange")
}

// MARK: -

/// Reports whether we are able to upload Backup attachments, via various
/// consolidated inputs.
///
/// `@MainActor`-isolated because most of the inputs are themselves isolated.
@MainActor
public protocol BackupAttachmentUploadQueueStatusReporter {
    func currentStatus() -> BackupAttachmentUploadQueueStatus
}

extension BackupAttachmentUploadQueueStatusReporter {
    func notifyStatusDidChange() {
        NotificationCenter.default.postOnMainThread(
            name: .backupAttachmentUploadQueueStatusDidChange,
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
    func beginObservingIfNecessary() -> BackupAttachmentUploadQueueStatus

    /// Notifies the status manager that the upload queue was emptied.
    func didEmptyQueue()
}

// MARK: -

@MainActor
public class BackupAttachmentUploadQueueStatusManagerImpl: BackupAttachmentUploadQueueStatusManager {

    // MARK: - BackupAttachmentUploadQueueStatusReporter

    public func currentStatus() -> BackupAttachmentUploadQueueStatus {
        return state.asQueueStatus
    }

    // MARK: - BackupAttachmentUploadQueueStatusManager

    public func beginObservingIfNecessary() -> BackupAttachmentUploadQueueStatus {
        observeDeviceAndLocalStatesIfNecessary()
        return currentStatus()
    }

    public func didEmptyQueue() {
        state.isQueueEmpty = true
        stopObservingDeviceAndLocalStates()
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
        tsAccountManager: TSAccountManager
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
            isQueueEmpty: nil,
            isMainApp: appContext.isMainApp,
            isAppReady: false,
            isRegistered: nil,
            backupPlan: nil,
            shouldAllowBackupUploadsOnCellular: nil,
            isWifiReachable: nil,
            batteryLevel: nil,
            isLowPowerMode: nil,
        )

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.appReadinessDidChange()
        }
    }

    // MARK: - Private

    private struct State {
        var isQueueEmpty: Bool?

        var isMainApp: Bool
        var isAppReady: Bool
        var isRegistered: Bool?

        var backupPlan: BackupPlan?

        var shouldAllowBackupUploadsOnCellular: Bool?
        var isWifiReachable: Bool?

        // Value from 0 to 1
        var batteryLevel: Float?
        var isLowPowerMode: Bool?

        init(
            isQueueEmpty: Bool?,
            isMainApp: Bool,
            isAppReady: Bool,
            isRegistered: Bool?,
            backupPlan: BackupPlan?,
            shouldAllowBackupUploadsOnCellular: Bool?,
            isWifiReachable: Bool?,
            batteryLevel: Float?,
            isLowPowerMode: Bool?,
        ) {
            self.isQueueEmpty = isQueueEmpty
            self.isMainApp = isMainApp
            self.isAppReady = isAppReady
            self.isRegistered = isRegistered
            self.backupPlan = backupPlan
            self.shouldAllowBackupUploadsOnCellular = shouldAllowBackupUploadsOnCellular
            self.isWifiReachable = isWifiReachable
            self.batteryLevel = batteryLevel
            self.isLowPowerMode = isLowPowerMode
        }

        var asQueueStatus: BackupAttachmentUploadQueueStatus {
            if isQueueEmpty == true {
                return .empty
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

            if
                shouldAllowBackupUploadsOnCellular != true,
                isWifiReachable != true
            {
                return .noWifiReachability
            }

            if (batteryLevel ?? 0) < 0.1 {
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

        let isQueueEmpty = db.read { tx in
            return ((try? backupAttachmentUploadStore.fetchNextUploads(count: 1, tx: tx)) ?? []).isEmpty
        }
        state.isQueueEmpty = isQueueEmpty

        // Only observe if the queue is non-empty, so as to not waste resources;
        // for example, by telling the OS we want battery level updates.
        if isQueueEmpty, !wasQueueEmpty {
            stopObservingDeviceAndLocalStates()
        } else if !isQueueEmpty, wasQueueEmpty {
            observeDeviceAndLocalStates()
        }
    }

    private func observeDeviceAndLocalStates() {
        let (backupPlan, shouldAllowBackupUploadsOnCellular) = db.read { tx in
            (
                backupSettingsStore.backupPlan(tx: tx),
                backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx)
            )
        }

        let notificationsToObserve: [(Notification.Name, Selector)] = [
            (.registrationStateDidChange, #selector(registrationStateDidChange)),
            (.backupPlanChanged, #selector(backupPlanDidChange)),
            (.shouldAllowBackupUploadsOnCellularChanged, #selector(shouldAllowBackupUploadsOnCellularDidChange)),
            (.reachabilityChanged, #selector(reachabilityDidChange)),
            (UIDevice.batteryLevelDidChangeNotification, #selector(batteryLevelDidChange)),
            (Notification.Name.NSProcessInfoPowerStateDidChange, #selector(lowPowerModeDidChange)),
        ]
        for (name, selector) in notificationsToObserve {
            NotificationCenter.default.addObserver(
                self,
                selector: selector,
                name: name,
                object: nil
            )
        }

        self.batteryLevelMonitor = deviceBatteryLevelManager?.beginMonitoring(reason: "BackupDownloadQueue")
        self.state = State(
            isQueueEmpty: state.isQueueEmpty,
            isMainApp: appContext.isMainApp,
            isAppReady: appReadiness.isAppReady,
            isRegistered: tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered,
            backupPlan: backupPlan,
            shouldAllowBackupUploadsOnCellular: shouldAllowBackupUploadsOnCellular,
            isWifiReachable: reachabilityManager.isReachable(via: .wifi),
            batteryLevel: batteryLevelMonitor?.batteryLevel,
            isLowPowerMode: deviceBatteryLevelManager?.isLowPowerModeEnabled,
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
    private func shouldAllowBackupUploadsOnCellularDidChange() {
        state.shouldAllowBackupUploadsOnCellular = db.read { tx in
            backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx)
        }
    }

    @objc
    private func reachabilityDidChange() {
        state.isWifiReachable = reachabilityManager.isReachable(via: .wifi)
    }

    @objc
    private func batteryLevelDidChange() {
        state.batteryLevel = batteryLevelMonitor?.batteryLevel
    }

    @objc
    private func lowPowerModeDidChange() {
        self.state.isLowPowerMode = deviceBatteryLevelManager?.isLowPowerModeEnabled
    }
}
