//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI
import StoreKit
import SwiftUI

class BackupSettingsViewController: HostingController<BackupSettingsView> {
    enum OnLoadAction {
        case none
        case presentWelcomeToBackupsSheet
    }

    private let accountKeyStore: AccountKeyStore
    private let backupAttachmentUploadTracker: BackupSettingsAttachmentUploadTracker
    private let backupDisablingManager: BackupDisablingManager
    private let backupEnablingManager: BackupEnablingManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let db: DB

    private var eventObservationTasks: [Task<Void, Never>]
    private let onLoadAction: OnLoadAction
    private let viewModel: BackupSettingsViewModel

    convenience init(
        onLoadAction: OnLoadAction,
    ) {
        self.init(
            onLoadAction: onLoadAction,
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupAttachmentUploadProgress: DependenciesBridge.shared.backupAttachmentUploadProgress,
            backupAttachmentUploadQueueStatusReporter: DependenciesBridge.shared.backupAttachmentUploadQueueStatusReporter,
            backupDisablingManager: AppEnvironment.shared.backupDisablingManager,
            backupEnablingManager: AppEnvironment.shared.backupEnablingManager,
            backupSettingsStore: BackupSettingsStore(),
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            db: DependenciesBridge.shared.db,
        )
    }

    init(
        onLoadAction: OnLoadAction,
        accountKeyStore: AccountKeyStore,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter,
        backupDisablingManager: BackupDisablingManager,
        backupEnablingManager: BackupEnablingManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        db: DB,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupAttachmentUploadTracker = BackupSettingsAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusReporter: backupAttachmentUploadQueueStatusReporter,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress
        )
        self.backupDisablingManager = backupDisablingManager
        self.backupEnablingManager = backupEnablingManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.db = db

        self.eventObservationTasks = []
        self.onLoadAction = onLoadAction
        self.viewModel = db.read { tx in
            let viewModel = BackupSettingsViewModel(
                backupEnabledState: .disabled, // Default, set below
                backupPlanLoadingState: .loading, // Default, loaded after init
                latestBackupAttachmentUploadUpdate: nil, // Default, loaded after init
                lastBackupDate: backupSettingsStore.lastBackupDate(tx: tx),
                lastBackupSizeBytes: backupSettingsStore.lastBackupSizeBytes(tx: tx),
                backupFrequency: backupSettingsStore.backupFrequency(tx: tx),
                shouldBackUpOnCellular: backupSettingsStore.shouldBackUpOnCellular(tx: tx)
            )

            if let disableBackupsRemotelyState = backupDisablingManager.currentDisableRemotelyState(tx: tx) {
                viewModel.handleDisableBackupsRemoteState(disableBackupsRemotelyState)
            } else {
                switch backupSettingsStore.backupPlan(tx: tx) {
                case .disabled:
                    viewModel.backupEnabledState = .disabled
                case .free, .paid, .paidExpiringSoon:
                    viewModel.backupEnabledState = .enabled
                }
            }

            return viewModel
        }

        super.init(wrappedView: BackupSettingsView(viewModel: viewModel))

        title = OWSLocalizedString(
            "BACKUPS_SETTINGS_TITLE",
            comment: "Title for the 'Backup' settings menu."
        )
        OWSTableViewController2.removeBackButtonText(viewController: self)

        viewModel.actionsDelegate = self
        // Run as soon as we've set the actionDelegate.
        viewModel.loadBackupPlan()

        eventObservationTasks = [
            Task { [weak self, backupAttachmentUploadTracker] in
                for await uploadUpdate in await backupAttachmentUploadTracker.start() {
                    guard let self else { return }
                    viewModel.latestBackupAttachmentUploadUpdate = uploadUpdate
                }
            },
            Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: BackupSettingsStore.Notifications.backupPlanChanged
                ) {
                    guard let self else { return }
                    await viewModel.loadBackupPlan()
                }
            },
        ]
    }

    deinit {
        eventObservationTasks.forEach { $0.cancel() }
    }

    override func viewDidLoad() {
        switch onLoadAction {
        case .none:
            break
        case .presentWelcomeToBackupsSheet:
            presentWelcomeToBackupsSheet()
        }
    }
}

// MARK: - BackupSettingsViewModel.ActionsDelegate

extension BackupSettingsViewController: BackupSettingsViewModel.ActionsDelegate {
    fileprivate func enableBackups(
        implicitPlanSelection: ChooseBackupPlanViewController.PlanSelection?
    ) {
        // TODO: [Backups] Show the rest of the onboarding flow.

        Task {
            if let planSelection = implicitPlanSelection {
                await _enableBackups(
                    fromViewController: self,
                    planSelection: planSelection
                )
            } else {
                await showChooseBackupPlan(initialPlanSelection: nil)
            }
        }
    }

    @MainActor
    private func showChooseBackupPlan(
        initialPlanSelection: ChooseBackupPlanViewController.PlanSelection?
    ) async {
        let chooseBackupPlanViewController: ChooseBackupPlanViewController
        do throws(OWSAssertionError) {
            chooseBackupPlanViewController = try await .load(
                fromViewController: self,
                initialPlanSelection: initialPlanSelection,
                onConfirmPlanSelectionBlock: { [weak self] chooseBackupPlanViewController, planSelection in
                    Task { [weak self] in
                        guard let self else { return }

                        await _enableBackups(
                            fromViewController: chooseBackupPlanViewController,
                            planSelection: planSelection
                        )
                    }
                }
            )
        } catch {
            return
        }

        navigationController?.pushViewController(
            chooseBackupPlanViewController,
            animated: true
        )
    }

    @MainActor
    private func _enableBackups(
        fromViewController: UIViewController,
        planSelection: ChooseBackupPlanViewController.PlanSelection
    ) async {
        do throws(BackupEnablingManager.DisplayableError) {
            try await backupEnablingManager.enableBackups(
                fromViewController: fromViewController,
                planSelection: planSelection
            )
        } catch {
            OWSActionSheets.showActionSheet(
                message: error.localizedActionSheetMessage,
                fromViewController: fromViewController,
            )
            return
        }

        // We know we're enabled now! Set state before popping so correct UI is shown.
        viewModel.backupEnabledState = .enabled
        navigationController?.popToViewController(self, animated: true) { [self] in
            presentWelcomeToBackupsSheet()
        }
    }

    private func presentWelcomeToBackupsSheet() {
        let welcomeToBackupsSheet = HeroSheetViewController(
            hero: .image(.backupsSubscribed),
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_WELCOME_TO_BACKUPS_SHEET_TITLE",
                comment: "Title for a sheet shown after the user enables backups."
            ),
            body: OWSLocalizedString(
                "BACKUP_SETTINGS_WELCOME_TO_BACKUPS_SHEET_MESSAGE",
                comment: "Message for a sheet shown after the user enables backups."
            ),
            primary: .button(HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_WELCOME_TO_BACKUPS_SHEET_PRIMARY_BUTTON",
                    comment: "Title for the primary button for a sheet shown after the user enables backups."
                ),
                action: { _ in
                    self.viewModel.performManualBackup()
                }
            )),
            secondary: .button(.dismissing(
                title: OWSLocalizedString(
                    "BACKUP_SETTINGS_WELCOME_TO_BACKUPS_SHEET_SECONDARY_BUTTON",
                    comment: "Title for the secondary button for a sheet shown after the user enables backups."
                ),
                style: .secondary
            ))
        )

        present(welcomeToBackupsSheet, animated: true)
    }

    // MARK: -

    fileprivate func disableBackups() {
        AssertIsOnMainThread()

        func errorActionSheet(_ message: String) {
            OWSActionSheets.showActionSheet(
                message: message,
                fromViewController: self
            )
        }

        do throws(BackupDisablingManager.NotRegisteredError) {
            try db.write { tx throws(BackupDisablingManager.NotRegisteredError) in
                return try backupDisablingManager.disableBackups(tx: tx)
            }

            if let disableRemotelyState = db.read(block: { backupDisablingManager.currentDisableRemotelyState(tx: $0) }) {
                viewModel.handleDisableBackupsRemoteState(disableRemotelyState)
            }
        } catch {
            errorActionSheet(OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_ERROR_NOT_REGISTERED",
                comment: "Message shown in an action sheet when the user tries to disable Backups, but is not registered."
            ))
        }
    }

    func showDisablingBackupsFailedSheet() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_ERROR_GENERIC_ERROR_ACTION_SHEET_TITLE",
                comment: "Title shown in an action sheet indicating we failed to delete the user's Backup due to an unexpected error."
            ),
            message: OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLING_ERROR_GENERIC_ERROR_ACTION_SHEET_MESSAGE",
                comment: "Message shown in an action sheet indicating we failed to delete the user's Backup due to an unexpected error."
            ),
        )
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.contactSupport) { _ in
            ContactSupportActionSheet.present(
                emailFilter: .custom("iOS Disable Backups Failed"),
                logDumper: .fromGlobals(),
                fromViewController: self
            )
        })
        actionSheet.addAction(.okay)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    // MARK: -

    fileprivate func loadBackupPlan() async throws -> BackupSettingsViewModel.BackupPlanLoadingState.LoadedBackupPlan {
        switch db.read(block: { backupSettingsStore.backupPlan(tx: $0) }) {
        case .free:
            return .free
        case .disabled, .paid, .paidExpiringSoon:
            break
        }

        guard
            let backupSubscription = try await backupSubscriptionManager
                .fetchAndMaybeDowngradeSubscription()
        else {
            return .free
        }

        let endOfCurrentPeriod = Date(timeIntervalSince1970: backupSubscription.endOfCurrentPeriod)

        switch backupSubscription.status {
        case .active, .pastDue:
            // `.pastDue` means that a renewal failed, but the payment
            // processor is automatically retrying. For now, assume it
            // may recover, and show it as paid. If it fails, it'll
            // become `.canceled` instead.
            if backupSubscription.cancelAtEndOfPeriod {
                return .paidExpiringSoon(expirationDate: endOfCurrentPeriod)
            }

            return .paid(
                price: backupSubscription.amount,
                renewalDate: endOfCurrentPeriod
            )
        case .canceled:
            // TODO: [Backups] Downgrade local state to the free plan, if necessary.
            // This might be the first place we learn, locally, that our
            // subscription has expired and we've been implicitly downgraded to
            // the free plan. Correspondingly, we should use this as a change to
            // set local state, if necessary. Make sure to log that state change
            // loudly!
            return .free
        case .incomplete, .unpaid, .unknown:
            // These are unexpected statuses, so we know that something
            // is wrong with the subscription. Consequently, we can show
            // it as free.
            owsFailDebug("Unexpected backup subscription status! \(backupSubscription.status)")
            return .free
        }
    }

    // MARK: -

    fileprivate func upgradeFromFreeToPaidPlan() {
        Task {
            await showChooseBackupPlan(initialPlanSelection: .free)
        }
    }

    fileprivate func manageOrCancelPaidPlan() {
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
            viewModel.loadBackupPlan()
        }
    }

    fileprivate func resubscribeToPaidPlan() {
        Task {
            await showChooseBackupPlan(initialPlanSelection: .free)
        }
    }

    // MARK: -

    fileprivate func performManualBackup() {
        // TODO: [Backups] Implement
    }

    fileprivate func setBackupFrequency(_ newBackupFrequency: BackupFrequency) {
        db.write { tx in
            backupSettingsStore.setBackupFrequency(newBackupFrequency, tx: tx)
        }
    }

    fileprivate func setShouldBackUpOnCellular(_ newShouldBackUpOnCellular: Bool) {
        db.write { tx in
            backupSettingsStore.setShouldBackUpOnCellular(newShouldBackUpOnCellular, tx: tx)
        }
    }

    // MARK: -

    fileprivate func showViewBackupKey() {
        Task { await _showViewBackupKey() }
    }

    @MainActor
    private func _showViewBackupKey() async {
        guard let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) }) else {
            return
        }

        guard await LocalDeviceAuthentication().performBiometricAuth() else {
            return
        }

        navigationController?.pushViewController(
            BackupRecordKeyViewController(
                aep: aep,
                isOnboardingFlow: false,
                onCompletion: { [weak self] recordKeyViewController in
                    self?.showKeyRecordedConfirmationSheet(
                        fromViewController: recordKeyViewController
                    )
                }
            ),
            animated: true
        )
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    private func showKeyRecordedConfirmationSheet(fromViewController: BackupRecordKeyViewController) {
        let sheet = HeroSheetViewController(
            hero: .image(.backupsKey),
            title: OWSLocalizedString(
                "BACKUP_ONBOARDING_CONFIRM_KEY_KEEP_KEY_SAFE_SHEET_TITLE",
                comment: "Title for a sheet warning users to their 'Backup Key' safe."
            ),
            body: OWSLocalizedString(
                "BACKUP_ONBOARDING_CONFIRM_KEY_KEEP_KEY_SAFE_SHEET_BODY",
                comment: "Body for a sheet warning users to their 'Backup Key' safe."
            ),
            primary: .button(HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BUTTON_CONTINUE",
                    comment: "Label for 'continue' button."
                ),
                action: { [weak self] _ in
                    self?.dismiss(animated: true)
                    self?.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
                    self?.navigationController?.popViewController(animated: true)
                }
            )),
            secondary: .button(HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_ONBOARDING_CONFIRM_KEY_SEE_KEY_AGAIN_BUTTON_TITLE",
                    comment: "Title for a button offering to let users see their 'Backup Key'."
                ),
                style: .secondary,
                action: .custom({ [weak self] _ in
                    self?.dismiss(animated: true)
                    self?.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
                })
            ))
        )
        fromViewController.present(sheet, animated: true)
    }}

// MARK: -

private class BackupSettingsViewModel: ObservableObject {
    protocol ActionsDelegate: AnyObject {
        func enableBackups(implicitPlanSelection: ChooseBackupPlanViewController.PlanSelection?)

        func disableBackups()
        func showDisablingBackupsFailedSheet()

        func loadBackupPlan() async throws -> BackupPlanLoadingState.LoadedBackupPlan
        func upgradeFromFreeToPaidPlan()
        func manageOrCancelPaidPlan()
        func resubscribeToPaidPlan()

        func performManualBackup()
        func setBackupFrequency(_ newBackupFrequency: BackupFrequency)
        func setShouldBackUpOnCellular(_ newShouldBackUpOnCellular: Bool)

        func showViewBackupKey()
    }

    enum BackupPlanLoadingState {
        enum LoadedBackupPlan {
            case free
            case paid(price: FiatMoney, renewalDate: Date)
            case paidExpiringSoon(expirationDate: Date)
        }

        case loading
        case loaded(LoadedBackupPlan)
        case networkError
        case genericError
    }

    enum BackupEnabledState {
        case enabled
        case disabled
        case disabledLocallyStillDisablingRemotely
        case disabledLocallyButDisableRemotelyFailed
    }

    @Published var backupPlanLoadingState: BackupPlanLoadingState
    @Published var backupEnabledState: BackupEnabledState
    @Published var latestBackupAttachmentUploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate?

    @Published var lastBackupDate: Date?
    @Published var lastBackupSizeBytes: UInt64?
    @Published var backupFrequency: BackupFrequency
    @Published var shouldBackUpOnCellular: Bool

    weak var actionsDelegate: ActionsDelegate?

    private let loadBackupPlanQueue: SerialTaskQueue

    init(
        backupEnabledState: BackupEnabledState,
        backupPlanLoadingState: BackupPlanLoadingState,
        latestBackupAttachmentUploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate?,
        lastBackupDate: Date?,
        lastBackupSizeBytes: UInt64?,
        backupFrequency: BackupFrequency,
        shouldBackUpOnCellular: Bool,
    ) {
        self.backupEnabledState = backupEnabledState
        self.backupPlanLoadingState = backupPlanLoadingState
        self.latestBackupAttachmentUploadUpdate = latestBackupAttachmentUploadUpdate
        self.lastBackupDate = lastBackupDate
        self.lastBackupSizeBytes = lastBackupSizeBytes
        self.backupFrequency = backupFrequency
        self.shouldBackUpOnCellular = shouldBackUpOnCellular

        self.loadBackupPlanQueue = SerialTaskQueue()
    }

    // MARK: -

    func enableBackups(implicitPlanSelection: ChooseBackupPlanViewController.PlanSelection?) {
        actionsDelegate?.enableBackups(implicitPlanSelection: implicitPlanSelection)
    }

    func disableBackups() {
        actionsDelegate?.disableBackups()
    }

    func handleDisableBackupsRemoteState(
        _ disablingRemotelyState: BackupDisablingManager.DisableRemotelyState
    ) {
        let disableRemotelyTask: Task<Void, Error>
        switch disablingRemotelyState {
        case .inProgress(let task):
            withAnimation {
                backupEnabledState = .disabledLocallyStillDisablingRemotely
            }

            disableRemotelyTask = task
        case .previouslyFailed:
            withAnimation {
                backupEnabledState = .disabledLocallyButDisableRemotelyFailed
            }

            return
        }

        Task { @MainActor in
            let newBackupEnabledState: BackupEnabledState
            do {
                try await disableRemotelyTask.value
                newBackupEnabledState = .disabled
            } catch {
                newBackupEnabledState = .disabledLocallyButDisableRemotelyFailed
                actionsDelegate?.showDisablingBackupsFailedSheet()
            }

            withAnimation {
                backupEnabledState = newBackupEnabledState
            }
        }
    }

    // MARK: -

    func loadBackupPlan() {
        guard let actionsDelegate else { return }

        loadBackupPlanQueue.enqueue { @MainActor [self, actionsDelegate] in
            withAnimation {
                backupPlanLoadingState = .loading
            }

            let newLoadingState: BackupPlanLoadingState
            do {
                let backupPlan = try await actionsDelegate.loadBackupPlan()
                newLoadingState = .loaded(backupPlan)
            } catch let error where error.isNetworkFailureOrTimeout {
                newLoadingState = .networkError
            } catch {
                newLoadingState = .genericError
            }

            withAnimation {
                backupPlanLoadingState = newLoadingState
            }
        }
    }

    func upgradeFromFreeToPaidPlan() {
        actionsDelegate?.upgradeFromFreeToPaidPlan()
    }

    func manageOrCancelPaidPlan() {
        actionsDelegate?.manageOrCancelPaidPlan()
    }

    func resubscribeToPaidPlan() {
        actionsDelegate?.resubscribeToPaidPlan()
    }

    // MARK: -

    func performManualBackup() {
        actionsDelegate?.performManualBackup()
    }

    func setBackupFrequency(_ newBackupFrequency: BackupFrequency) {
        backupFrequency = newBackupFrequency
        actionsDelegate?.setBackupFrequency(newBackupFrequency)
    }

    func setShouldBackUpOnCellular(_ newShouldBackUpOnCellular: Bool) {
        shouldBackUpOnCellular = newShouldBackUpOnCellular
        actionsDelegate?.setShouldBackUpOnCellular(newShouldBackUpOnCellular)
    }

    // MARK: -

    func showViewBackupKey() {
        actionsDelegate?.showViewBackupKey()
    }
}

// MARK: -

struct BackupSettingsView: View {
    @ObservedObject private var viewModel: BackupSettingsViewModel

    fileprivate init(viewModel: BackupSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SignalList {
            SignalSection {
                BackupPlanView(
                    loadingState: viewModel.backupPlanLoadingState,
                    viewModel: viewModel
                )
            }

            if let latestBackupAttachmentUploadUpdate = viewModel.latestBackupAttachmentUploadUpdate {
                SignalSection {
                    BackupAttachmentUploadProgressView(
                        latestUploadUpdate: latestBackupAttachmentUploadUpdate
                    )
                }
            }

            switch viewModel.backupEnabledState {
            case .enabled:
                SignalSection {
                    Button {
                        viewModel.performManualBackup()
                    } label: {
                        Label {
                            Text(OWSLocalizedString(
                                "BACKUP_SETTINGS_MANUAL_BACKUP_BUTTON_TITLE",
                                comment: "Title for a button allowing users to trigger a manual backup."
                            ))
                        } icon: {
                            Image(uiImage: Theme.iconImage(.backup))
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                    }
                    .foregroundStyle(Color.Signal.label)
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_ENABLED_SECTION_HEADER",
                        comment: "Header for a menu section related to settings for when Backups are enabled."
                    ))
                }

                SignalSection {
                    BackupDetailsView(viewModel: viewModel)
                }

                SignalSection {
                    Button {
                        viewModel.disableBackups()
                    } label: {
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_DISABLE_BACKUPS_BUTTON_TITLE",
                            comment: "Title for a button allowing users to turn off Backups."
                        ))
                        .foregroundStyle(Color.Signal.red)
                    }
                } footer: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_DISABLE_BACKUPS_BUTTON_FOOTER",
                        comment: "Footer for a menu section allowing users to turn off Backups."
                    ))
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }
            case .disabled:
                SignalSection {
                    reenableBackupsButton
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_DISABLED_SECTION_FOOTER",
                        comment: "Footer for a menu section related to settings for when Backups are disabled."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }
            case .disabledLocallyStillDisablingRemotely:
                SignalSection {
                    VStack(alignment: .leading) {
                        LottieView(animation: .named("linear_indeterminate"))
                            .playing(loopMode: .loop)
                            .background {
                                Capsule().fill(Color.Signal.secondaryFill)
                            }

                        Spacer().frame(height: 16)

                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUPS_DISABLING_PROGRESS_VIEW_DESCRIPTION",
                            comment: "Description for a progress view tracking Backups being disabled."
                        ))
                        .foregroundStyle(Color.Signal.secondaryLabel)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_DISABLING_SECTION_HEADER",
                        comment: "Header for a menu section related to disabling Backups."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }
            case .disabledLocallyButDisableRemotelyFailed:
                SignalSection {
                    VStack(alignment: .center) {
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUPS_DISABLING_GENERIC_ERROR_TITLE",
                            comment: "Title for a view indicating we failed to delete the user's Backup due to an unexpected error."
                        ))
                        .bold()
                        .foregroundStyle(Color.Signal.secondaryLabel)

                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUPS_DISABLING_GENERIC_ERROR_MESSAGE",
                            comment: "Message for a view indicating we failed to delete the user's Backup due to an unexpected error."
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
                        comment: "Header for a menu section related to settings for when disabling Backups encountered an unexpected error."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }

                SignalSection {
                    reenableBackupsButton
                }
            }
        }
    }

    /// A button to enable Backups if it was previously disabled, if we can let
    /// the user reenable.
    private var reenableBackupsButton: AnyView {
        let implicitPlanSelection: ChooseBackupPlanViewController.PlanSelection?
        switch viewModel.backupPlanLoadingState {
        case .loading, .networkError:
            // Don't let them reenable until we know if they're already paying
            // or not.
            return AnyView(EmptyView())
        case .loaded(.free), .genericError:
            // Let the reenable with anything.
            implicitPlanSelection = nil
        case .loaded(.paid), .loaded(.paidExpiringSoon):
            // Only let the user reenable with .paid, because they're already
            // paying.
            implicitPlanSelection = .paid
        }

        return AnyView(
            Button {
                viewModel.enableBackups(implicitPlanSelection: implicitPlanSelection)
            } label: {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_REENABLE_BACKUPS_BUTTON_TITLE",
                    comment: "Title for a button allowing users to re-enable Backups, after it had been previously disabled."
                ))
            }
                .buttonStyle(.plain)
        )
    }
}

// MARK: -

private struct BackupAttachmentUploadProgressView: View {
    let latestUploadUpdate: BackupSettingsAttachmentUploadTracker.UploadUpdate

    var body: some View {
        VStack(alignment: .leading) {
            ProgressView(value: latestUploadUpdate.percentageUploaded)
                .progressViewStyle(.linear)
                .tint(Color.Signal.accent)
                .scaleEffect(x: 1, y: 1.5)
                .padding(.vertical, 12)

            let subtitleText: String = switch latestUploadUpdate.state {
            case .running:
                String(
                    format: OWSLocalizedString(
                        "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_RUNNING",
                        comment: "Subtitle for a progress bar tracking active uploading. Embeds 1:{{ the amount uploaded as a file size, e.g. 100 MB }}; 2:{{ the total amount to upload as a file size, e.g. 1 GB }}; 3:{{ the amount uploaded as a percentage, e.g. 10% }}."
                    ),
                    latestUploadUpdate.bytesUploaded.formatted(.byteCount(style: .decimal)),
                    latestUploadUpdate.totalBytesToUpload.formatted(.byteCount(style: .decimal)),
                    latestUploadUpdate.percentageUploaded.formatted(.percent.precision(.fractionLength(0))),
                )
            case .pausedLowBattery:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_PAUSED_LOW_BATTERY",
                    comment: "Subtitle for a progress bar tracking uploads that are paused because of low battery."
                )
            case .pausedNeedsWifi:
                OWSLocalizedString(
                    "BACKUP_SETTINGS_UPLOAD_PROGRESS_SUBTITLE_PAUSED_NEEDS_WIFI",
                    comment: "Subtitle for a progress bar tracking uploads that are paused because they need WiFi."
                )
            }

            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)
        }
    }
}

// MARK: -

private struct BackupPlanView: View {
    let loadingState: BackupSettingsViewModel.BackupPlanLoadingState
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
        case .loaded(let loadedBackupPlan):
            loadedView(
                loadedBackupPlan: loadedBackupPlan,
                viewModel: viewModel
            )
        case .networkError:
            VStack(alignment: .center) {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_NETWORK_ERROR_TITLE",
                    comment: "Title for a view indicating we failed to fetch someone's Backup plan due to a network error."
                ))
                .font(.subheadline)
                .bold()
                .foregroundStyle(Color.Signal.secondaryLabel)

                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_NETWORK_ERROR_MESSAGE",
                    comment: "Message for a view indicating we failed to fetch someone's Backup plan due to a network error."
                ))
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer().frame(height: 16)

                Button {
                    viewModel.loadBackupPlan()
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
                    comment: "Title for a view indicating we failed to fetch someone's Backup plan due to an unexpected error."
                ))
                .font(.subheadline)
                .bold()
                .foregroundStyle(Color.Signal.secondaryLabel)

                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_PLAN_GENERIC_ERROR_MESSAGE",
                    comment: "Message for a view indicating we failed to fetch someone's Backup plan due to an unexpected error."
                ))
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 140)
        }
    }

    private func loadedView(
        loadedBackupPlan: BackupSettingsViewModel.BackupPlanLoadingState.LoadedBackupPlan,
        viewModel: BackupSettingsViewModel
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Group {
                    switch loadedBackupPlan {
                    case .free:
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUP_PLAN_FREE_HEADER",
                            comment: "Header describing what the free backup plan includes."
                        ))
                    case .paid, .paidExpiringSoon:
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUP_PLAN_PAID_HEADER",
                            comment: "Header describing what the paid backup plan includes."
                        ))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer().frame(height: 8)

                switch loadedBackupPlan {
                case .free:
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_PLAN_FREE_DESCRIPTION",
                        comment: "Text describing the user's free backup plan."
                    ))
                case .paid(let price, let renewalDate):
                    let renewalStringFormat = OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_PLAN_PAID_RENEWAL_FORMAT",
                        comment: "Text explaining when the user's paid backup plan renews. Embeds {{ the formatted renewal date }}."
                    )
                    let priceStringFormat = OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_PLAN_PAID_PRICE_FORMAT",
                        comment: "Text explaining the price of the user's paid backup plan. Embeds {{ the formatted price }}."
                    )

                    Text(String(
                        format: priceStringFormat,
                        CurrencyFormatter.format(money: price)
                    ))
                    Text(String(
                        format: renewalStringFormat,
                        DateFormatter.localizedString(from: renewalDate, dateStyle: .medium, timeStyle: .none)
                    ))
                case .paidExpiringSoon(let expirationDate):
                    let expirationDateFutureString = OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_CANCELED_FUTURE_EXPIRATION_FORMAT",
                        comment: "Text explaining that a user's paid plan, which has been canceled, will expire on a future date. Embeds {{ the formatted expiration date }}."
                    )

                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_CANCELED_DESCRIPTION",
                        comment: "Text describing that the user's paid backup plan has been canceled."
                    ))
                    .foregroundStyle(Color.Signal.red)
                    Text(String(
                        format: expirationDateFutureString,
                        DateFormatter.localizedString(from: expirationDate, dateStyle: .medium, timeStyle: .none)
                    ))
                }

                Spacer().frame(height: 16)

                Button {
                    switch loadedBackupPlan {
                    case .free:
                        viewModel.upgradeFromFreeToPaidPlan()
                    case .paid:
                        viewModel.manageOrCancelPaidPlan()
                    case .paidExpiringSoon:
                        viewModel.resubscribeToPaidPlan()
                    }
                } label: {
                    switch loadedBackupPlan {
                    case .free:
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUP_PLAN_FREE_ACTION_BUTTON_TITLE",
                            comment: "Title for a button allowing users to upgrade from a free to paid backup plan."
                        ))
                    case .paid:
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUP_PLAN_PAID_ACTION_BUTTON_TITLE",
                            comment: "Title for a button allowing users to manage or cancel their paid backup plan."
                        ))
                    case .paidExpiringSoon:
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_BACKUP_PLAN_PAID_BUT_CANCELED_ACTION_BUTTON_TITLE",
                            comment: "Title for a button allowing users to reenable a paid backup plan that has been canceled."
                        ))
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .foregroundStyle(Color.Signal.label)
                .padding(.top, 8)
            }

            Spacer()

            Image("backups-subscribed")
                .frame(width: 56, height: 56)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

// MARK: -

private struct BackupDetailsView: View {
    let viewModel: BackupSettingsViewModel

    var body: some View {
        HStack {
            let lastBackupMessage: String? = {
                guard let lastBackupDate = viewModel.lastBackupDate else {
                    return nil
                }

                let lastBackupDateString = DateFormatter.localizedString(from: lastBackupDate, dateStyle: .medium, timeStyle: .none)
                let lastBackupTimeString = DateFormatter.localizedString(from: lastBackupDate, dateStyle: .none, timeStyle: .short)

                if Calendar.current.isDateInToday(lastBackupDate) {
                    let todayFormatString = OWSLocalizedString(
                        "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_TODAY_FORMAT",
                        comment: "Text explaining that the user's last backup was today. Embeds {{ the time of the backup }}."
                    )

                    return String(format: todayFormatString, lastBackupTimeString)
                } else if Calendar.current.isDateInYesterday(lastBackupDate) {
                    let yesterdayFormatString = OWSLocalizedString(
                        "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_YESTERDAY_FORMAT",
                        comment: "Text explaining that the user's last backup was yesterday. Embeds {{ the time of the backup }}."
                    )

                    return String(format: yesterdayFormatString, lastBackupTimeString)
                } else {
                    let pastFormatString = OWSLocalizedString(
                        "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_PAST_FORMAT",
                        comment: "Text explaining that the user's last backup was in the past. Embeds 1:{{ the date of the backup }} and 2:{{ the time of the backup }}."
                    )

                    return String(format: pastFormatString, lastBackupDateString, lastBackupTimeString)
                }
            }()

            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_ENABLED_LAST_BACKUP_LABEL",
                comment: "Label for a menu item explaining when the user's last backup occurred."
            ))
            Spacer()
            if let lastBackupMessage {
                Text(lastBackupMessage)
                    .foregroundStyle(Color.Signal.secondaryLabel)
            }
        }

        HStack {
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_ENABLED_BACKUP_SIZE_LABEL",
                comment: "Label for a menu item explaining the size of the user's backup."
            ))
            Spacer()
            if let lastBackupSizeBytes = viewModel.lastBackupSizeBytes {
                Text(lastBackupSizeBytes.formatted(.byteCount(style: .decimal)))
                    .foregroundStyle(Color.Signal.secondaryLabel)
            }
        }

        Picker(
            OWSLocalizedString(
                "BACKUP_SETTINGS_ENABLED_BACKUP_FREQUENCY_LABEL",
                comment: "Label for a menu item explaining the frequency of automatic backups."
            ),
            selection: Binding(
                get: { viewModel.backupFrequency },
                set: { viewModel.setBackupFrequency($0) }
            )
        ) {
            ForEach(BackupFrequency.allCases) { frequency in
                let localizedString: String = switch frequency {
                case .daily: OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_BACKUP_FREQUENCY_DAILY",
                    comment: "Text describing that a user's backup will be automatically performed daily."
                )
                case .weekly: OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_BACKUP_FREQUENCY_WEEKLY",
                    comment: "Text describing that a user's backup will be automatically performed weekly."
                )
                case .monthly: OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_BACKUP_FREQUENCY_MONTHLY",
                    comment: "Text describing that a user's backup will be automatically performed monthly."
                )
                case .manually: OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_BACKUP_FREQUENCY_MANUALLY",
                    comment: "Text describing that a user's backup will only be performed manually."
                )
                }

                Text(localizedString).tag(frequency)
            }
        }

        HStack {
            Toggle(
                OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_BACKUP_ON_CELLULAR_LABEL",
                    comment: "Label for a toggleable menu item describing whether to make backups on cellular data."
                ),
                isOn: Binding(
                    get: { viewModel.shouldBackUpOnCellular },
                    set: { viewModel.setShouldBackUpOnCellular($0) }
                )
            )
        }

        Button {
            viewModel.showViewBackupKey()
        } label: {
            HStack {
                Text(OWSLocalizedString(
                    "BACKUP_SETTINGS_ENABLED_VIEW_BACKUP_KEY_LABEL",
                    comment: "Label for a menu item offering to show the user their backup key."
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

private extension BackupSettingsViewModel {
    static func forPreview(
        backupEnabledState: BackupEnabledState,
        latestBackupAttachmentUploadUpdateState: BackupSettingsAttachmentUploadTracker.UploadUpdate.State?,
        backupPlanLoadResult: Result<BackupPlanLoadingState.LoadedBackupPlan, Error>,
    ) -> BackupSettingsViewModel {
        class PreviewActionsDelegate: ActionsDelegate {
            private let backupPlanLoadResult: Result<BackupPlanLoadingState.LoadedBackupPlan, Error>
            init(backupPlanLoadResult: Result<BackupPlanLoadingState.LoadedBackupPlan, Error>) {
                self.backupPlanLoadResult = backupPlanLoadResult
            }

            func enableBackups(implicitPlanSelection: ChooseBackupPlanViewController.PlanSelection?) { print("Enabling! implicitPlanSelection: \(implicitPlanSelection as Any)") }
            func disableBackups() { print("Disabling!") }
            func showDisablingBackupsFailedSheet() { print("Showing disabling-Backups-failed sheet!") }

            func loadBackupPlan() async throws -> BackupSettingsViewModel.BackupPlanLoadingState.LoadedBackupPlan {
                try! await Task.sleep(nanoseconds: 2.clampedNanoseconds)
                return try backupPlanLoadResult.get()
            }
            func upgradeFromFreeToPaidPlan() { print("Upgrading!") }
            func manageOrCancelPaidPlan() { print("Managing or canceling!") }
            func resubscribeToPaidPlan() { print("Resubscribing!") }

            func performManualBackup() { print("Manually backing up!") }
            func setBackupFrequency(_ newBackupFrequency: BackupFrequency) { print("Frequency: \(newBackupFrequency)") }
            func setShouldBackUpOnCellular(_ newShouldBackUpOnCellular: Bool) { print("Cellular: \(newShouldBackUpOnCellular)") }

            func showViewBackupKey() { print("Showing View Backup Key!") }
        }

        let viewModel = BackupSettingsViewModel(
            backupEnabledState: backupEnabledState,
            backupPlanLoadingState: .loading,
            latestBackupAttachmentUploadUpdate: latestBackupAttachmentUploadUpdateState.map {
                BackupSettingsAttachmentUploadTracker.UploadUpdate(
                    state: $0,
                    bytesUploaded: 400_000_000,
                    totalBytesToUpload: 1_600_000_000,
                )
            },
            lastBackupDate: Date().addingTimeInterval(-1 * .day),
            lastBackupSizeBytes: 2_400_000_000,
            backupFrequency: .daily,
            shouldBackUpOnCellular: false
        )
        let actionsDelegate = PreviewActionsDelegate(backupPlanLoadResult: backupPlanLoadResult)
        viewModel.actionsDelegate = actionsDelegate
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)

        viewModel.loadBackupPlan()
        return viewModel
    }
}

#Preview("Plan: Paid") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .success(.paid(
            price: FiatMoney(currencyCode: "USD", value: 2.99),
            renewalDate: Date().addingTimeInterval(.week)
        ))
    ))
}

#Preview("Plan: Free") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .success(.free)
    ))
}

#Preview("Plan: Expiring") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .success(.paidExpiringSoon(
            expirationDate: Date().addingTimeInterval(.week)
        ))
    ))
}

#Preview("Plan: Network Error") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .failure(OWSHTTPError.networkFailure(.genericTimeout))
    ))
}

#Preview("Plan: Generic Error") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .failure(OWSGenericError(""))
    ))
}

#Preview("Uploads: Running") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: .running,
        backupPlanLoadResult: .success(.free)
    ))
}

#Preview("Uploads: Paused (WiFi)") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: .pausedNeedsWifi,
        backupPlanLoadResult: .success(.free)
    ))
}

#Preview("Uploads: Paused (Battery)") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .enabled,
        latestBackupAttachmentUploadUpdateState: .pausedLowBattery,
        backupPlanLoadResult: .success(.free)
    ))
}

#Preview("Disabling: Success") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .disabled,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .success(.free),
    ))
}

#Preview("Disabling: Remotely") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .disabledLocallyStillDisablingRemotely,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .success(.free),
    ))
}

#Preview("Disabling: Remotely Failed") {
    BackupSettingsView(viewModel: .forPreview(
        backupEnabledState: .disabledLocallyButDisableRemotelyFailed,
        latestBackupAttachmentUploadUpdateState: nil,
        backupPlanLoadResult: .success(.free),
    ))
}

#endif
