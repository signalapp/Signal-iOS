//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI
import StoreKit
import SwiftUI

class BackupSettingsViewController:
    HostingController<BackupSettingsView>,
    BackupSettingsViewModel.ActionsDelegate
{
    enum OnAppearAction {
        case presentWelcomeToBackupsSheet
    }

    private let accountEntropyPoolManager: AccountEntropyPoolManager
    private let accountKeyStore: AccountKeyStore
    private let backupAttachmentDownloadTracker: BackupSettingsAttachmentDownloadTracker
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupAttachmentUploadTracker: BackupSettingsAttachmentUploadTracker
    private let backupDisablingManager: BackupDisablingManager
    private let backupEnablingManager: BackupEnablingManager
    private let backupExportJobRunner: BackupExportJobRunner
    private let backupFailureStateManager: BackupFailureStateManager
    private let backupIdService: BackupIdService
    private let backupPlanManager: BackupPlanManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionIssueStore: BackupSubscriptionIssueStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let db: DB
    private let deviceSleepManager: DeviceSleepManager
    private let subscriptionConfigManager: SubscriptionConfigManager
    private let tsAccountManager: TSAccountManager

    private var onAppearAction: OnAppearAction?
    private let viewModel: BackupSettingsViewModel

    private var externalEventObservationTasks: [Task<Void, Never>] = []

    convenience init(
        onAppearAction: OnAppearAction?,
    ) {
        guard let deviceSleepManager = DependenciesBridge.shared.deviceSleepManager else {
            owsFail("Unexpectedly missing DeviceSleepManager in main app!")
        }

        self.init(
            onAppearAction: onAppearAction,
            accountEntropyPoolManager: DependenciesBridge.shared.accountEntropyPoolManager,
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupAttachmentDownloadProgress: DependenciesBridge.shared.backupAttachmentDownloadProgress,
            backupAttachmentDownloadQueueStatusReporter: DependenciesBridge.shared.backupAttachmentDownloadQueueStatusReporter,
            backupAttachmentUploadProgress: DependenciesBridge.shared.backupAttachmentUploadProgress,
            backupAttachmentUploadQueueStatusReporter: DependenciesBridge.shared.backupAttachmentUploadQueueStatusReporter,
            backupAttachmentUploadStore: DependenciesBridge.shared.backupAttachmentUploadStore,
            backupDisablingManager: DependenciesBridge.shared.backupDisablingManager,
            backupEnablingManager: AppEnvironment.shared.backupEnablingManager,
            backupExportJobRunner: DependenciesBridge.shared.backupExportJobRunner,
            backupFailureStateManager: DependenciesBridge.shared.backupFailureStateManager,
            backupIdService: DependenciesBridge.shared.backupIdService,
            backupPlanManager: DependenciesBridge.shared.backupPlanManager,
            backupSettingsStore: BackupSettingsStore(),
            backupSubscriptionIssueStore: BackupSubscriptionIssueStore(),
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            db: DependenciesBridge.shared.db,
            deviceSleepManager: deviceSleepManager,
            subscriptionConfigManager: DependenciesBridge.shared.subscriptionConfigManager,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
    }

    init(
        onAppearAction: OnAppearAction?,
        accountEntropyPoolManager: AccountEntropyPoolManager,
        accountKeyStore: AccountKeyStore,
        backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress,
        backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupDisablingManager: BackupDisablingManager,
        backupEnablingManager: BackupEnablingManager,
        backupExportJobRunner: BackupExportJobRunner,
        backupFailureStateManager: BackupFailureStateManager,
        backupIdService: BackupIdService,
        backupPlanManager: BackupPlanManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionIssueStore: BackupSubscriptionIssueStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        db: DB,
        deviceSleepManager: DeviceSleepManager,
        subscriptionConfigManager: SubscriptionConfigManager,
        tsAccountManager: TSAccountManager,
    ) {
        owsPrecondition(
            db.read { tsAccountManager.registrationState(tx: $0).isPrimaryDevice == true },
            "Unsafe to let a linked device access Backup Settings!",
        )

        self.accountEntropyPoolManager = accountEntropyPoolManager
        self.accountKeyStore = accountKeyStore
        self.backupAttachmentDownloadTracker = BackupSettingsAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusReporter: backupAttachmentDownloadQueueStatusReporter,
            backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
        )
        self.backupAttachmentUploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: backupAttachmentUploadQueueStatusReporter,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
        )
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupDisablingManager = backupDisablingManager
        self.backupEnablingManager = backupEnablingManager
        self.backupExportJobRunner = backupExportJobRunner
        self.backupFailureStateManager = backupFailureStateManager
        self.backupIdService = backupIdService
        self.backupPlanManager = backupPlanManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionIssueStore = backupSubscriptionIssueStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.db = db
        self.deviceSleepManager = deviceSleepManager
        self.subscriptionConfigManager = subscriptionConfigManager
        self.tsAccountManager = tsAccountManager

        self.onAppearAction = onAppearAction
        self.viewModel = db.read { tx in
            let viewModel = BackupSettingsViewModel(
                backupSubscriptionConfiguration: subscriptionConfigManager.backupConfigurationOrDefault(tx: tx),
                backupSubscriptionLoadingState: .loading,
                backupSubscriptionAlreadyRedeemed: backupSubscriptionIssueStore.shouldShowIAPSubscriptionAlreadyRedeemedWarning(tx: tx),
                backupPlan: backupPlanManager.backupPlan(tx: tx),
                failedToDisableBackupsRemotely: backupDisablingManager.disableRemotelyFailed(tx: tx),
                latestBackupExportProgressUpdate: nil,
                latestBackupAttachmentDownloadUpdate: nil,
                latestBackupAttachmentUploadUpdate: nil,
                lastBackupDetails: backupSettingsStore.lastBackupDetails(tx: tx),
                shouldAllowBackupUploadsOnCellular: backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx),
                mediaTierCapacityOverflow: Self.getMediaTierCapacityOverflow(
                    backupAttachmentUploadStore: backupAttachmentUploadStore,
                    backupSettingsStore: backupSettingsStore,
                    tx: tx,
                ),
                hasBackupFailed: backupFailureStateManager.hasFailedBackup(tx: tx),
                isBackgroundAppRefreshDisabled: Self.isBackgroundAppRefreshDisabled(),
            )

            return viewModel
        }

        super.init(wrappedView: BackupSettingsView(viewModel: viewModel))

        title = OWSLocalizedString(
            "BACKUPS_SETTINGS_TITLE",
            comment: "Title for the 'Backup' settings menu.",
        )
        OWSTableViewController2.removeBackButtonText(viewController: self)

        viewModel.actionsDelegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            await refreshBackupSubscriptionConfig()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        switch onAppearAction.take() {
        case nil:
            break
        case .presentWelcomeToBackupsSheet:
            presentWelcomeToBackupsSheet()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        startExternalEventObservation()

        // Reload the view model, as state may have changed while we weren't
        // visible.
        reloadViewModel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        stopExternalEventObservation()
    }

    // MARK: -

    /// Refresh the `BackupSubscriptionConfig` we loaded during `init`.
    ///
    /// Covers the niche case in which we hadn't successfully fetched the config
    /// before init, prompting to contact support if we fail here as well (maybe
    /// we're having parsing issues or something).
    private func refreshBackupSubscriptionConfig() async {
        do {
            let backupSubscriptionConfig = try await subscriptionConfigManager.backupConfiguration()

            // If we loaded a different BackupSubscriptionConfig than what we
            // got during init, swap it in.
            if viewModel.backupSubscriptionConfiguration != backupSubscriptionConfig {
                viewModel.backupSubscriptionConfiguration = backupSubscriptionConfig
            }
        } catch where error.isNetworkFailureOrTimeout || error.is5xxServiceResponse {
            // Ignore network failures.
        } catch {
            owsFailDebug("Failed to fetch Backup subscription config!")
            SheetDisplayableError.genericError.showSheet(from: self)
        }
    }

    private func startExternalEventObservation() {
        guard externalEventObservationTasks.isEmpty else {
            return
        }

        externalEventObservationTasks = [
            Task { [weak self, backupExportJobRunner] in
                await self?.preventDeviceSleepDuringNonNilUpdates(
                    updateStream: backupExportJobRunner.updates(),
                    label: "Export",
                ) { [weak self] exportJobUpdate in
                    guard let self else { return }

                    switch exportJobUpdate {
                    case nil:
                        viewModel.latestBackupExportProgressUpdate = nil
                    case .progress(let progressUpdate):
                        viewModel.latestBackupExportProgressUpdate = progressUpdate
                    case .completion(let result):
                        viewModel.latestBackupExportProgressUpdate = nil

                        switch result {
                        case .success:
                            break
                        case .failure(let error):
                            showSheetForBackupExportJobError(error)
                        }

                        db.read { tx in
                            self.viewModel.hasBackupFailed = self.backupFailureStateManager.hasFailedBackup(tx: tx)
                        }
                    }
                }
            },
            Task { [weak self, backupAttachmentDownloadTracker] in
                await self?.preventDeviceSleepDuringNonNilUpdates(
                    updateStream: backupAttachmentDownloadTracker.updates(),
                    label: "Downloads",
                ) { [weak self] downloadUpdate in
                    guard let self else { return }
                    viewModel.latestBackupAttachmentDownloadUpdate = downloadUpdate
                }
            },
            Task { [weak self, backupAttachmentUploadTracker] in
                await self?.preventDeviceSleepDuringNonNilUpdates(
                    updateStream: backupAttachmentUploadTracker.updates(),
                    label: "Uploads",
                ) { [weak self] uploadUpdate in
                    guard let self else { return }
                    viewModel.latestBackupAttachmentUploadUpdate = uploadUpdate
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: .OWSApplicationDidBecomeActive,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        loadBackupSubscription()
                    }
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: .backupPlanChanged,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        _backupPlanDidChange()
                    }
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: .lastBackupDetailsDidChange,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        _lastBackupDetailsDidChange()
                    }
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: .shouldAllowBackupUploadsOnCellularChanged,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        _shouldAllowBackupUploadsOnCellularDidChange()
                    }
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: .backupSubscriptionAlreadyRedeemedDidChange,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        _backupSubscriptionAlreadyRedeemedDidChange()
                    }
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: .backupIAPNotFoundLocallyDidChange,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        _backupIAPNotFoundLocallyDidChange()
                    }
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: .hasConsumedMediaTierCapacityStatusDidChange,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        _hasConsumedMediaTierCapacityDidChange()
                    }
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: UIApplication.backgroundRefreshStatusDidChangeNotification,
                ) {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        _isBackgroundAppRefreshDisabledDidChange()
                    }
                }
            },
        ]
    }

    private func stopExternalEventObservation() {
        externalEventObservationTasks.forEach { $0.cancel() }
        externalEventObservationTasks = []
    }

    /// Prevent device sleep when the given `updateStream` is producing non-nil
    /// updates. This is appropriate when said updates result in us displaying
    /// UX, such as a progress bar, for which we want to prevent sleep.
    @MainActor
    private func preventDeviceSleepDuringNonNilUpdates<T>(
        updateStream: AsyncStream<T?>,
        label: String,
        onUpdate: (T?) -> Void,
    ) async {
        // Caller-retained as long as sleep-blocking is required.
        var deviceSleepBlock: DeviceSleepBlockObject?

        for await update in updateStream {
            if update != nil {
                deviceSleepBlock = deviceSleepBlock ?? {
                    let newSleepBlock = DeviceSleepBlockObject(blockReason: "BackupSettings: \(label)")
                    deviceSleepManager.addBlock(blockObject: newSleepBlock)
                    return newSleepBlock
                }()
            } else {
                deviceSleepBlock
                    .take()
                    .map { deviceSleepManager.removeBlock(blockObject: $0) }
            }

            onUpdate(update)
        }

        if let deviceSleepBlock {
            deviceSleepManager.removeBlock(blockObject: deviceSleepBlock)
        }
    }

    // MARK: -

    private func reloadViewModel() {
        // Notably, we don't actively try and reload any of "latest update"
        // properties, since when we start listening to the update streams (see
        // `externalEventObservationTasks`) the latest update is yielded
        // immediately.

        db.read { tx in
            viewModel.backupPlan = backupPlanManager.backupPlan(tx: tx)
            viewModel.failedToDisableBackupsRemotely = backupDisablingManager.disableRemotelyFailed(tx: tx)
            viewModel.lastBackupDetails = backupSettingsStore.lastBackupDetails(tx: tx)
            viewModel.shouldAllowBackupUploadsOnCellular = backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx)
        }

        loadBackupSubscription()
    }

    private func _backupPlanDidChange() {
        reloadViewModel()

        // If we just disabled Backups locally but recorded a failure disabling
        // remotely, show an action sheet. (We'll also show that we failed to
        // disable remotely in BackupSettings.)
        switch viewModel.backupPlan {
        case .disabled where viewModel.failedToDisableBackupsRemotely:
            showDisablingBackupsFailedSheet()
        case .disabled, .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }
    }

    private func _lastBackupDetailsDidChange() {
        db.read { tx in
            viewModel.lastBackupDetails = backupSettingsStore.lastBackupDetails(tx: tx)
        }
    }

    private func _shouldAllowBackupUploadsOnCellularDidChange() {
        db.read { tx in
            viewModel.shouldAllowBackupUploadsOnCellular = backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx)
        }
    }

    private func _backupSubscriptionAlreadyRedeemedDidChange() {
        db.read { tx in
            viewModel.backupSubscriptionAlreadyRedeemed = backupSubscriptionIssueStore.shouldShowIAPSubscriptionAlreadyRedeemedWarning(tx: tx)
        }
    }

    private func _backupIAPNotFoundLocallyDidChange() {
        // This property isn't directly on the view model, but is fetched as
        // part of loading the subscription view.
        loadBackupSubscription()
    }

    private func _hasConsumedMediaTierCapacityDidChange() {
        db.read { tx in
            viewModel.mediaTierCapacityOverflow = Self.getMediaTierCapacityOverflow(
                backupAttachmentUploadStore: backupAttachmentUploadStore,
                backupSettingsStore: backupSettingsStore,
                tx: tx,
            )
        }
    }

    private static func getMediaTierCapacityOverflow(
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupSettingsStore: BackupSettingsStore,
        tx: DBReadTransaction,
    ) -> UInt64? {
        let hasConsumedMediaTierCapacity = backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx)
        if hasConsumedMediaTierCapacity {
            return (try? backupAttachmentUploadStore.totalEstimatedFullsizeBytesToUpload(tx: tx)) ?? 0
        } else {
            return nil
        }
    }

    private func _isBackgroundAppRefreshDisabledDidChange() {
        viewModel.isBackgroundAppRefreshDisabled = Self.isBackgroundAppRefreshDisabled()
    }

    private static func isBackgroundAppRefreshDisabled() -> Bool {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .restricted, .denied: true
        case .available: false
        @unknown default: false
        }
    }

    // MARK: - BackupSettingsViewModel.ActionsDelegate

    fileprivate func enableBackups(
        planSelection: BackupSettingsViewModel.EnableBackupsPlanSelection,
        shouldShowWelcomeToBackupsSheet: Bool,
    ) {
        Task {
            switch planSelection {
            case .required(let planSelection):
                await _enableBackups(
                    fromViewController: self,
                    planSelection: planSelection,
                    shouldShowWelcomeToBackupsSheet: shouldShowWelcomeToBackupsSheet,
                )
            case .userChoice(let initialSelection):
                await _showChooseBackupPlan(
                    initialPlanSelection: initialSelection,
                    shouldShowWelcomeToBackupsSheet: shouldShowWelcomeToBackupsSheet,
                )
            }
        }
    }

    @MainActor
    private func _showChooseBackupPlan(
        initialPlanSelection: ChooseBackupPlanViewController.PlanSelection?,
        shouldShowWelcomeToBackupsSheet: Bool,
    ) async {
        do throws(SheetDisplayableError) {
            let chooseBackupPlanViewController: ChooseBackupPlanViewController = try await .load(
                fromViewController: self,
                initialPlanSelection: initialPlanSelection,
                onConfirmPlanSelectionBlock: { [weak self] chooseBackupPlanViewController, planSelection in
                    Task { [weak self] in
                        guard let self else { return }

                        await _enableBackups(
                            fromViewController: chooseBackupPlanViewController,
                            planSelection: planSelection,
                            shouldShowWelcomeToBackupsSheet: shouldShowWelcomeToBackupsSheet,
                        )
                    }
                },
            )

            navigationController?.pushViewController(
                chooseBackupPlanViewController,
                animated: true,
            )
        } catch {
            error.showSheet(from: self)
        }
    }

    @MainActor
    private func _enableBackups(
        fromViewController: UIViewController,
        planSelection: ChooseBackupPlanViewController.PlanSelection,
        shouldShowWelcomeToBackupsSheet: Bool,
    ) async {
        do throws(SheetDisplayableError) {
            try await backupEnablingManager.enableBackups(
                fromViewController: fromViewController,
                planSelection: planSelection,
            )

            navigationController?.popToViewController(self, animated: true) { [self] in
                if shouldShowWelcomeToBackupsSheet {
                    presentWelcomeToBackupsSheet()
                }
            }
        } catch {
            error.showSheet(from: fromViewController)
        }
    }

    private func presentWelcomeToBackupsSheet() {
        final class WelcomeToBackupsSheet: HeroSheetViewController {
            override var canBeDismissed: Bool { false }

            init(onConfirm: @escaping () -> Void) {
                super.init(
                    hero: .image(.backupsSubscribed),
                    title: OWSLocalizedString(
                        "BACKUP_SETTINGS_WELCOME_TO_BACKUPS_SHEET_TITLE",
                        comment: "Title for a sheet shown after the user enables backups.",
                    ),
                    body: OWSLocalizedString(
                        "BACKUP_SETTINGS_WELCOME_TO_BACKUPS_SHEET_MESSAGE",
                        comment: "Message for a sheet shown after the user enables backups.",
                    ),
                    primaryButton: HeroSheetViewController.Button(
                        title: CommonStrings.okButton,
                        action: { _ in onConfirm() },
                    ),
                )
            }
        }

        let welcomeToBackupsSheet = WelcomeToBackupsSheet { [self] in
            viewModel.performManualBackup()
            dismiss(animated: true)
        }

        present(welcomeToBackupsSheet, animated: true)
    }

    // MARK: -

    fileprivate func disableBackups() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_CONFIRMATION_ACTION_SHEET_TITLE",
                comment: "Title for an action sheet confirming the user wants to disable Backups.",
            ),
            message: OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_CONFIRMATION_ACTION_SHEET_MESSAGE",
                comment: "Message for an action sheet confirming the user wants to disable Backups.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_CONFIRMATION_ACTION_SHEET_CONFIRM",
                comment: "Title for a button in an action sheet confirming the user wants to disable Backups.",
            ),
            style: .destructive,
            handler: { [weak self] _ in
                guard let self else { return }

                let isRegisteredPrimaryDevice = db.read { tx in
                    self.tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice
                }

                guard isRegisteredPrimaryDevice else {
                    OWSActionSheets.showActionSheet(
                        message: OWSLocalizedString(
                            "BACKUP_SETTINGS_DISABLING_ERROR_NOT_REGISTERED",
                            comment: "Message shown in an action sheet when the user tries to disable Backups, but is not registered.",
                        ),
                        fromViewController: self,
                    )
                    return
                }

                Task {
                    await self._disableBackups(aepSideEffect: nil)
                }
            },
        ))
        actionSheet.addAction(.cancel)

        presentActionSheet(actionSheet)
    }

    @MainActor
    private func _disableBackups(aepSideEffect: BackupDisablingManager.AEPSideEffect?) async {
        let backupPlanBeforeDisabling = viewModel.backupPlan

        // If we were running a manual Backup, cancel it. Most of the manual
        // Backup steps will respond to BackupPlan changing, but for example the
        // message-export stage (ensconced in its own DB transaction) will not.
        cancelManualBackup()

        // Start disabling Backups, which may result in us starting
        // downloads. When disabling completes, we'll be notified via
        // `BackupPlan` going from `.disabling` to `.disabled`.
        let currentDownloadQueueStatus = await backupDisablingManager.startDisablingBackups(
            aepSideEffect: aepSideEffect,
        )

        switch currentDownloadQueueStatus {
        case .empty, .suspended, .notRegisteredAndReady, .appBackgrounded:
            break
        case .running, .noWifiReachability, .noReachability, .lowBattery, .lowPowerMode, .lowDiskSpace:
            let downloadsActionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_DISABLING_DOWNLOADS_STARTED_ACTION_SHEET_TITLE",
                    comment: "Title shown in an action sheet when the user disables Backups, explaining that their media is downloading first.",
                ),
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_DISABLING_DOWNLOADS_STARTED_ACTION_SHEET_MESSAGE",
                    comment: "Message shown in an action sheet when the user disables Backups, explaining that their media is downloading first.",
                ),
            )
            await OWSActionSheets.showAndAwaitActionSheet(downloadsActionSheet, fromViewController: self)
        }

        switch backupPlanBeforeDisabling {
        case .disabled, .disabling, .free, .paidAsTester, .paidExpiringSoon:
            break
        case .paid:
            // If the user still has a paid subscription, suggest that they
            // cancel it.
            let cancelSubscriptionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_DISABLING_SUBSCRIPTION_CANCEL_ACTION_SHEET_TITLE",
                    comment: "Title for an action sheet shown when the user disables Backups, but is still subscribed to the paid plan.",
                ),
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_DISABLING_SUBSCRIPTION_CANCEL_ACTION_SHEET_MESSAGE",
                    comment: "Message for an action sheet shown when the user disables Backups, but is still subscribed to the paid plan.",
                ),
            )
            cancelSubscriptionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_DISABLING_SUBSCRIPTION_CANCEL_ACTION_SHEET_MANAGE_SUBSCRIPTION_BUTTON",
                    comment: "Button for an action sheet shown when the user disables Backups, letting them manage their subscription.",
                ),
                handler: { [weak self] _ in
                    guard let self else { return }
                    showAppStoreManageSubscriptions()
                },
            ))
            cancelSubscriptionSheet.addAction(.cancel)
            await OWSActionSheets.showAndAwaitActionSheet(cancelSubscriptionSheet, fromViewController: self)
        }
    }

    private func showDisablingBackupsFailedSheet() {
        OWSActionSheets.showContactSupportActionSheet(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_ERROR_GENERIC_ERROR_ACTION_SHEET_TITLE",
                comment: "Title shown in an action sheet indicating we failed to delete the user's Backup due to an unexpected error.",
            ),
            message: OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_ERROR_GENERIC_ERROR_ACTION_SHEET_MESSAGE",
                comment: "Message shown in an action sheet indicating we failed to delete the user's Backup due to an unexpected error.",
            ),
            emailFilter: .backupDisableFailed,
            fromViewController: self,
        )
    }

    // MARK: -

    private let loadBackupSubscriptionTaskQueue = SerialTaskQueue()

    fileprivate func loadBackupSubscription() {
        loadBackupSubscriptionTaskQueue.enqueueCancellingPrevious { @MainActor [self] in
            if Task.isCancelled {
                return
            }

            switch viewModel.backupSubscriptionLoadingState {
            case .loading, .loaded:
                break
            case .networkError, .genericError:
                withAnimation {
                    viewModel.backupSubscriptionLoadingState = .loading
                }
            }

            let newLoadingState: BackupSettingsViewModel.BackupSubscriptionLoadingState
            do {
                let backupSubscription = try await _loadBackupSubscription()
                newLoadingState = .loaded(backupSubscription)
            } catch is CancellationError {
                // We were cancelled: leave it loading. Whoever cancelled us
                // should be trying again.
                return
            } catch let error where error.isNetworkFailureOrTimeout {
                newLoadingState = .networkError
            } catch {
                newLoadingState = .genericError
            }

            withAnimation {
                viewModel.backupSubscriptionLoadingState = newLoadingState
            }
        }
    }

    private func _loadBackupSubscription() async throws -> BackupSettingsViewModel.BackupSubscriptionLoadingState.LoadedBackupSubscription {
        var currentBackupPlan = db.read { backupPlanManager.backupPlan(tx: $0) }

        switch currentBackupPlan {
        case .free:
            return .freeAndEnabled
        case .paidAsTester:
            return .paidButFreeForTesters
        case .disabling, .disabled:
            // Our IAP subscription may be active even if Backups are disabled,
            // and if so we want to load the state of said subscription.
            break
        case .paid, .paidExpiringSoon:
            break
        }

        let fetchedBackupSubscription: Subscription? = try await backupSubscriptionManager
            .fetchAndMaybeDowngradeSubscription()

        // Now that we've fetched a subscription, refetch state that may have
        // changed as a result.
        var backupIAPNotFoundLocally: Bool!
        db.read { tx in
            currentBackupPlan = backupPlanManager.backupPlan(tx: tx)
            backupIAPNotFoundLocally = backupSubscriptionIssueStore.shouldShowIAPSubscriptionNotFoundLocallyWarning(tx: tx)
        }

        if backupIAPNotFoundLocally {
            return .paidButIAPNotFoundLocally
        }

        let backupSubscription: Subscription
        switch currentBackupPlan {
        case .free:
            return .freeAndEnabled
        case .paidAsTester:
            return .paidButFreeForTesters
        case .disabling, .disabled:
            if let fetchedBackupSubscription {
                backupSubscription = fetchedBackupSubscription
            } else {
                return .freeAndDisabled
            }
        case .paid, .paidExpiringSoon:
            if let fetchedBackupSubscription {
                backupSubscription = fetchedBackupSubscription
            } else {
                owsFailDebug("Missing Backups subscription after fetch, but still on paid plan!")
                return .freeAndEnabled
            }
        }

        switch backupSubscription.status {
        case .canceled, .unrecognized:
            fallthrough
        case .active:
            let endOfCurrentPeriod = backupSubscription.endOfCurrentPeriod
            if backupSubscription.cancelAtEndOfPeriod {
                if endOfCurrentPeriod.isAfterNow {
                    return .paidButExpiring(expirationDate: endOfCurrentPeriod)
                } else {
                    return .paidButExpired(expirationDate: endOfCurrentPeriod)
                }
            } else {
                return .paid(
                    price: backupSubscription.amount,
                    renewalDate: endOfCurrentPeriod,
                )
            }
        case .pastDue:
            // The .pastDue status is returned if we're in the IAP "billing
            // retry", period, which indicates something has gone wrong with a
            // subscription renewal.
            //
            // SeeAlso: BackupSubscriptionManager
            return .paidButFailedToRenew
        }
    }

    // MARK: -

    fileprivate func showAppStoreManageSubscriptions() {
        guard let windowScene = view.window?.windowScene else {
            owsFailDebug("Missing window scene!")
            return
        }

        Task {
            do {
                try await AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                owsFailDebug("Failed to show manage-subscriptions view! \(error)")
            }

            // Reload the BackupPlan, since our subscription may now be in a
            // different state (e.g., set to not renew).
            loadBackupSubscription()
        }
    }

    // MARK: -

    fileprivate func performManualBackup() {
        // We observe updates from BackupExportJob, including when it
        // finishes, so all we need to do here is kick it off.
        backupExportJobRunner.startIfNecessary()
    }

    fileprivate func cancelManualBackup() {
        backupExportJobRunner.cancelIfRunning()
        suspendUploads()
    }

    fileprivate func suspendUploads() {
        db.write {
            self.backupSettingsStore.setIsBackupUploadQueueSuspended(true, tx: $0)
        }
    }

    private func showSheetForBackupExportJobError(_ error: Error) {
        let actionSheet: ActionSheetController
        switch error {
        case is CancellationError:
            return

        case is NotRegisteredError:
            actionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_NOT_REGISTERED",
                    comment: "Message for an action sheet explaining that you must be registered to make a Backup.",
                ),
            )
            actionSheet.addAction(.okay)

        case BackupExportJobError.needsWifi:
            actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_NEED_WIFI_TITLE",
                    comment: "Title for an action sheet explaining that performing a backup failed because WiFi is required.",
                ),
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_NEED_WIFI_MESSAGE",
                    comment: "Message for an action sheet explaining that performing a backup failed because WiFi is required.",
                ),
            )
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_NEED_WIFI_ACTION",
                    comment: "Title for a button in an action sheet allowing users to perform a backup, ignoring that WiFi is required.",
                ),
                handler: { [weak self] _ in
                    guard let self else { return }

                    setShouldAllowBackupUploadsOnCellular(true)
                    performManualBackup()
                },
            ))
            actionSheet.addAction(.cancel)

        case _ where error.isNetworkFailureOrTimeout || error.is5xxServiceResponse:
            actionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_NETWORK_ERROR",
                    comment: "Message for an action sheet explaining that performing a backup failed with a network error.",
                ),
            )
            actionSheet.addAction(.okay)

        default:
            actionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_GENERIC_ERROR",
                    comment: "Message for an action sheet explaining that performing a backup failed with a generic error.",
                ),
            )
            actionSheet.addAction(.contactSupport(
                emailFilter: .backupExportFailed,
                fromViewController: self,
            ))
            actionSheet.addAction(.okay)
        }

        presentActionSheet(actionSheet)
    }

    // MARK: -

    fileprivate func setShouldAllowBackupUploadsOnCellular(_ newShouldAllowBackupUploadsOnCellular: Bool) {
        db.write { tx in
            backupSettingsStore.setShouldAllowBackupUploadsOnCellular(newShouldAllowBackupUploadsOnCellular, tx: tx)
        }
    }

    // MARK: -

    fileprivate func setOptimizeLocalStorage(_ newOptimizeLocalStorage: Bool) {
        let isPaidPlanTester: Bool = db.write { tx in
            let currentBackupPlan = backupPlanManager.backupPlan(tx: tx)
            let newBackupPlan: BackupPlan
            let isPaidPlanTester: Bool

            switch currentBackupPlan {
            case .disabled, .disabling, .free:
                owsFailDebug("Shouldn't be setting Optimize Local Storage: \(currentBackupPlan)")
                return false
            case .paid:
                newBackupPlan = .paid(optimizeLocalStorage: newOptimizeLocalStorage)
                isPaidPlanTester = false
            case .paidExpiringSoon:
                newBackupPlan = .paidExpiringSoon(optimizeLocalStorage: newOptimizeLocalStorage)
                isPaidPlanTester = false
            case .paidAsTester:
                newBackupPlan = .paidAsTester(optimizeLocalStorage: newOptimizeLocalStorage)
                isPaidPlanTester = true
            }

            backupPlanManager.setBackupPlan(newBackupPlan, tx: tx)
            return isPaidPlanTester
        }

        // If disabling Optimize Local Storage, offer to start downloads now.
        if !newOptimizeLocalStorage {
            showDownloadOffloadedMediaSheet()
        } else if isPaidPlanTester {
            showOffloadedMediaForTestersWarningSheet(onAcknowledge: {})
        }
    }

    private func showDownloadOffloadedMediaSheet() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_DOWNLOAD_SHEET_TITLE",
                comment: "Title for an action sheet allowing users to download their offloaded media.",
            ),
            message: OWSLocalizedString(
                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_DOWNLOAD_SHEET_MESSAGE",
                comment: "Message for an action sheet allowing users to download their offloaded media.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_DOWNLOAD_SHEET_NOW_ACTION",
                comment: "Action in an action sheet allowing users to download their offloaded media now.",
            ),
            handler: { [weak self] _ in
                guard let self else { return }

                db.write { tx in
                    self.backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
                }
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_DOWNLOAD_SHEET_LATER_ACTION",
                comment: "Action in an action sheet allowing users to download their offloaded media later.",
            ),
            handler: { _ in },
        ))

        presentActionSheet(actionSheet)
    }

    private func showOffloadedMediaForTestersWarningSheet(
        onAcknowledge: @escaping () -> Void,
    ) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_TESTER_WARNING_SHEET_TITLE",
                comment: "Title for an action sheet warning users who are testers about the Optimize Local Storage feature.",
            ),
            message: OWSLocalizedString(
                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_TESTER_WARNING_SHEET_MESSAGE",
                comment: "Message for an action sheet warning users who are testers about the Optimize Local Storage feature.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okButton,
            handler: { _ in
                onAcknowledge()
            },
        ))

        presentActionSheet(actionSheet)
    }

    // MARK: -

    fileprivate func setIsBackupDownloadQueueSuspended(_ isSuspended: Bool, backupPlan: BackupPlan) {
        if isSuspended {
            switch backupPlan {
            case .disabled, .disabling, .free, .paid:
                db.write { tx in
                    backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
                }
            case .paidAsTester:
                showOffloadedMediaForTestersWarningSheet(onAcknowledge: { [self] in
                    db.write { tx in
                        backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
                    }
                })
            case .paidExpiringSoon:
                let warningSheet = ActionSheetController(
                    title: OWSLocalizedString(
                        "BACKUP_SETTINGS_SKIP_DOWNLOADS_WARNING_SHEET_TITLE",
                        comment: "Title for a sheet warning the user about skipping downloads.",
                    ),
                    message: OWSLocalizedString(
                        "BACKUP_SETTINGS_SKIP_DOWNLOADS_WARNING_SHEET_MESSAGE",
                        comment: "Message for a sheet warning the user about skipping downloads.",
                    ),
                )
                warningSheet.addAction(ActionSheetAction(
                    title: OWSLocalizedString(
                        "BACKUP_SETTINGS_SKIP_DOWNLOADS_WARNING_SHEET_ACTION_SKIP",
                        comment: "Title for an action in a sheet warning the user about skipping downloads.",
                    ),
                    style: .destructive,
                    handler: { [self] _ in
                        db.write { tx in
                            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
                        }
                    },
                ))
                warningSheet.addAction(ActionSheetAction(
                    title: CommonStrings.learnMore,
                    handler: { _ in
                        CurrentAppContext().open(
                            URL.Support.backups,
                            completion: nil,
                        )
                    },
                ))
                warningSheet.addAction(.cancel)

                presentActionSheet(warningSheet)
            }
        } else {
            db.write { tx in
                backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
            }
        }
    }

    fileprivate func setShouldAllowBackupDownloadsOnCellular() {
        db.write { tx in
            backupSettingsStore.setShouldAllowBackupDownloadsOnCellular(true, tx: tx)
        }
    }

    // MARK: -

    fileprivate func showViewRecoveryKey() {
        Task { await _showViewRecoveryKey() }
    }

    @MainActor
    private func _showViewRecoveryKey() async {
        guard let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) }) else {
            return
        }

        guard let authSuccess = await LocalDeviceAuthentication().performBiometricAuth() else {
            return
        }

        let recordKeyViewController = BackupRecordKeyViewController(
            aepMode: .current(aep, authSuccess),
            options: [.showCreateNewKeyButton],
            onCreateNewKeyPressed: { [weak self] recordKeyViewController in
                guard let self else { return }

                Task {
                    // If appropriate, the warning sheet will let the user continue
                    // in a "create new AEP" flow.
                    await self.showCreateNewRecoveryKeyWarningSheet(fromViewController: recordKeyViewController)
                }
            },
        )

        navigationController?.pushViewController(recordKeyViewController, animated: true)
    }

    @MainActor
    private func showCreateNewRecoveryKeyWarningSheet(
        fromViewController: BackupRecordKeyViewController,
    ) async {
        let (
            currentBackupPlan,
            isRegisteredPrimaryDevice,
        ) = db.read { tx in
            return (
                backupSettingsStore.backupPlan(tx: tx),
                tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
            )
        }

        guard isRegisteredPrimaryDevice else {
            OWSActionSheets.showActionSheet(
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_CREATE_NEW_KEY_ERROR_NOT_REGISTERED",
                    comment: "Message shown in an action sheet when the user tries to create a new Recovery Key, but is not registered.",
                ),
                fromViewController: self,
            )
            return
        }

        let showCreateKeySheet = {
            self._showCreateNewRecoveryKeyWarningSheet(
                fromViewController: fromViewController,
                currentBackupPlan: currentBackupPlan,
            )
        }

        // Check if we've hit the limit for registering new backupIDs and warn the user
        if
            let limits = try? await backupIdService.fetchBackupIDLimits(auth: .implicit()),
            !limits.hasPermitsRemaining
        {
            let bodyText = String(
                format: OWSLocalizedString(
                    "BACKUP_SETTINGS_CREATE_NEW_KEY_LIMIT_REACHED_WARNING_SHEET_BODY",
                    comment: "Explanation text for a sheet warning users they've reached a rate limit for creating Recovery Key. {{ Embeds 1: the preformatted time they must wait before enabling backups, such as \"1 week\" or \"6 hours\". }}",
                ),
                DateUtil.formatDuration(
                    seconds: UInt32(clamping: limits.retryAfterSeconds),
                    useShortFormat: false,
                ),
            )
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_CREATE_NEW_KEY_LIMIT_REACHED_WARNING_SHEET_TITLE",
                    comment: "Title for a sheet warning users they've reached a rate limit for creating Recovery Key.",
                ),
                message: bodyText,
            )

            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_CREATE_NEW_KEY_LIMIT_REACHED_WARNING_SHEET_CONTINUE_ACTION",
                    comment: "Action in an action sheet allowing to continue to rotate their key",
                ),
                style: .destructive,
                handler: { _ in
                    showCreateKeySheet()
                },
            ))
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.learnMore,
                handler: { _ in
                    CurrentAppContext().open(
                        URL.Support.backups,
                        completion: nil,
                    )
                },
            ))
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.okButton,
                handler: { _ in },
            ))

            presentActionSheet(actionSheet)
        } else {
            showCreateKeySheet()
        }
    }

    private func _showCreateNewRecoveryKeyWarningSheet(
        fromViewController: BackupRecordKeyViewController,
        currentBackupPlan: BackupPlan,
    ) {
        let primaryButtonTitle: String
        switch currentBackupPlan {
        case .disabling:
            // For simplicity, if we're already disabling don't allow creating a
            // new key. We may be disabling because of an earlier "create new
            // key" action, and we don't want ambiguity about which key is the
            // "latest".
            //
            // At the time of writing, you can't get to this flow if BackupPlan
            // is .disabling, so this dead-ends instead of showing a nice error.
            owsFail("Trying to show Create New Key sheet, but BackupPlan is .disabling. How did the UI let us get here?")
        case .disabled:
            primaryButtonTitle = CommonStrings.continueButton
        case .free, .paid, .paidExpiringSoon, .paidAsTester:
            primaryButtonTitle = OWSLocalizedString(
                "BACKUP_SETTINGS_CREATE_NEW_KEY_WARNING_SHEET_BACKUPS_MUST_BE_DISABLED_TITLE",
                comment: "TItle for a sheet warning users that Backups must be disabled to create a new Recovery Key.",
            )
        }

        let warningSheet = HeroSheetViewController(
            hero: .image(.backupsKey),
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_CREATE_NEW_KEY_WARNING_SHEET_TITLE",
                comment: "Title for a sheet warning users about creating a new Recovery Key.",
            ),
            body: OWSLocalizedString(
                "BACKUP_SETTINGS_CREATE_NEW_KEY_WARNING_SHEET_BODY",
                comment: "Body for a sheet warning users about creating a new Recovery Key.",
            ),
            primary: .button(HeroSheetViewController.Button(
                title: primaryButtonTitle,
                action: { sheet in
                    sheet.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        showRecordNewRecoveryKey()
                    }
                },
            )),
            secondary: .button(.dismissing(
                title: CommonStrings.cancelButton,
                style: .secondary,
            )),
        )
        fromViewController.present(warningSheet, animated: true)
    }

    private func showRecordNewRecoveryKey() {
        let newCandidateAEP = AccountEntropyPool()
        let recordKeyViewController = BackupRecordKeyViewController(
            aepMode: .newCandidate(newCandidateAEP),
            options: [.showContinueButton],
            onContinuePressed: { [weak self] _ in
                guard let self else { return }
                showConfirmNewRecoveryKey(newCandidateAEP: newCandidateAEP)
            },
        )

        navigationController?.pushViewController(recordKeyViewController, animated: true)
    }

    private func showConfirmNewRecoveryKey(newCandidateAEP: AccountEntropyPool) {
        let confirmKeyViewController = BackupConfirmKeyViewController(
            aep: newCandidateAEP,
            onContinue: { [weak self] _ in
                guard let self else { return }

                self.finalizeNewRecoveryKey(newCandidateAEP: newCandidateAEP)

                // Pop all the way back to Backup Settings.
                navigationController?.popToViewController(self, animated: true) {
                    self.presentToast(text: OWSLocalizedString(
                        "BACKUP_SETTINGS_CREATE_NEW_KEY_SUCCESS_TOAST",
                        comment: "Toast shown when a new Recovery Key has been created successfully.",
                    ))
                }
            },
            onSeeKeyAgain: { [weak self] in
                guard let self else { return }

                // Popping drops us back on the BackupRecordKeyViewController.
                navigationController?.popViewController(animated: true)
            },
        )

        navigationController?.pushViewController(confirmKeyViewController, animated: true)
    }

    private func finalizeNewRecoveryKey(newCandidateAEP: AccountEntropyPool) {
        db.write { tx in
            switch backupSettingsStore.backupPlan(tx: tx) {
            case .disabled:
                Logger.warn("Rotating AEP.")

                accountEntropyPoolManager.setAccountEntropyPool(
                    newAccountEntropyPool: newCandidateAEP,
                    disablePIN: false,
                    tx: tx,
                )
            case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
                Logger.warn("Disabling Backups, then rotating AEP.")

                Task {
                    await _disableBackups(aepSideEffect: .rotate(newAEP: newCandidateAEP))
                }
            }
        }
    }

    // MARK: -

    fileprivate func showBackupSubscriptionAlreadyRedeemedSheet() {
        let alreadyRedeemedSheet = BackupSubscriptionAlreadyRedeemedSheet()
        present(alreadyRedeemedSheet, animated: true)
    }

    fileprivate func showBackupIAPNotFoundLocallySheet() {
        let notFoundLocallySheet = HeroSheetViewController(
            hero: .circleIcon(icon: .backupErrorBold, iconSize: 40, tintColor: .orange, backgroundColor: UIColor(rgbHex: 0xF9E4B6)),
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_IAP_NOT_FOUND_LOCALLY_SHEET_TITLE",
                comment: "Title for a sheet explaining that the user's Backups subscription was not found on this device.",
            ),
            body: OWSLocalizedString(
                "BACKUP_SETTINGS_IAP_NOT_FOUND_LOCALLY_SHEET_BODY",
                comment: "Body for a sheet explaining that the user's Backups subscription was not found on this device.",
            ),
            primaryButton: .dismissing(title: OWSLocalizedString(
                "BACKUP_SETTINGS_IAP_NOT_FOUND_LOCALLY_SHEET_GOT_IT_BUTTON",
                comment: "Button for a sheet explaining that the user's Backups subscription was not found on this device.",
            )),
        )

        present(notFoundLocallySheet, animated: true)
    }

    fileprivate func showBackgroundAppRefreshDisabledWarningSheet() {
        let disabledSheet = HeroSheetViewController(
            hero: .circleIcon(icon: .backupErrorBold, iconSize: 40, tintColor: .orange, backgroundColor: UIColor(rgbHex: 0xF9E4B6)),
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_BACKGROUND_APP_REFRESH_DISABLED_SHEET_TITLE",
                comment: "Title for a sheet warning the user about the Background App Refresh permission. \"Background App Refresh\" should be localized the same way it is in iOS Settings app permissions.",
            ),
            body: OWSLocalizedString(
                "BACKUP_SETTINGS_BACKGROUND_APP_REFRESH_DISABLED_SHEET_MESSAGE",
                comment: "Message for a sheet warning the user about the Background App Refresh permission. \"Background App Refresh\" should be localized the same way it is in iOS Settings app permissions.",
            ),
            primaryButton: HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKGROUND_APP_REFRESH_DISABLED_SHEET_GO_TO_SETTINGS_BUTTON",
                    comment: "Title for a button that takes the users to Signal's iOS Settings page.",
                ),
                action: { sheet in
                    sheet.dismiss(animated: true) {
                        UIApplication.shared.openSystemSettings()
                    }
                },
            ),
            secondaryButton: .dismissing(
                title: CommonStrings.dismissButton,
                style: .secondary,
            ),
        )

        present(disabledSheet, animated: true)
    }
}

// MARK: -

private class BackupSettingsViewModel: ObservableObject {
    enum EnableBackupsPlanSelection {
        case required(ChooseBackupPlanViewController.PlanSelection)
        case userChoice(initialSelection: ChooseBackupPlanViewController.PlanSelection?)
    }

    protocol ActionsDelegate: AnyObject {
        func enableBackups(planSelection: EnableBackupsPlanSelection, shouldShowWelcomeToBackupsSheet: Bool)
        func disableBackups()

        func loadBackupSubscription()
        func showAppStoreManageSubscriptions()

        func performManualBackup()
        func cancelManualBackup()
        func suspendUploads()

        func setShouldAllowBackupUploadsOnCellular(_ newShouldAllowBackupUploadsOnCellular: Bool)

        func setOptimizeLocalStorage(_ newOptimizeLocalStorage: Bool)

        func setIsBackupDownloadQueueSuspended(_ isSuspended: Bool, backupPlan: BackupPlan)
        func setShouldAllowBackupDownloadsOnCellular()

        func showViewRecoveryKey()

        func showBackupSubscriptionAlreadyRedeemedSheet()
        func showBackupIAPNotFoundLocallySheet()
        func showBackgroundAppRefreshDisabledWarningSheet()
    }

    enum BackupSubscriptionLoadingState: Equatable {
        enum LoadedBackupSubscription: Equatable {
            case freeAndEnabled
            case freeAndDisabled
            case paidButFreeForTesters
            case paid(price: FiatMoney, renewalDate: Date)
            case paidButExpiring(expirationDate: Date)
            case paidButExpired(expirationDate: Date)
            case paidButFailedToRenew
            case paidButIAPNotFoundLocally
        }

        case loading
        case loaded(LoadedBackupSubscription)
        case networkError
        case genericError
    }

    @Published var backupSubscriptionConfiguration: BackupSubscriptionConfiguration

    @Published var backupSubscriptionLoadingState: BackupSubscriptionLoadingState
    @Published var backupSubscriptionAlreadyRedeemed: Bool

    @Published var backupPlan: BackupPlan
    @Published var failedToDisableBackupsRemotely: Bool

    @Published var latestBackupExportProgressUpdate: OWSSequentialProgress<BackupExportJobStep>?
    @Published var latestBackupAttachmentDownloadUpdate: BackupSettingsAttachmentDownloadTracker.DownloadUpdate?
    @Published var latestBackupAttachmentUploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate?

    @Published var lastBackupDetails: BackupSettingsStore.LastBackupDetails?
    @Published var shouldAllowBackupUploadsOnCellular: Bool

    /// Nil means has not consumed capacity; non-nil value represents the total byte count over
    /// the server side capacity all local attachments consume (meaning that's how many bytes
    /// the user has to delete to go back under storage quota).
    @Published var mediaTierCapacityOverflow: UInt64?
    /// Indicates that the user's Backup has failed recently, and we should show
    /// a corresponding error.
    @Published var hasBackupFailed: Bool
    /// Indicates that the "Background App Refresh" permission is disabled, and
    /// we should show a corresponding error. (This prevents `BGProcessingTask`
    /// from running.)
    @Published var isBackgroundAppRefreshDisabled: Bool

    weak var actionsDelegate: ActionsDelegate?

    init(
        backupSubscriptionConfiguration: BackupSubscriptionConfiguration,
        backupSubscriptionLoadingState: BackupSubscriptionLoadingState,
        backupSubscriptionAlreadyRedeemed: Bool,
        backupPlan: BackupPlan,
        failedToDisableBackupsRemotely: Bool,
        latestBackupExportProgressUpdate: OWSSequentialProgress<BackupExportJobStep>?,
        latestBackupAttachmentDownloadUpdate: BackupSettingsAttachmentDownloadTracker.DownloadUpdate?,
        latestBackupAttachmentUploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate?,
        lastBackupDetails: BackupSettingsStore.LastBackupDetails?,
        shouldAllowBackupUploadsOnCellular: Bool,
        mediaTierCapacityOverflow: UInt64?,
        hasBackupFailed: Bool,
        isBackgroundAppRefreshDisabled: Bool,
    ) {
        self.backupSubscriptionConfiguration = backupSubscriptionConfiguration

        self.backupSubscriptionLoadingState = backupSubscriptionLoadingState
        self.backupSubscriptionAlreadyRedeemed = backupSubscriptionAlreadyRedeemed

        self.backupPlan = backupPlan
        self.failedToDisableBackupsRemotely = failedToDisableBackupsRemotely

        self.latestBackupExportProgressUpdate = latestBackupExportProgressUpdate
        self.latestBackupAttachmentDownloadUpdate = latestBackupAttachmentDownloadUpdate
        self.latestBackupAttachmentUploadUpdate = latestBackupAttachmentUploadUpdate

        self.lastBackupDetails = lastBackupDetails
        self.shouldAllowBackupUploadsOnCellular = shouldAllowBackupUploadsOnCellular

        self.mediaTierCapacityOverflow = mediaTierCapacityOverflow
        self.hasBackupFailed = hasBackupFailed
        self.isBackgroundAppRefreshDisabled = isBackgroundAppRefreshDisabled
    }

    // MARK: -

    func enableBackups(planSelection: EnableBackupsPlanSelection, shouldShowWelcomeToBackupsSheet: Bool) {
        actionsDelegate?.enableBackups(
            planSelection: planSelection,
            shouldShowWelcomeToBackupsSheet: shouldShowWelcomeToBackupsSheet,
        )
    }

    func disableBackups() {
        actionsDelegate?.disableBackups()
    }

    // MARK: -

    var isPaidPlanTester: Bool {
        switch backupPlan {
        case .disabled, .disabling, .free, .paid, .paidExpiringSoon:
            false
        case .paidAsTester:
            true
        }
    }

    // MARK: -

    func loadBackupSubscription() {
        actionsDelegate?.loadBackupSubscription()
    }

    func showAppStoreManageSubscriptions() {
        actionsDelegate?.showAppStoreManageSubscriptions()
    }

    // MARK: -

    func performManualBackup() {
        actionsDelegate?.performManualBackup()
    }

    func cancelManualBackup() {
        actionsDelegate?.cancelManualBackup()
    }

    func suspendUploads() {
        actionsDelegate?.suspendUploads()
    }

    // MARK: -

    func setShouldAllowBackupUploadsOnCellular(_ newShouldAllowBackupUploadsOnCellular: Bool) {
        actionsDelegate?.setShouldAllowBackupUploadsOnCellular(newShouldAllowBackupUploadsOnCellular)
    }

    // MARK: -

    var optimizeLocalStorageAvailable: Bool {
        switch backupPlan {
        case .disabled, .disabling, .free:
            false
        case .paid, .paidExpiringSoon, .paidAsTester:
            true
        }
    }

    var optimizeLocalStorage: Bool {
        switch backupPlan {
        case .disabled, .disabling, .free:
            false
        case
            .paid(let optimizeLocalStorage),
            .paidExpiringSoon(let optimizeLocalStorage),
            .paidAsTester(let optimizeLocalStorage):
            optimizeLocalStorage
        }
    }

    func setOptimizeLocalStorage(_ newOptimizeLocalStorage: Bool) {
        actionsDelegate?.setOptimizeLocalStorage(newOptimizeLocalStorage)
    }

    // MARK: -

    func setIsBackupDownloadQueueSuspended(_ isSuspended: Bool) {
        actionsDelegate?.setIsBackupDownloadQueueSuspended(isSuspended, backupPlan: backupPlan)
    }

    func setShouldAllowBackupDownloadsOnCellular() {
        actionsDelegate?.setShouldAllowBackupDownloadsOnCellular()
    }

    // MARK: -

    func showViewRecoveryKey() {
        actionsDelegate?.showViewRecoveryKey()
    }

    // MARK: -

    func showBackupSubscriptionAlreadyRedeemedSheet() {
        actionsDelegate?.showBackupSubscriptionAlreadyRedeemedSheet()
    }

    func showBackupIAPNotFoundLocallySheet() {
        actionsDelegate?.showBackupIAPNotFoundLocallySheet()
    }

    func showBackgroundAppRefreshDisabledWarningSheet() {
        actionsDelegate?.showBackgroundAppRefreshDisabledWarningSheet()
    }
}

// MARK: -

struct BackupSettingsView: View {
    private enum Contents {
        case enabled
        case disablingDownloadsRunning(BackupSettingsAttachmentDownloadTracker.DownloadUpdate)
        case disabling
        case disabledFailedToDisableRemotely
        case disabled
    }

    private var contents: Contents {
        switch viewModel.backupPlan {
        case .free, .paid, .paidExpiringSoon, .paidAsTester:
            return .enabled
        case .disabled:
            if viewModel.failedToDisableBackupsRemotely {
                return .disabledFailedToDisableRemotely
            } else {
                return .disabled
            }
        case .disabling:
            let latestDownloadUpdate = viewModel.latestBackupAttachmentDownloadUpdate

            switch latestDownloadUpdate?.state {
            case nil, .suspended:
                return .disabling
            case .running, .pausedLowBattery, .pausedLowPowerMode, .pausedNeedsWifi, .pausedNeedsInternet, .outOfDiskSpace:
                return .disablingDownloadsRunning(latestDownloadUpdate!)
            }
        }
    }

    @ObservedObject private var viewModel: BackupSettingsViewModel

    fileprivate init(viewModel: BackupSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SignalList {
            SignalSection {
                Label {
                    Text(
                        OWSLocalizedString(
                            "BACKUP_SETTINGS_BETA_NOTICE_HEADER",
                            comment: "Notice that backups is a beta feature",
                        ),
                    )
                    .font(.subheadline)
                } icon: {
                    Image(uiImage: Theme.iconImage(.info))
                        .frame(width: 24, height: 24)
                }
                .padding(.vertical, 2)
                .foregroundColor(Color.Signal.label)
            }

            if viewModel.backupSubscriptionAlreadyRedeemed {
                SignalSection {
                    HStack(alignment: .center, spacing: 16) {
                        Image(.backupErrorBold)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.Signal.orange)

                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_SUBSCRIPTION_ALREADY_REDEEMED_NOTICE_TITLE",
                            comment: "Title for notice that the user's Backups subscription couldn't be redeemed.",
                        ))
                        .font(.subheadline)
                        .foregroundColor(Color.Signal.label)

                        Button {
                            viewModel.showBackupSubscriptionAlreadyRedeemedSheet()
                        } label: {
                            Text(OWSLocalizedString(
                                "BACKUP_SETTINGS_SUBSCRIPTION_ALREADY_REDEEMED_NOTICE_DETAIL_BUTTON",
                                comment: "Title for detail button in notice that the user's Backups subscription couldn't be redeemed.",
                            ))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Color.Signal.label)
                        }
                    }
                }
                .listRowBackground(Color.Signal.quaternaryFill)
            }

            SignalSection {
                BackupSubscriptionView(
                    backupSubscriptionConfiguration: viewModel.backupSubscriptionConfiguration,
                    loadingState: viewModel.backupSubscriptionLoadingState,
                    viewModel: viewModel,
                )
            }

            switch contents {
            case .enabled:
                if let latestBackupAttachmentDownloadUpdate = viewModel.latestBackupAttachmentDownloadUpdate {
                    SignalSection {
                        BackupAttachmentDownloadProgressView(
                            backupPlan: viewModel.backupPlan,
                            latestDownloadUpdate: latestBackupAttachmentDownloadUpdate,
                            viewModel: viewModel,
                        )
                    }
                }

            case .disablingDownloadsRunning(let lastDownloadUpdate):
                SignalSection {
                    BackupAttachmentDownloadProgressView(
                        backupPlan: viewModel.backupPlan,
                        latestDownloadUpdate: lastDownloadUpdate,
                        viewModel: viewModel,
                    )
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_DISABLING_DOWNLOADING_MEDIA_PROGRESS_VIEW_DESCRIPTION",
                        comment: "Description for a progress view tracking media being downloaded in service of disabling Backups.",
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }

            case .disabled, .disabling, .disabledFailedToDisableRemotely:
                EmptyView()
            }

            switch contents {
            case .enabled:
                SignalSection {
                    if viewModel.isBackgroundAppRefreshDisabled {
                        Label {
                            Text(OWSLocalizedString(
                                "BACKUP_SETTINGS_BACKGROUND_APP_REFRESH_DISABLED_MESSAGE",
                                comment: "Message describing that the Background App Refresh permission is disabled for Signal. \"Background App Refresh\" should be localized the same way it is in iOS Settings app permissions.",
                            ))
                            .appendLink(
                                OWSLocalizedString(
                                    "BACKUP_SETTINGS_BACKGROUND_APP_REFRESH_DISABLED_MESSAGE_UPDATE_NOW",
                                    comment: "Add-on to a message describing that the Background App Refresh permission is disabled for Signal. \"Background App Refresh\" should be localized the same way it is in iOS Settings app permissions.",
                                ),
                                useBold: true,
                                tint: .Signal.label,
                                action: {
                                    viewModel.showBackgroundAppRefreshDisabledWarningSheet()
                                },
                            )
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        } icon: {
                            YellowBadgeView()
                        }
                    }

                    if viewModel.hasBackupFailed {
                        Label {
                            Text(OWSLocalizedString(
                                "BACKUP_SETTINGS_BACKUP_FAILED_MESSAGE",
                                comment: "Message describing to the user that the last backup failed.",
                            ))
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        } icon: {
                            YellowBadgeView()
                        }
                    }

                    if let latestBackupExportProgressUpdate = viewModel.latestBackupExportProgressUpdate {
                        BackupExportProgressView(
                            latestExportProgressUpdate: latestBackupExportProgressUpdate,
                            latestAttachmentUploadUpdate: viewModel.latestBackupAttachmentUploadUpdate,
                        )

                        CancelManualBackupButton {
                            viewModel.cancelManualBackup()
                        }
                    } else if let mediaTierCapacityOverflow = viewModel.mediaTierCapacityOverflow {
                        VStack(alignment: .leading) {
                            Label {
                                Text(
                                    String(
                                        format: OWSLocalizedString(
                                            "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_PAUSED_OUT_OF_STORAGE_SPACE_FORMAT",
                                            comment: "Subtitle for a progress bar tracking uploads that are paused because the user is out of remote storage space. Embeds 1:{{ total storage space provided, e.g. 100 GB }}; 2:{{ space the user needs to free up by deleting media, e.g. 1 GB }}.",
                                        ),
                                        viewModel.backupSubscriptionConfiguration.storageAllowanceBytes.formatted(.owsByteCount(
                                            fudgeBase2ToBase10: true,
                                            zeroPadFractionDigits: false,
                                        )),
                                        max(
                                            // Always display at least 5 MB
                                            1000 * 1000 * 5,
                                            Int64(clamping: mediaTierCapacityOverflow),
                                        ).formatted(.owsByteCount()),
                                    ),
                                )
                                .appendLink(CommonStrings.learnMore, useBold: true, tint: .Signal.label) {
                                    CurrentAppContext().open(
                                        URL.Support.backups,
                                        completion: nil,
                                    )
                                }
                                .font(.subheadline)
                                .foregroundStyle(Color.Signal.label)
                                .monospacedDigit()
                                .multilineTextAlignment(.leading)
                            } icon: {
                                Image(.errorCircleFillCompact)
                            }
                        }
                        VStack(alignment: .leading) {
                            PerformManualBackupButton {
                                viewModel.performManualBackup()
                            }
                        }
                    } else if let latestBackupAttachmentUploadUpdate = viewModel.latestBackupAttachmentUploadUpdate {
                        BackupAttachmentUploadProgressView(
                            latestUploadUpdate: latestBackupAttachmentUploadUpdate,
                        )
                        CancelManualBackupButton {
                            viewModel.suspendUploads()
                        }
                    } else {
                        PerformManualBackupButton {
                            viewModel.performManualBackup()
                        }
                    }
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_ENABLED_SECTION_HEADER",
                        comment: "Header for a menu section related to settings for when Backups are enabled.",
                    ))
                }

                SignalSection {
                    BackupDetailsView(
                        lastBackupDetails: viewModel.lastBackupDetails,
                        shouldAllowBackupUploadsOnCellular: viewModel.shouldAllowBackupUploadsOnCellular,
                        viewModel: viewModel,
                    )

                    if BuildFlags.Backups.showOptimizeMedia {
                        Toggle(
                            OWSLocalizedString(
                                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_TOGGLE_TITLE",
                                comment: "Title for a toggle allowing users to change the Optimize Local Storage setting.",
                            ),
                            isOn: Binding(
                                get: { viewModel.optimizeLocalStorage },
                                set: { viewModel.setOptimizeLocalStorage($0) },
                            ),
                        ).disabled(!viewModel.optimizeLocalStorageAvailable)
                    }
                } footer: {
                    if BuildFlags.Backups.showOptimizeMedia {
                        let footerText: String = if
                            viewModel.optimizeLocalStorageAvailable,
                            viewModel.isPaidPlanTester
                        {
                            OWSLocalizedString(
                                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_TOGGLE_FOOTER_AVAILABLE_FOR_TESTERS",
                                comment: "Footer for a toggle allowing users to change the Optimize Local Storage setting, if the toggle is available and they are a tester.",
                            )
                        } else if viewModel.optimizeLocalStorageAvailable {
                            OWSLocalizedString(
                                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_TOGGLE_FOOTER_AVAILABLE",
                                comment: "Footer for a toggle allowing users to change the Optimize Local Storage setting, if the toggle is available.",
                            )
                        } else {
                            OWSLocalizedString(
                                "BACKUP_SETTINGS_OPTIMIZE_LOCAL_STORAGE_TOGGLE_FOOTER_UNAVAILABLE",
                                comment: "Footer for a toggle allowing users to change the Optimize Local Storage setting, if the toggle is unavailable.",
                            )
                        }

                        Text(footerText)
                            .foregroundStyle(Color.Signal.secondaryLabel)
                            .font(.caption)
                    }
                }

                SignalSection {
                    Button {
                        viewModel.disableBackups()
                    } label: {
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_DISABLE_BACKUPS_BUTTON_TITLE",
                            comment: "Title for a button allowing users to turn off Backups.",
                        ))
                        .foregroundStyle(Color.Signal.red)
                    }
                } footer: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_DISABLE_BACKUPS_BUTTON_FOOTER",
                        comment: "Footer for a menu section allowing users to turn off Backups.",
                    ))
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }

            case .disablingDownloadsRunning:
                // Download progress is shown in the section above this, so don't show
                // anything here until the downloads complete.
                EmptyView()

            case .disabling:
                SignalSection {
                    VStack(alignment: .leading) {
                        StyledProgressBar(style: .indeterminate)

                        Spacer().frame(height: 8)

                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUPS_DISABLING_PROGRESS_VIEW_DESCRIPTION",
                            comment: "Description for a progress view tracking Backups being disabled.",
                        ))
                        .foregroundStyle(Color.Signal.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_DISABLING_SECTION_HEADER",
                        comment: "Header for a menu section related to disabling Backups.",
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }

            case .disabled:
                SignalSection {
                    ReenableBackupsButton(
                        backupSubscriptionLoadingState: viewModel.backupSubscriptionLoadingState,
                        viewModel: viewModel,
                    )
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_DISABLED_SECTION_FOOTER",
                        comment: "Footer for a menu section related to settings for when Backups are disabled.",
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }

                SignalSection {
                    BackupViewKeyView(viewModel: viewModel)
                }

            case .disabledFailedToDisableRemotely:
                SignalSection {
                    VStack(alignment: .center) {
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUPS_DISABLING_GENERIC_ERROR_TITLE",
                            comment: "Title for a view indicating we failed to delete the user's Backup due to an unexpected error.",
                        ))
                        .bold()
                        .foregroundStyle(Color.Signal.secondaryLabel)

                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUPS_DISABLING_GENERIC_ERROR_MESSAGE",
                            comment: "Message for a view indicating we failed to delete the user's Backup due to an unexpected error.",
                        ))
                        .font(.subheadline)
                        .foregroundStyle(Color.Signal.secondaryLabel)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_DISABLING_GENERIC_ERROR_SECTION_HEADER",
                        comment: "Header for a menu section related to settings for when disabling Backups encountered an unexpected error.",
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }

                SignalSection {
                    ReenableBackupsButton(
                        backupSubscriptionLoadingState: viewModel.backupSubscriptionLoadingState,
                        viewModel: viewModel,
                    )
                }

                SignalSection {
                    BackupViewKeyView(viewModel: viewModel)
                }
            }
        }
    }
}

private struct YellowBadgeView: View {
    var body: some View {
        VStack {
            Spacer().frame(height: 6)
            Circle()
                .frame(width: 10, height: 10)
                .foregroundStyle(Color.Signal.yellow)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ReenableBackupsButton: View {
    let backupSubscriptionLoadingState: BackupSettingsViewModel.BackupSubscriptionLoadingState
    let viewModel: BackupSettingsViewModel

    private var enableBackupsPlanSelection: BackupSettingsViewModel.EnableBackupsPlanSelection? {
        switch backupSubscriptionLoadingState {
        case .loading, .networkError:
            // Don't let them reenable until we know more.
            return nil
        case
            .loaded(.freeAndEnabled),
            .loaded(.freeAndDisabled),
            .loaded(.paidButFreeForTesters),
            .loaded(.paidButExpired),
            .loaded(.paidButFailedToRenew),
            .loaded(.paidButIAPNotFoundLocally),
            .genericError:
            return .userChoice(initialSelection: nil)
        case .loaded(.paid), .loaded(.paidButExpiring):
            // They're currently paid, so automatically reenable with paid.
            return .required(.paid)
        }
    }

    var body: some View {
        if let enableBackupsPlanSelection {
            Button {
                viewModel.enableBackups(
                    planSelection: enableBackupsPlanSelection,
                    shouldShowWelcomeToBackupsSheet: true,
                )
            } label: {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_REENABLE_BACKUPS_BUTTON_TITLE",
                    comment: "Title for a button allowing users to re-enable Backups, after it had been previously disabled.",
                ))
                .foregroundStyle(Color.Signal.label)
            }
        }
    }
}

// MARK: -

private struct BackupExportProgressView: View {
    private struct ProgressBarState {
        let style: StyledProgressBar.Style
        let label: String
    }

    let latestExportProgressUpdate: OWSSequentialProgress<BackupExportJobStep>
    let latestAttachmentUploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate?

    private var progressBarState: ProgressBarState {
        switch latestExportProgressUpdate.currentStep {
        case .backupExport, .backupUpload:
            let percentExportCompleted = latestExportProgressUpdate.progress(for: .backupExport)?.percentComplete ?? 0
            let percentUploadCompleted = latestExportProgressUpdate.progress(for: .backupUpload)?.percentComplete ?? 0
            let percentComplete = (0.95 * percentExportCompleted) + (0.05 * percentUploadCompleted)
            return ProgressBarState(
                style: .determinate(percentComplete: percentComplete),
                label: String(
                    format: OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_EXPORT_PROGRESS_DESCRIPTION_PREPARING_BACKUP",
                        comment: "Description for a progress bar tracking the preparation of a Backup. Embeds 1:{{ the percentage completed preformatted as a percent, e.g. 10% }}.",
                    ),
                    percentComplete.formatted(.percent.precision(.fractionLength(0))),
                ),
            )

        case .listMedia, .attachmentOrphaning,
             .attachmentUpload where latestAttachmentUploadUpdate == nil:
            return ProgressBarState(
                style: .indeterminate,
                label: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_PROGRESS_DESCRIPTION_PROCESSING_MEDIA",
                    comment: "Description for a progress bar tracking the processing of Backup media.",
                ),
            )

        case .attachmentUpload:
            // If this is nil, we'll be in the case above.
            let latestAttachmentUploadUpdate = latestAttachmentUploadUpdate!

            return ProgressBarState(
                style: .determinate(percentComplete: latestAttachmentUploadUpdate.percentageUploaded),
                label: BackupAttachmentUploadProgressView.subtitleText(
                    uploadUpdate: latestAttachmentUploadUpdate,
                ),
            )

        case .offloading:
            return ProgressBarState(
                style: .indeterminate,
                label: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_PROGRESS_DESCRIPTION_OPTIMIZING_MEDIA",
                    comment: "Description for a progress bar tracking the optimizing of Backup media.",
                ),
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            let progressBarState = self.progressBarState

            StyledProgressBar(style: progressBarState.style)

            Text(progressBarState.label)
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .monospacedDigit()
        }
    }
}

// MARK: -

private struct CancelManualBackupButton: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_MANUAL_BACKUP_CANCEL_BUTTON",
                comment: "Title for a button shown under a progress bar tracking a manual backup, which lets the user cancel the backup.",
            ))
        }
        .foregroundStyle(Color.Signal.label)
    }
}

private struct PerformManualBackupButton: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            Label {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_MANUAL_BACKUP_BUTTON_TITLE",
                    comment: "Title for a button allowing users to trigger a manual backup.",
                ))
            } icon: {
                Image(uiImage: .backup)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
        }
        .foregroundStyle(Color.Signal.label)
    }
}

// MARK: -

private struct StyledProgressBar: View {
    enum Style {
        case determinate(percentComplete: Float)
        case indeterminate
    }

    let style: Style

    var body: some View {
        VStack {
            switch style {
            case .determinate(let percentComplete):
                PulsingProgressBar(value: percentComplete)
                    .tint(.Signal.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            case .indeterminate:
                LottieView(animation: .named("linear_indeterminate"))
                    .playing(loopMode: .loop)
                    .background {
                        Capsule().fill(Color.Signal.secondaryFill)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .scaleEffect(x: 1, y: 1.5)
        .padding(.vertical, 12)
    }
}

private struct PulsingProgressBar: View {
    struct ClearTrackProgressView: UIViewRepresentable {
        let value: Float
        let tintColor: UIColor

        func makeUIView(context: Context) -> UIProgressView {
            let progressView = UIProgressView()
            progressView.trackTintColor = .clear
            progressView.progressTintColor = tintColor
            return progressView
        }

        func updateUIView(_ uiView: UIProgressView, context: Context) {
            uiView.setProgress(value, animated: false)
        }
    }

    let value: Float
    let animationDuration: TimeInterval = 1
    let stopAfter: TimeInterval = 3

    init(value: Float) {
        self.value = value
    }

    @State private var animationPart1Progress: Float = 0
    @State private var animationPart2Progress: Float = 0
    @State private var animationPart3Progress: Float = 0
    @State private var lastValue: Float?
    @State private var isAnimating = true
    @State private var animationTimer: Timer?
    @State private var animationStopTimer: Timer?

    var body: some View {
        ZStack {
            ProgressView(value: value)
                .progressViewStyle(.linear)
            ClearTrackProgressView(
                value: value * animationPart1Progress,
                tintColor: .tintColor
                    .blended(with: .white, alpha: 0.2),
            )
            ClearTrackProgressView(
                value: value * animationPart2Progress,
                tintColor: .tintColor,
            )
            .onAppear {
                // The animation gets started once and runs forever;
                // it just no-ops on each loop if not animating.
                startLoopingAnimation()
            }
            .onChange(of: value) { newValue in
                if lastValue != newValue {
                    // When the value changes, reset
                    // the stop timer.
                    startStopTimer()
                }
            }
            .onDisappear {
                self.animationTimer?.invalidate()
                self.animationTimer = nil
                self.animationStopTimer?.invalidate()
                self.animationStopTimer = nil
                self.isAnimating = true
            }
        }
    }

    private func startLoopingAnimation() {
        self.animationTimer = Timer.scheduledTimer(
            withTimeInterval: animationDuration / 100,
            repeats: true,
            block: { _ in
                // Don't animate under 20%; it looks ugly
                guard self.isAnimating, (self.lastValue ?? 0) > 0.2 else {
                    animationPart1Progress = 0
                    animationPart2Progress = 0
                    animationPart3Progress = 0
                    return
                }
                if animationPart1Progress < 0.75 {
                    animationPart1Progress += 0.01
                } else if animationPart2Progress < 0.99 {
                    if animationPart1Progress < 0.99 {
                        animationPart1Progress += 0.01
                    }
                    animationPart2Progress += 0.01
                } else if animationPart3Progress < 1 {
                    animationPart3Progress += 0.01
                } else {
                    animationPart1Progress = 0
                    animationPart2Progress = 0
                    animationPart3Progress = 0
                }
            },
        )
        startStopTimer()
    }

    /// We stop the animation after stopAfter seconds of no updates.
    private func startStopTimer() {
        self.animationStopTimer?.invalidate()
        self.isAnimating = true
        self.animationStopTimer = Timer.scheduledTimer(
            withTimeInterval: stopAfter,
            repeats: false,
            block: { [self] _ in
                self.isAnimating = false
            },
        )
        self.lastValue = value
    }
}

// MARK: -

private struct BackupAttachmentDownloadProgressView: View {
    let backupPlan: BackupPlan
    let latestDownloadUpdate: BackupSettingsAttachmentDownloadTracker.DownloadUpdate
    let viewModel: BackupSettingsViewModel

    var body: some View {
        VStack(alignment: .leading) {
            let progressViewColor: Color? = switch latestDownloadUpdate.state {
            case .suspended:
                nil
            case .running, .pausedLowBattery, .pausedLowPowerMode, .pausedNeedsWifi, .pausedNeedsInternet:
                .Signal.accent
            case .outOfDiskSpace:
                .yellow
            }

            let subtitleText: String = switch latestDownloadUpdate.state {
            case .suspended:
                switch backupPlan {
                case .disabled, .free, .paid, .paidAsTester:
                    String(
                        format: OWSLocalizedString(
                            "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_SUSPENDED",
                            comment: "Subtitle for a view explaining that downloads are available but not running. Embeds {{ the amount available to download as a file size, e.g. 100 MB }}.",
                        ),
                        latestDownloadUpdate.totalBytesToDownload.formatted(.owsByteCount()),
                    )
                case .disabling, .paidExpiringSoon:
                    String(
                        format: OWSLocalizedString(
                            "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_SUSPENDED_PAID_SUBSCRIPTION_EXPIRING",
                            comment: "Subtitle for a view explaining that downloads are available but not running, and the user's paid subscription is expiring. Embeds {{ the amount available to download as a file size, e.g. 100 MB }}.",
                        ),
                        latestDownloadUpdate.totalBytesToDownload.formatted(.owsByteCount()),
                    )
                }
            case .running:
                String(
                    format: OWSLocalizedString(
                        "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_RUNNING",
                        comment: "Subtitle for a progress bar tracking active downloading. Embeds 1:{{ the amount downloaded as a file size, e.g. 100 MB }}; 2:{{ the total amount to download as a file size, e.g. 1 GB }}; 3:{{ the amount downloaded as a percentage, e.g. 10% }}.",
                    ),
                    latestDownloadUpdate.bytesDownloaded.formatted(.owsByteCount()),
                    latestDownloadUpdate.totalBytesToDownload.formatted(.owsByteCount()),
                    latestDownloadUpdate.percentageDownloaded.formatted(.percent.precision(.fractionLength(0))),
                )
            case .pausedLowBattery:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_PAUSED_LOW_BATTERY",
                    comment: "Subtitle for a progress bar tracking downloads that are paused because of low battery.",
                )
            case .pausedLowPowerMode:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_PAUSED_LOW_POWER_MODE",
                    comment: "Subtitle for a progress bar tracking downloads that are paused because of low power mode.",
                )
            case .pausedNeedsWifi:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_PAUSED_NEEDS_WIFI",
                    comment: "Subtitle for a progress bar tracking downloads that are paused because they need WiFi.",
                )
            case .pausedNeedsInternet:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_PAUSED_NEEDS_INTERNET",
                    comment: "Subtitle for a progress bar tracking downloads that are paused because they need internet.",
                )
            case .outOfDiskSpace(let bytesRequired):
                String(
                    format: OWSLocalizedString(
                        "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_SUBTITLE_PAUSED_NEEDS_DISK_SPACE",
                        comment: "Subtitle for a progress bar tracking downloads that are paused because they need more disk space available. Embeds {{ the amount of space needed as a file size, e.g. 100 MB }}.",
                    ),
                    bytesRequired.formatted(.owsByteCount()),
                )
            }

            if let progressViewColor {
                PulsingProgressBar(value: latestDownloadUpdate.percentageDownloaded)
                    .tint(progressViewColor)
                    .scaleEffect(x: 1, y: 1.5)
                    .padding(.vertical, 12)

                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .monospacedDigit()
            } else {
                Text(subtitleText)
            }
        }

        switch latestDownloadUpdate.state {
        case .suspended:
            Button {
                viewModel.setIsBackupDownloadQueueSuspended(false)
            } label: {
                Label {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_ACTION_BUTTON_INITIATE_DOWNLOAD",
                        comment: "Title for a button shown in Backup Settings that lets a user initiate an available download.",
                    ))
                    .foregroundStyle(Color.Signal.label)
                } icon: {
                    Image(uiImage: .arrowCircleDown)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
            }
            .foregroundStyle(Color.Signal.label)
        case .running, .outOfDiskSpace:
            Button {
                viewModel.setIsBackupDownloadQueueSuspended(true)
            } label: {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_ACTION_BUTTON_CANCEL_DOWNLOAD",
                    comment: "Title for a button shown in Backup Settings that lets a user cancel an in-progress download.",
                ))
            }
            .foregroundStyle(Color.Signal.label)
        case .pausedNeedsWifi:
            Button {
                viewModel.setShouldAllowBackupDownloadsOnCellular()
            } label: {
                Label {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_DOWNLOAD_PROGRESS_ACTION_BUTTON_RESUME_DOWNLOAD_WITHOUT_WIFI",
                        comment: "Title for a button shown in Backup Settings that lets a user resume a download paused due to needing Wi-Fi.",
                    ))
                } icon: {
                    Image(uiImage: .arrowCircleDown)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
            }
            .foregroundStyle(Color.Signal.label)
        case .pausedLowBattery, .pausedLowPowerMode, .pausedNeedsInternet:
            EmptyView()
        }
    }
}

// MARK: -

private struct BackupAttachmentUploadProgressView: View {
    let latestUploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate

    var body: some View {
        VStack(alignment: .leading) {
            PulsingProgressBar(value: latestUploadUpdate.percentageUploaded)
                .tint(Color.Signal.accent)
                .scaleEffect(x: 1, y: 1.5)
                .padding(.vertical, 12)

            let subtitleText: String = Self.subtitleText(uploadUpdate: latestUploadUpdate)
            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .monospacedDigit()
        }
    }

    static func subtitleText(
        uploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate,
    ) -> String {
        switch uploadUpdate.state {
        case .running:
            let bytesUploaded = uploadUpdate.bytesUploaded
            let totalBytesToUpload = uploadUpdate.totalBytesToUpload
            let percentageUploaded = uploadUpdate.percentageUploaded

            return String(
                format: OWSLocalizedString(
                    "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_RUNNING",
                    comment: "Subtitle for a progress bar tracking active uploading. Embeds 1:{{ the amount uploaded as a file size, e.g. 100 MB }}; 2:{{ the total amount to upload as a file size, e.g. 1 GB }}; 3:{{ the percentage uploaded as a percent, e.g. 40% }}.",
                ),
                bytesUploaded.formatted(.owsByteCount()),
                totalBytesToUpload.formatted(.owsByteCount()),
                percentageUploaded.formatted(.percent.precision(.fractionLength(0))),
            )
        case .pausedLowBattery:
            return OWSLocalizedString(
                "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_PAUSED_LOW_BATTERY",
                comment: "Subtitle for a progress bar tracking uploads that are paused because of low battery.",
            )
        case .pausedLowPowerMode:
            return OWSLocalizedString(
                "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_PAUSED_LOW_POWER_MODE",
                comment: "Subtitle for a progress bar tracking uploads that are paused because of low power mode.",
            )
        case .pausedNeedsWifi:
            return OWSLocalizedString(
                "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_PAUSED_NEEDS_WIFI",
                comment: "Subtitle for a progress bar tracking uploads that are paused because they need WiFi.",
            )
        case .pausedNeedsInternet:
            return OWSLocalizedString(
                "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_PAUSED_NEEDS_INTERNET",
                comment: "Subtitle for a progress bar tracking uploads that are paused because they need an internet connection",
            )
        }
    }
}

// MARK: -

private struct BackupSubscriptionView: View {
    let backupSubscriptionConfiguration: BackupSubscriptionConfiguration
    let loadingState: BackupSettingsViewModel.BackupSubscriptionLoadingState
    let viewModel: BackupSettingsViewModel

    var body: some View {
        switch loadingState {
        case .loading:
            VStack(alignment: .center) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    // Force SwiftUI to redraw this if it re-appears (e.g.,
                    // because the user retried loading) instead of reusing one
                    // that will have stopped animating.
                    .id(UUID())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
        case .loaded(let loadedBackupSubscription):
            BackupSubscriptionLoadedView(
                backupSubscriptionConfiguration: backupSubscriptionConfiguration,
                loadedBackupSubscription: loadedBackupSubscription,
                viewModel: viewModel,
            )
        case .networkError:
            VStack(alignment: .center) {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_NETWORK_ERROR_TITLE",
                    comment: "Title for a view indicating we failed to fetch someone's Backup plan due to a network error.",
                ))
                .font(.subheadline)
                .bold()
                .foregroundStyle(Color.Signal.secondaryLabel)

                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_NETWORK_ERROR_MESSAGE",
                    comment: "Message for a view indicating we failed to fetch someone's Backup plan due to a network error.",
                ))
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer().frame(height: 16)

                Button {
                    viewModel.loadBackupSubscription()
                } label: {
                    Text(CommonStrings.retryButton)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(Color.Signal.secondaryFill)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 140)
        case .genericError:
            VStack(alignment: .center) {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_GENERIC_ERROR_TITLE",
                    comment: "Title for a view indicating we failed to fetch someone's Backup plan due to an unexpected error.",
                ))
                .font(.subheadline)
                .bold()
                .foregroundStyle(Color.Signal.secondaryLabel)

                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_GENERIC_ERROR_MESSAGE",
                    comment: "Message for a view indicating we failed to fetch someone's Backup plan due to an unexpected error.",
                ))
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 140)
        }
    }
}

private struct BackupSubscriptionLoadedView: View {
    let backupSubscriptionConfiguration: BackupSubscriptionConfiguration
    let loadedBackupSubscription: BackupSettingsViewModel.BackupSubscriptionLoadingState.LoadedBackupSubscription
    let viewModel: BackupSettingsViewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    headerView()
                    descriptionView()
                }

                Spacer()

                Group {
                    switch loadedBackupSubscription {
                    case
                        .freeAndEnabled,
                        .freeAndDisabled,
                        .paidButFreeForTesters,
                        .paid,
                        .paidButExpiring,
                        .paidButExpired,
                        .paidButFailedToRenew:
                        Image(.backupsSubscribed).resizable()
                    case .paidButIAPNotFoundLocally:
                        Image(.backupsLogoWarningBadged).resizable()
                    }
                }
                .frame(width: 64, height: 64)
                .padding(.leading, 16)
            }

            buttonsView()
        }
        .padding(4)
    }

    @ViewBuilder
    private func headerView() -> some View {
        switch loadedBackupSubscription {
        case .freeAndEnabled, .freeAndDisabled:
            Text(String.localizedStringWithFormat(
                OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_FREE_HEADER_%d",
                    tableName: "PluralAware",
                    comment: "Header describing what the free backup plan includes. Embeds {{ the number of days that files are available, e.g. '45' }}.",
                ),
                backupSubscriptionConfiguration.freeTierMediaDays,
            ))
            .font(.subheadline)
            .foregroundStyle(Color.Signal.secondaryLabel)

            Spacer().frame(height: 8)
        case .paidButFreeForTesters, .paid, .paidButExpiring, .paidButExpired, .paidButFailedToRenew:
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_HEADER",
                comment: "Header describing what the paid backup plan includes.",
            ))
            .font(.subheadline)
            .foregroundStyle(Color.Signal.secondaryLabel)

            Spacer().frame(height: 8)
        case .paidButIAPNotFoundLocally:
            EmptyView()
        }
    }

    @ViewBuilder
    private func descriptionView() -> some View {
        switch loadedBackupSubscription {
        case .freeAndEnabled:
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_FREE_DESCRIPTION",
                comment: "Text describing the user's free backup plan.",
            ))
        case .freeAndDisabled:
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_FREE_AND_DISABLED_DESCRIPTION",
                comment: "Text describing the user's free backup plan when they have Backups disabled.",
            ))
        case .paidButFreeForTesters:
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_FREE_FOR_TESTERS_DESCRIPTION",
                comment: "Text describing that the user's backup plan is paid, but free for them as a tester.",
            ))
        case .paid(let price, let renewalDate):
            let priceStringFormat = OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_PRICE_FORMAT",
                comment: "Text explaining the price of the user's paid backup plan. Embeds {{ the formatted price }}.",
            )
            Text(String(
                format: priceStringFormat,
                CurrencyFormatter.format(money: price),
            ))

            let renewalStringFormat = OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_RENEWAL_FORMAT",
                comment: "Text explaining when the user's paid backup plan renews. Embeds {{ the formatted renewal date }}.",
            )
            Text(String(
                format: renewalStringFormat,
                DateFormatter.localizedString(from: renewalDate, dateStyle: .medium, timeStyle: .none),
            ))
        case .paidButExpiring(let expirationDate), .paidButExpired(let expirationDate):
            let expirationDateFormatString = switch loadedBackupSubscription {
            case .freeAndEnabled, .freeAndDisabled, .paidButFreeForTesters, .paid, .paidButFailedToRenew, .paidButIAPNotFoundLocally:
                owsFail("Not possible")
            case .paidButExpiring:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_CANCELED_FUTURE_EXPIRATION_FORMAT",
                    comment: "Text explaining that a user's paid plan, which has been canceled, will expire on a future date. Embeds {{ the formatted expiration date }}.",
                )
            case .paidButExpired:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_CANCELED_PAST_EXPIRATION_FORMAT",
                    comment: "Text explaining that a user's paid plan, which has been canceled, expired on a past date. Embeds {{ the formatted expiration date }}.",
                )
            }

            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_CANCELED_DESCRIPTION",
                comment: "Text describing that the user's paid backup plan has been canceled.",
            ))
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Color.Signal.red)

            Text(String(
                format: expirationDateFormatString,
                DateFormatter.localizedString(from: expirationDate, dateStyle: .medium, timeStyle: .none),
            ))
        case .paidButFailedToRenew:
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_FAILED_TO_RENEW_DESCRIPTION_1",
                comment: "Text describing that the user's paid backup plan has failed to renew.",
            ))
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Color.Signal.red)

            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_FAILED_TO_RENEW_DESCRIPTION_2",
                comment: "Text describing that the user's paid backup plan has failed to renew.",
            ))
        case .paidButIAPNotFoundLocally:
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_IAP_NOT_FOUND_LOCALLY_DESCRIPTION",
                comment: "Text describing that the user's paid backup plan did not correspond to a App Store subscription on this device.",
            ))
        }
    }

    @ViewBuilder
    private func buttonsView() -> some View {
        switch loadedBackupSubscription {
        case .freeAndEnabled:
            loadedViewButton(
                label: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_FREE_ACTION_BUTTON_TITLE",
                    comment: "Title for a button allowing users to upgrade from a free to paid backup plan.",
                ),
                action: {
                    viewModel.enableBackups(
                        planSelection: .userChoice(initialSelection: .free),
                        shouldShowWelcomeToBackupsSheet: false,
                    )
                },
            )
        case .freeAndDisabled:
            // We already expose a "reenable Backups" button, so no need here.
            EmptyView()
        case .paidButFreeForTesters:
            loadedViewButton(
                label: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_FREE_FOR_TESTERS_ACTION_BUTTON_TITLE",
                    comment: "Title for a button allowing users to manage their backup plan as a tester.",
                ),
                action: {
                    viewModel.enableBackups(
                        planSelection: .userChoice(initialSelection: .paid),
                        shouldShowWelcomeToBackupsSheet: false,
                    )
                },
            )
        case .paid:
            loadedViewButton(
                label: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_PAID_ACTION_BUTTON_TITLE",
                    comment: "Title for a button allowing users to manage or cancel their paid backup plan.",
                ),
                action: {
                    viewModel.showAppStoreManageSubscriptions()
                },
            )
        case .paidButExpiring, .paidButExpired:
            loadedViewButton(
                label: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_CANCELED_ACTION_BUTTON_TITLE",
                    comment: "Title for a button allowing users to reenable a paid backup plan that has been canceled.",
                ),
                action: {
                    viewModel.showAppStoreManageSubscriptions()
                },
            )
        case .paidButFailedToRenew:
            loadedViewButton(
                label: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_FAILED_TO_RENEW_ACTION_BUTTON_TITLE",
                    comment: "Title for a button allowing users to manage a paid backup plan that failed to renew.",
                ),
                action: {
                    viewModel.showAppStoreManageSubscriptions()
                },
            )
        case .paidButIAPNotFoundLocally:
            HStack(spacing: 16) {
                loadedViewButton(
                    label: OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_IAP_NOT_FOUND_LOCALLY_ACTION_BUTTON_TITLE",
                        comment: "Title for a button allowing users to renew their backup subscription on this device.",
                    ),
                    expandWidth: true,
                    action: {
                        viewModel.enableBackups(
                            planSelection: .userChoice(initialSelection: nil),
                            shouldShowWelcomeToBackupsSheet: false,
                        )
                    },
                )

                loadedViewButton(
                    label: CommonStrings.learnMore,
                    expandWidth: true,
                    action: {
                        viewModel.showBackupIAPNotFoundLocallySheet()
                    },
                )
            }
        }
    }

    /// - Parameter expandWidth
    /// If true, the returned Button will expand its width to fill its container
    /// rather than just encapsulate its label.
    @ViewBuilder
    private func loadedViewButton(
        label: String,
        expandWidth: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button {
            action()
        } label: {
            Text(label)
                .frame(maxWidth: expandWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .foregroundStyle(Color.Signal.label)
        .font(.subheadline.weight(.medium))
        .padding(.top, 4)
    }
}

// MARK: -

private struct BackupDetailsView: View {
    let lastBackupDetails: BackupSettingsStore.LastBackupDetails?
    let shouldAllowBackupUploadsOnCellular: Bool
    let viewModel: BackupSettingsViewModel

    var body: some View {
        HStack {
            let lastBackupMessage: String? = {
                guard let lastBackupDate = lastBackupDetails?.date else {
                    return nil
                }

                let lastBackupDateString = DateFormatter.localizedString(from: lastBackupDate, dateStyle: .medium, timeStyle: .none)
                let lastBackupTimeString = DateFormatter.localizedString(from: lastBackupDate, dateStyle: .none, timeStyle: .short)

                if Calendar.current.isDateInToday(lastBackupDate) {
                    let todayFormatString = OWSLocalizedString(
                        "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_TODAY_FORMAT",
                        comment: "Text explaining that the user's last backup was today. Embeds {{ the time of the backup }}.",
                    )

                    return String(format: todayFormatString, lastBackupTimeString)
                } else if Calendar.current.isDateInYesterday(lastBackupDate) {
                    let yesterdayFormatString = OWSLocalizedString(
                        "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_YESTERDAY_FORMAT",
                        comment: "Text explaining that the user's last backup was yesterday. Embeds {{ the time of the backup }}.",
                    )

                    return String(format: yesterdayFormatString, lastBackupTimeString)
                } else {
                    let pastFormatString = OWSLocalizedString(
                        "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_PAST_FORMAT",
                        comment: "Text explaining that the user's last backup was in the past. Embeds 1:{{ the date of the backup }} and 2:{{ the time of the backup }}.",
                    )

                    return String(format: pastFormatString, lastBackupDateString, lastBackupTimeString)
                }
            }()

            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_LABEL",
                comment: "Label for a menu item explaining when the user's last backup occurred.",
            ))
            Spacer()
            if let lastBackupMessage {
                Text(lastBackupMessage)
                    .foregroundStyle(Color.Signal.secondaryLabel)
            }
        }

        if let lastBackupSizeBytes = lastBackupDetails?.backupTotalSizeBytes {
            HStack {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_BACKUP_SIZE_LABEL",
                    comment: "Label for a menu item explaining the size of the user's backup.",
                ))
                Spacer()
                Text(lastBackupSizeBytes.formatted(.owsByteCount()))
                    .foregroundStyle(Color.Signal.secondaryLabel)
            }
        }

        BackupViewKeyView(viewModel: viewModel)

        Toggle(
            OWSLocalizedString(
                "BACKUP_SETTINGS_ENABLED_BACKUP_ON_CELLULAR_LABEL",
                comment: "Label for a toggleable menu item describing whether to make backups on cellular data.",
            ),
            isOn: Binding(
                get: { shouldAllowBackupUploadsOnCellular },
                set: { viewModel.setShouldAllowBackupUploadsOnCellular($0) },
            ),
        )
    }
}

// MARK: -

private struct BackupViewKeyView: View {
    let viewModel: BackupSettingsViewModel

    var body: some View {
        Button {
            viewModel.showViewRecoveryKey()
        } label: {
            HStack {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_VIEW_BACKUP_KEY_LABEL",
                    comment: "Label for a menu item offering to show the user their recovery key.",
                ))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.Signal.secondaryLabel)
            }
        }
        .foregroundStyle(Color.Signal.label)
    }
}

// MARK: - Previews

#if DEBUG

private extension OWSSequentialProgress<BackupExportJobStep> {
    static func forPreview(
        _ step: BackupExportJobStep,
        _ progress: Float,
    ) -> OWSSequentialProgress<BackupExportJobStep> {
        return OWSProgress(
            completedUnitCount: UInt64(progress * 100),
            totalUnitCount: 100,
            childProgresses: [
                step.rawValue: [OWSProgress.ChildProgress(
                    completedUnitCount: 1,
                    totalUnitCount: 2,
                    label: step.rawValue,
                    parentLabel: nil,
                )],
            ],
        ).sequential(BackupExportJobStep.self)
    }
}

private extension BackupSettingsViewModel {
    static func forPreview(
        backupSubscriptionLoadingState: BackupSubscriptionLoadingState,
        backupPlan: BackupPlan,
        backupSubscriptionAlreadyRedeemed: Bool = false,
        failedToDisableBackupsRemotely: Bool = false,
        latestBackupExportProgressUpdate: OWSSequentialProgress<BackupExportJobStep>? = nil,
        latestBackupAttachmentDownloadUpdateState: BackupSettingsAttachmentDownloadTracker.DownloadUpdate.State? = nil,
        latestBackupAttachmentUploadUpdateState: BackupSettingsAttachmentUploadTracker.UploadUpdate.State? = nil,
        mediaTierCapacityOverflow: UInt64? = nil,
        hasBackupFailed: Bool = false,
        isBackgroundAppRefreshDisabled: Bool = false,
    ) -> BackupSettingsViewModel {
        class PreviewActionsDelegate: ActionsDelegate {
            func enableBackups(planSelection: EnableBackupsPlanSelection, shouldShowWelcomeToBackupsSheet: Bool) { print("Enabling! planSelection: \(planSelection)") }
            func disableBackups() { print("Disabling!") }

            func loadBackupSubscription() { print("Loading BackupSubscription!") }
            func showAppStoreManageSubscriptions() { print("AppStore Manage Subscriptions!") }

            func performManualBackup() { print("Manually backing up!") }
            func cancelManualBackup() { print("Canceling manual backup!") }
            func suspendUploads() { print("Manually suspending uploads!") }

            func setShouldAllowBackupUploadsOnCellular(_ newShouldAllowBackupUploadsOnCellular: Bool) { print("Uploads on cellular: \(newShouldAllowBackupUploadsOnCellular)") }

            func setOptimizeLocalStorage(_ newOptimizeLocalStorage: Bool) { print("Optimize local storage: \(newOptimizeLocalStorage)") }

            func setIsBackupDownloadQueueSuspended(_ isSuspended: Bool, backupPlan: BackupPlan) { print("Download queue suspended: \(isSuspended) \(backupPlan)") }
            func setShouldAllowBackupDownloadsOnCellular() { print("Downloads on cellular: true") }

            func showViewRecoveryKey() { print("Showing View Recovery Key!") }

            func showBackupSubscriptionAlreadyRedeemedSheet() { print("Showing Backup subscription already redeemed sheet!") }
            func showBackupIAPNotFoundLocallySheet() { print("Showing Backup IAP not found locally sheet!") }
            func showBackgroundAppRefreshDisabledWarningSheet() { print("Showing Background App Refresh warning sheet!") }
        }

        let viewModel = BackupSettingsViewModel(
            backupSubscriptionConfiguration: BackupSubscriptionConfiguration(
                storageAllowanceBytes: 100_000_000_000,
                freeTierMediaDays: 45,
            ),
            backupSubscriptionLoadingState: backupSubscriptionLoadingState,
            backupSubscriptionAlreadyRedeemed: backupSubscriptionAlreadyRedeemed,
            backupPlan: backupPlan,
            failedToDisableBackupsRemotely: failedToDisableBackupsRemotely,
            latestBackupExportProgressUpdate: latestBackupExportProgressUpdate,
            latestBackupAttachmentDownloadUpdate: latestBackupAttachmentDownloadUpdateState.map {
                BackupSettingsAttachmentDownloadTracker.DownloadUpdate(
                    state: $0,
                    bytesDownloaded: 1_400_000_000,
                    totalBytesToDownload: 1_600_000_000,
                )
            },
            latestBackupAttachmentUploadUpdate: latestBackupAttachmentUploadUpdateState.map {
                BackupSettingsAttachmentUploadTracker.UploadUpdate(
                    state: $0,
                    bytesUploaded: 400_000_000,
                    totalBytesToUpload: 1_600_000_000,
                )
            },
            lastBackupDetails: BackupSettingsStore.LastBackupDetails(
                date: Date().addingTimeInterval(-1 * .day),
                backupFileSizeBytes: 40_000_000,
                backupTotalSizeBytes: 2_400_000_000,
            ),
            shouldAllowBackupUploadsOnCellular: false,
            mediaTierCapacityOverflow: mediaTierCapacityOverflow,
            hasBackupFailed: hasBackupFailed,
            isBackgroundAppRefreshDisabled: isBackgroundAppRefreshDisabled,
        )
        let actionsDelegate = PreviewActionsDelegate()
        viewModel.actionsDelegate = actionsDelegate
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)

        return viewModel
    }
}

#Preview("Plan: Free") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
    ))
}

#Preview("Plan: Free For Testers") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
    ))
}

#Preview("Plan: Paid") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paid(
            price: FiatMoney(currencyCode: "USD", value: 1.99),
            renewalDate: Date().addingTimeInterval(.week),
        )),
        backupPlan: .paid(optimizeLocalStorage: false),
    ))
}

#Preview("Plan: Expiring") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButExpiring(
            expirationDate: Date().addingTimeInterval(.week),
        )),
        backupPlan: .paidExpiringSoon(optimizeLocalStorage: false),
    ))
}

#Preview("Plan: Expired") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButExpired(
            expirationDate: Date().addingTimeInterval(-1 * .week),
        )),
        backupPlan: .paidExpiringSoon(optimizeLocalStorage: false),
    ))
}

#Preview("Plan: Failed to Renew") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFailedToRenew),
        backupPlan: .paidExpiringSoon(optimizeLocalStorage: false),
    ))
}

#Preview("Plan: Already Redeemed") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paid(
            price: FiatMoney(currencyCode: "USD", value: 1.99),
            renewalDate: Date().addingTimeInterval(.week),
        )),
        backupPlan: .paidExpiringSoon(optimizeLocalStorage: false),
        backupSubscriptionAlreadyRedeemed: true,
    ))
}

#Preview("Plan: Paid but No IAP") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButIAPNotFoundLocally),
        backupPlan: .paid(optimizeLocalStorage: false),
    ))
}

#Preview("Plan: Network Error") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .networkError,
        backupPlan: .paid(optimizeLocalStorage: false),
    ))
}

#Preview("Plan: Generic Error") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .genericError,
        backupPlan: .paid(optimizeLocalStorage: false),
    ))
}

#Preview("Failed Backup") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        hasBackupFailed: true,
    ))
}

#Preview("Out of Quota") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        mediaTierCapacityOverflow: 1_000_000_000,
    ))
}

#Preview("Background App Refresh Disabled") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        isBackgroundAppRefreshDisabled: true,
    ))
}

#Preview("Manual Backup: Backup Export") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupExportProgressUpdate: .forPreview(.backupExport, 0.33),
    ))
}

#Preview("Manual Backup: Listing Media") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupExportProgressUpdate: .forPreview(.listMedia, 0.50),
    ))
}

#Preview("Manual Backup: Media Upload") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        latestBackupExportProgressUpdate: .forPreview(.attachmentUpload, 0.80),
        latestBackupAttachmentUploadUpdateState: .running,
    ))
}

#Preview("Manual Backup: Media Upload Paused (Low Battery)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        latestBackupExportProgressUpdate: .forPreview(.attachmentUpload, 0.80),
        latestBackupAttachmentUploadUpdateState: .pausedLowBattery,
    ))
}

#Preview("Manual Backup: Media Upload Paused (Low Power Mode)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        latestBackupExportProgressUpdate: .forPreview(.attachmentUpload, 0.80),
        latestBackupAttachmentUploadUpdateState: .pausedLowPowerMode,
    ))
}

#Preview("Manual Backup: Media Upload Paused (WiFi)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        latestBackupExportProgressUpdate: .forPreview(.attachmentUpload, 0.80),
        latestBackupAttachmentUploadUpdateState: .pausedNeedsWifi,
    ))
}

#Preview("Manual Backup: Media Upload Paused (Internet)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        latestBackupExportProgressUpdate: .forPreview(.attachmentUpload, 0.80),
        latestBackupAttachmentUploadUpdateState: .pausedNeedsInternet,
    ))
}

#Preview("Manual Backup: Offloading") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paidButFreeForTesters),
        backupPlan: .paidAsTester(optimizeLocalStorage: false),
        latestBackupExportProgressUpdate: .forPreview(.offloading, 0.90),
    ))
}

#Preview("Downloads: Suspended") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.paid(
            price: FiatMoney(currencyCode: "USD", value: 1.99),
            renewalDate: Date().addingTimeInterval(.week),
        )),
        backupPlan: .paid(optimizeLocalStorage: false),
        latestBackupAttachmentDownloadUpdateState: .suspended,
    ))
}

#Preview("Downloads: Suspended w/o Paid Plan") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentDownloadUpdateState: .suspended,
    ))
}

#Preview("Downloads: Running") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentDownloadUpdateState: .running,
    ))
}

#Preview("Downloads: Paused (Low Battery)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentDownloadUpdateState: .pausedLowBattery,
    ))
}

#Preview("Downloads: Paused (Low Power Mode)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentDownloadUpdateState: .pausedLowPowerMode,
    ))
}

#Preview("Downloads: Paused (WiFi)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentDownloadUpdateState: .pausedNeedsWifi,
    ))
}

#Preview("Downloads: Paused (Internet)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentDownloadUpdateState: .pausedNeedsInternet,
    ))
}

#Preview("Downloads: Disk Space Error") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentDownloadUpdateState: .outOfDiskSpace(bytesRequired: 200_000_000),
    ))
}

#Preview("Uploads: Running") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentUploadUpdateState: .running,
    ))
}

#Preview("Uploads: Paused (WiFi)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentUploadUpdateState: .pausedNeedsWifi,
    ))
}

#Preview("Uploads: Paused (Battery)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndEnabled),
        backupPlan: .free,
        latestBackupAttachmentUploadUpdateState: .pausedLowBattery,
    ))
}

#Preview("Disabling: Success") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndDisabled),
        backupPlan: .disabled,
    ))
}

#Preview("Disabling: Remotely") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndDisabled),
        backupPlan: .disabling,
    ))
}

#Preview("Disabling: Remotely (w/ Downloads)") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndDisabled),
        backupPlan: .disabling,
        latestBackupAttachmentDownloadUpdateState: .pausedNeedsInternet,
    ))
}

#Preview("Disabling: Remotely Failed") {
    BackupSettingsView(viewModel: .forPreview(
        backupSubscriptionLoadingState: .loaded(.freeAndDisabled),
        backupPlan: .disabled,
        failedToDisableBackupsRemotely: true,
    ))
}

#endif
