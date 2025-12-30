//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public enum BackupAttachmentDownloadQueueMode {
    case fullsize
    case thumbnail
}

public enum BackupAttachmentDownloadQueueStatus: Equatable, Sendable {
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
    /// The device has low battery.
    case lowBattery
    /// The device is in low power mode.
    case lowPowerMode
    /// There is not enough disk space to finish downloading.
    /// Note that we require a minimum amount of space and will continue
    /// greedily downloading until this minimum is reached even if we know
    /// ahead of time we will hit the threshold before finishing.
    /// Does not apply to upload.
    case lowDiskSpace
    /// The app is running in the background.
    case appBackgrounded
}

public extension Notification.Name {
    static func backupAttachmentDownloadQueueStatusDidChange(mode: BackupAttachmentDownloadQueueMode) -> Notification.Name {
        switch mode {
        case .fullsize:
            return Notification.Name(rawValue: "BackupAttachmentDownloadQueueStatusDidChange_fullsize")
        case .thumbnail:
            return Notification.Name(rawValue: "BackupAttachmentDownloadQueueStatusDidChange_thumbnail")
        }
    }
}

// MARK: -

/// Reports whether we are able to download Backup attachments, via various
/// consolidated inputs.
///
/// `@MainActor`-isolated because most of the inputs are themselves isolated.
@MainActor
public protocol BackupAttachmentDownloadQueueStatusReporter {
    func currentStatus(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus

    func currentStatusAndToken(for mode: BackupAttachmentDownloadQueueMode) -> (BackupAttachmentDownloadQueueStatus, BackupAttachmentDownloadQueueStatusToken)

    /// Synchronously returns the minimum required disk space for downloads.
    nonisolated func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64

    /// Re-triggers disk space checks and clears any in-memory state for past disk space errors,
    /// in order to attempt download resumption.
    func reattemptDiskSpaceChecks()
}

extension BackupAttachmentDownloadQueueStatusReporter {
    fileprivate func notifyStatusDidChange(for mode: BackupAttachmentDownloadQueueMode) {
        NotificationCenter.default.postOnMainThread(
            name: .backupAttachmentDownloadQueueStatusDidChange(mode: mode),
            object: nil,
        )
    }
}

/// Grab one of these when starting a job; use it to mark success or failure
/// This takes a (black box) snapshot of state when the download began so that
/// when we respond to success or errors we apply them appropriately based
/// on state at start of the job, not at the end.
public protocol BackupAttachmentDownloadQueueStatusToken {}

// MARK: -

/// API for callers to manage the `StatusReporter` in response to relevant
/// external events.
@MainActor
public protocol BackupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusReporter {

    /// Begin observing status updates, if necessary.
    func beginObservingIfNecessary(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus

    /// Synchronously check remaining disk space.
    /// If there is sufficient space, early exit.
    /// Otherwise, await a full state update.
    nonisolated func quickCheckDiskSpaceForDownloads() async

    /// Checks if the error should change the status (e.g. out of disk space errors should stop subsequent downloads)
    /// Returns nil if the error has no effect on the status (though note the status may be changed for any other concurrent
    /// reason unrelated to the error).
    nonisolated func jobDidExperienceError(
        _ error: Error,
        token: BackupAttachmentDownloadQueueStatusToken,
        mode: BackupAttachmentDownloadQueueMode,
    ) async -> BackupAttachmentDownloadQueueStatus?

    nonisolated func jobDidSucceed(
        token: BackupAttachmentDownloadQueueStatusToken,
        mode: BackupAttachmentDownloadQueueMode,
    ) async

    /// Call when the download queue is emptied.
    func didEmptyQueue(for mode: BackupAttachmentDownloadQueueMode)

    func setIsMainAppAndActiveOverride(_ newValue: Bool)
}

// MARK: -

@MainActor
public class BackupAttachmentDownloadQueueStatusManagerImpl: BackupAttachmentDownloadQueueStatusManager {

    // MARK: - BackupAttachmentDownloadQueueStatusReporter

    public func currentStatus(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus {
        return state.asQueueStatus(mode: mode, dateProvider: dateProvider)
    }

    public func currentStatusAndToken(for mode: BackupAttachmentDownloadQueueMode) -> (BackupAttachmentDownloadQueueStatus, BackupAttachmentDownloadQueueStatusToken) {
        return (
            state.asQueueStatus(mode: mode, dateProvider: dateProvider),
            BackupAttachmentDownloadQueueStatusTokenImpl(lastNetworkOr5xxErrorTime: state.lastNetworkOr5xxErrorTime),
        )
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

    public func beginObservingIfNecessary(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus {
        observeDeviceAndLocalStatesIfNecessary()
        return currentStatus(for: mode)
    }

    public nonisolated func jobDidExperienceError(
        _ error: Error,
        token: BackupAttachmentDownloadQueueStatusToken,
        mode: BackupAttachmentDownloadQueueMode,
    ) async -> BackupAttachmentDownloadQueueStatus? {
        // We care about out of disk space errors for downloads.
        if (error as NSError).code == NSFileWriteOutOfSpaceError {
            // Return nil to avoid having to thread-hop to the main thread just to get
            // the current status when we know it won't change due to this error.
            return await MainActor.run {
                return downloadDidExperienceOutOfSpaceError(mode: mode)
            }
        } else if error.isNetworkFailureOrTimeout {
            return await MainActor.run {
                return downloadDidExperienceNetworkOr5xxError(mode: mode, token: token)
            }
        } else {
            return nil
        }
    }

    public nonisolated func jobDidSucceed(
        token: BackupAttachmentDownloadQueueStatusToken,
        mode: BackupAttachmentDownloadQueueMode,
    ) async {
        guard (token as? BackupAttachmentDownloadQueueStatusTokenImpl)?.lastNetworkOr5xxErrorTime != nil else {
            return
        }
        await MainActor.run {
            self.resetNetworkErrorRetriesAfterSuccess(token: token)
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

    public func didEmptyQueue(for mode: BackupAttachmentDownloadQueueMode) {
        switch mode {
        case .thumbnail:
            state.isThumbnailQueueEmpty = true
        case .fullsize:
            state.isFullsizeQueueEmpty = true

            // We were temporarily doing downloads over cellular, but we're done
            // and shouldn't keep allowing cellular.
            Task {
                await db.awaitableWrite { tx in
                    backupSettingsStore.setShouldAllowBackupDownloadsOnCellular(false, tx: tx)
                }
            }
        }

        if state.isThumbnailQueueEmpty == true, state.isFullsizeQueueEmpty == true {
            stopObservingDeviceAndLocalStates()
        }
    }

    public func setIsMainAppAndActiveOverride(_ newValue: Bool) {
        state.isMainAppAndActiveOverride = newValue
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
        tsAccountManager: TSAccountManager,
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
            isFullsizeQueueEmpty: nil,
            isThumbnailQueueEmpty: nil,
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
            downloadDidExperienceOutOfSpaceError: false,
            isMainAppAndActive: appContext.isMainAppAndActive,
        )
        self.fullsizeQueueStatus = state.asQueueStatus(mode: .fullsize, dateProvider: dateProvider)
        self.thumbnailQueueStatus = state.asQueueStatus(mode: .thumbnail, dateProvider: dateProvider)

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.appReadinessDidChange()
        }
    }

    // MARK: - Private

    private struct State {
        var isFullsizeQueueEmpty: Bool?
        var isThumbnailQueueEmpty: Bool?

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

        var isMainAppAndActive: Bool
        var isMainAppAndActiveOverride: Bool = false

        var networkOr5xxErrorCount = 0
        var lastNetworkOr5xxErrorTime: Date?

        init(
            isFullsizeQueueEmpty: Bool?,
            isThumbnailQueueEmpty: Bool?,
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
            isMainAppAndActive: Bool,
        ) {
            self.isFullsizeQueueEmpty = isFullsizeQueueEmpty
            self.isThumbnailQueueEmpty = isThumbnailQueueEmpty
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
            self.isMainAppAndActive = isMainAppAndActive
        }

        func asQueueStatus(
            mode: BackupAttachmentDownloadQueueMode,
            dateProvider: DateProvider,
        ) -> BackupAttachmentDownloadQueueStatus {

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
                return .lowPowerMode
            }

            if !isMainAppAndActive, !isMainAppAndActiveOverride {
                return .appBackgrounded
            }

            if let lastNetworkOr5xxErrorTime {
                let restartTime = BackupAttachmentDownloadQueueStatusManagerImpl.queueRestartTimeAfterNetworkError(
                    at: lastNetworkOr5xxErrorTime,
                    failureCount: networkOr5xxErrorCount,
                )
                if dateProvider() <= restartTime {
                    return .noReachability
                }
            }

            return .running
        }
    }

    private var state: State {
        didSet {
            fullsizeQueueStatus = state.asQueueStatus(mode: .fullsize, dateProvider: dateProvider)
            thumbnailQueueStatus = state.asQueueStatus(mode: .thumbnail, dateProvider: dateProvider)
        }
    }

    private var fullsizeQueueStatus: BackupAttachmentDownloadQueueStatus {
        didSet {
            if oldValue != fullsizeQueueStatus {
                notifyStatusDidChange(for: .fullsize)
            }
        }
    }

    private var thumbnailQueueStatus: BackupAttachmentDownloadQueueStatus {
        didSet {
            if oldValue != thumbnailQueueStatus {
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

        let (
            isFullsizeQueueEmpty,
            isThumbnailQueueEmpty,
            areDownloadsSuspended,
        ) = db.read { tx in
            return (
                !backupAttachmentDownloadStore.hasAnyReadyDownloads(
                    isThumbnail: false,
                    tx: tx,
                ),
                !backupAttachmentDownloadStore.hasAnyReadyDownloads(
                    isThumbnail: true,
                    tx: tx,
                ),
                backupSettingsStore.isBackupAttachmentDownloadQueueSuspended(tx: tx),
            )

        }
        state.isFullsizeQueueEmpty = isFullsizeQueueEmpty
        state.isThumbnailQueueEmpty = isThumbnailQueueEmpty
        state.areDownloadsSuspended = areDownloadsSuspended

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
        let (isRegistered, shouldAllowBackupDownloadsOnCellular) = db.read { tx in
            return (
                tsAccountManager.registrationState(tx: tx).isRegistered,
                backupSettingsStore.shouldAllowBackupDownloadsOnCellular(tx: tx),
            )
        }

        let notificationsToObserve: [(Notification.Name, Selector)] = [
            (.registrationStateDidChange, #selector(registrationStateDidChange)),
            (.reachabilityChanged, #selector(reachabilityDidChange)),
            (.batteryLevelChanged, #selector(batteryLevelDidChange)),
            (.batteryLowPowerModeChanged, #selector(lowPowerModeDidChange)),
            (.OWSApplicationWillEnterForeground, #selector(willEnterForeground)),
            (.backupAttachmentDownloadQueueSuspensionStatusDidChange, #selector(suspensionStatusDidChange)),
            (.shouldAllowBackupDownloadsOnCellularChanged, #selector(shouldAllowBackupDownloadsOnCellularDidChange)),
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

        // Don't worry about this changing during an app lifetime; just check it once up front.
        let requiredDiskSpace = getRequiredDiskSpace()

        self.batteryLevelMonitor = deviceBatteryLevelManager?.beginMonitoring(reason: "BackupDownloadQueue")
        self.state = State(
            isFullsizeQueueEmpty: state.isFullsizeQueueEmpty,
            isThumbnailQueueEmpty: state.isThumbnailQueueEmpty,
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
            downloadDidExperienceOutOfSpaceError: state.downloadDidExperienceOutOfSpaceError,
            isMainAppAndActive: appContext.isMainAppAndActive,
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
    private func reachabilityDidChange() {
        let isWifiReachable = reachabilityManager.isReachable(via: .wifi)
        let isReachable = reachabilityManager.isReachable(via: .any)

        state.isWifiReachable = isWifiReachable
        state.isReachable = isReachable

        if isWifiReachable, state.shouldAllowBackupDownloadsOnCellular == true {
            // We were temporarily doing downloads over cellular, but now we
            // have WiFi and shouldn't keep allowing cellular.
            Task {
                await db.awaitableWrite { tx in
                    backupSettingsStore.setShouldAllowBackupDownloadsOnCellular(false, tx: tx)
                }
            }
        }
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
                forPath: AttachmentStream.attachmentsDirectory(),
            )
        } catch {
            owsFailDebug("Unable to determine disk space \(error)")
            return nil
        }
    }

    private nonisolated func getRequiredDiskSpace() -> UInt64 {
        return UInt64(remoteConfigManager.currentConfig().attachmentMaxEncryptedBytes) * 5
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

    private func downloadDidExperienceOutOfSpaceError(mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus {
        // We track the error independent of fullsize vs thumbnail
        state.downloadDidExperienceOutOfSpaceError = true
        return state.asQueueStatus(mode: mode, dateProvider: dateProvider)
    }

    private class BackupAttachmentDownloadQueueStatusTokenImpl: BackupAttachmentDownloadQueueStatusToken {
        let lastNetworkOr5xxErrorTime: Date?

        init(lastNetworkOr5xxErrorTime: Date?) {
            self.lastNetworkOr5xxErrorTime = lastNetworkOr5xxErrorTime
        }
    }

    @objc
    private func isMainAppAndActiveDidChange() {
        self.state.isMainAppAndActive = appContext.isMainAppAndActive
    }

    private nonisolated static func queueRestartTimeAfterNetworkError(
        at errorDate: Date,
        failureCount: Int,
    ) -> Date {
        let delay = OWSOperation.retryIntervalForExponentialBackoff(
            failureCount: failureCount,
            minAverageBackoff: 1,
            maxAverageBackoff: .day * 5,
        )
        return errorDate.addingTimeInterval(delay)
    }

    private func downloadDidExperienceNetworkOr5xxError(
        mode: BackupAttachmentDownloadQueueMode,
        token: BackupAttachmentDownloadQueueStatusToken,
    ) -> BackupAttachmentDownloadQueueStatus {
        guard
            let token = token as? BackupAttachmentDownloadQueueStatusTokenImpl,
            state.lastNetworkOr5xxErrorTime == token.lastNetworkOr5xxErrorTime
        else {
            return state.asQueueStatus(mode: mode, dateProvider: dateProvider)
        }
        let failureCount = state.networkOr5xxErrorCount
        let errorDate = dateProvider()
        let restartDate = Self.queueRestartTimeAfterNetworkError(
            at: errorDate,
            failureCount: failureCount,
        )
        state.networkOr5xxErrorCount = failureCount + 1
        state.lastNetworkOr5xxErrorTime = errorDate
        if restartDate > dateProvider() {
            Task { [weak self, dateProvider] in
                let now = dateProvider()
                if restartDate > now {
                    try await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(restartDate.timeIntervalSince(now)))
                }
                self?.didReachNetworkErrorRetryTime(token: BackupAttachmentDownloadQueueStatusTokenImpl(lastNetworkOr5xxErrorTime: errorDate))
            }
        }
        return state.asQueueStatus(mode: mode, dateProvider: dateProvider)
    }

    private func didReachNetworkErrorRetryTime(token: BackupAttachmentDownloadQueueStatusToken) {
        guard
            let token = token as? BackupAttachmentDownloadQueueStatusTokenImpl,
            state.lastNetworkOr5xxErrorTime == token.lastNetworkOr5xxErrorTime
        else {
            return
        }
        state.lastNetworkOr5xxErrorTime = nil
    }

    private func resetNetworkErrorRetriesAfterSuccess(token: BackupAttachmentDownloadQueueStatusToken) {
        guard
            let token = token as? BackupAttachmentDownloadQueueStatusTokenImpl,
            state.lastNetworkOr5xxErrorTime == token.lastNetworkOr5xxErrorTime
        else {
            return
        }
        state.lastNetworkOr5xxErrorTime = nil
        state.networkOr5xxErrorCount = 0
    }
}

// MARK: -

#if TESTABLE_BUILD

class MockBackupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager {
    struct BackupAttachmentDownloadQueueStatusTokenMock: BackupAttachmentDownloadQueueStatusToken {}

    var currentStatusMock: BackupAttachmentDownloadQueueStatus?
    func currentStatus(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus {
        currentStatusMock ?? .empty
    }

    func currentStatusAndToken(for mode: BackupAttachmentDownloadQueueMode) -> (BackupAttachmentDownloadQueueStatus, BackupAttachmentDownloadQueueStatusToken) {
        (currentStatusMock ?? .empty, BackupAttachmentDownloadQueueStatusTokenMock())
    }

    func minimumRequiredDiskSpaceToCompleteDownloads() -> UInt64 {
        0
    }

    func reattemptDiskSpaceChecks() {
        // Nothing
    }

    func beginObservingIfNecessary(for mode: BackupAttachmentDownloadQueueMode) -> BackupAttachmentDownloadQueueStatus {
        return currentStatus(for: mode)
    }

    func quickCheckDiskSpaceForDownloads() async {
        // Nothing
    }

    func jobDidExperienceError(
        _ error: any Error,
        token: BackupAttachmentDownloadQueueStatusToken,
        mode: BackupAttachmentDownloadQueueMode,
    ) async -> BackupAttachmentDownloadQueueStatus? {
        return nil
    }

    func jobDidSucceed(
        token: BackupAttachmentDownloadQueueStatusToken,
        mode: BackupAttachmentDownloadQueueMode,
    ) async {
        // Nothing
    }

    func didEmptyQueue(for mode: BackupAttachmentDownloadQueueMode) {
        // Nothing
    }

    func setIsMainAppAndActiveOverride(_ newValue: Bool) {}
}

#endif
