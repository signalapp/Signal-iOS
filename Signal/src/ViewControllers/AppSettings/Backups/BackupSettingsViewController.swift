//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import StoreKit
import SwiftUI

class BackupSettingsViewController: HostingController<BackupSettingsView> {
    private let backupIdManager: BackupIdManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let db: DB
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    private let viewModel: BackupSettingsViewModel

    convenience init() {
        self.init(
            backupIdManager: DependenciesBridge.shared.backupIdManager,
            backupSettingsStore: BackupSettingsStore(),
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            db: DependenciesBridge.shared.db,
            networkManager: SSKEnvironment.shared.networkManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )
    }

    init(
        backupIdManager: BackupIdManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        db: DB,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager
    ) {
        self.backupIdManager = backupIdManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.db = db
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager

        self.viewModel = db.read { tx in
            BackupSettingsViewModel(
                areBackupsEnabled: backupSettingsStore.backupPlan(tx: tx) != nil,
                lastBackupDate: backupSettingsStore.lastBackupDate(tx: tx),
                lastBackupSizeBytes: backupSettingsStore.lastBackupSizeBytes(tx: tx),
                backupFrequency: backupSettingsStore.backupFrequency(tx: tx),
                shouldBackUpOnCellular: backupSettingsStore.shouldBackUpOnCellular(tx: tx)
            )
        }

        super.init(wrappedView: BackupSettingsView(viewModel: viewModel))

        title = OWSLocalizedString(
            "BACKUPS_SETTINGS_TITLE",
            comment: "Title for the 'Backup' settings menu."
        )

        viewModel.actionsDelegate = self
        // Run as soon as we've set the actionDelegate.
        viewModel.loadBackupPlan()
    }
}

// MARK: -

extension BackupSettingsViewController: BackupSettingsViewModel.ActionsDelegate {
    fileprivate func enableBackups() {
        // TODO: [Backups] Show the rest of the onboarding flow
        showChooseBackupPlan(initialPlanSelection: nil)
    }

    fileprivate func disableBackups() {
        Task { await _disableBackups() }
    }

    @MainActor
    private func _disableBackups() async {
        func errorActionSheet(_ message: String) {
            OWSActionSheets.showActionSheet(
                message: message,
                fromViewController: self
            )
        }

        do {
            guard let localIdentifiers = db.read(block: { tx in
                tsAccountManager.localIdentifiers(tx: tx)
            }) else {
                errorActionSheet(OWSLocalizedString(
                    "BACKUP_SETTINGS_DISABLE_ERROR_NOT_REGISTERED",
                    comment: "Message shown in an action sheet when the user tries to disable Backups, but is not registered."
                ))
                return
            }

            try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: self
            ) {
                try await self.backupIdManager.deleteBackupId(
                    localIdentifiers: localIdentifiers,
                    auth: .implicit()
                )
            }

            await db.awaitableWrite { tx in
                backupSettingsStore.setBackupPlan(nil, tx: tx)

                viewModel.reloadViewState(
                    backupSettingsStore: backupSettingsStore,
                    tx: tx
                )
            }
        } catch where error.isNetworkFailureOrTimeout {
            errorActionSheet(OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLE_ERROR_NETWORK_ERROR",
                comment: "Message shown in an action sheet when the user tries to disable Backups, but encountered a network error."
            ))
        } catch {
            owsFailDebug("Unexpectedly failed to disable Backups! \(error)")
            errorActionSheet(OWSLocalizedString(
                "BACKUP_SETTINGS_DISABLE_ERROR_GENERIC_ERROR",
                comment: "Message shown in an action sheet when the user tries to disable Backups, but encountered a generic error."
            ))
        }
    }

    // MARK: -

    fileprivate func loadBackupPlan() async throws -> BackupSettingsViewModel.BackupPlanLoadingState.LoadedBackupPlan {
        // TODO: [Backups] Remove when this goes to prod!
        try await Task.sleep(nanoseconds: 2.clampedNanoseconds)

        let backupSubscriberID: Data? = db.read { tx in
            backupSubscriptionManager.getIAPSubscriberData(tx: tx)?.subscriberId
        }

        guard
            let backupSubscriberID,
            let backupSubscription = try await SubscriptionFetcher(networkManager: networkManager)
                .fetch(subscriberID: backupSubscriberID)
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
                return .paidButCanceled(expirationDate: endOfCurrentPeriod)
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
        showChooseBackupPlan(initialPlanSelection: .free)
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

            db.read { tx in
                viewModel.reloadViewState(
                    backupSettingsStore: backupSettingsStore,
                    tx: tx
                )
            }
        }
    }

    fileprivate func resubscribeToPaidPlan() {
        showChooseBackupPlan(initialPlanSelection: .free)
    }

    private func showChooseBackupPlan(
        initialPlanSelection: ChooseBackupPlanViewController.PlanSelection?
    ) {
        guard let navigationController else {
            owsFailDebug("Missing nav controller!")
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: self
        ) { modal async -> Void in
            guard
                let paidPlanDisplayPrice = try? await self.backupSubscriptionManager
                    .subscriptionDisplayPrice()
            else {
                modal.dismiss()
                return
            }

            modal.dismiss {
                let chooseBackupPlanViewController = ChooseBackupPlanViewController(
                    initialPlanSelection: initialPlanSelection,
                    paidPlanDisplayPrice: paidPlanDisplayPrice
                )
                chooseBackupPlanViewController.delegate = self

                navigationController.pushViewController(
                    chooseBackupPlanViewController,
                    animated: true
                )
            }
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
}

// MARK: -

extension BackupSettingsViewController: ChooseBackupPlanViewController.Delegate {
    func chooseBackupPlanViewController(
        _ chooseBackupPlanViewController: ChooseBackupPlanViewController,
        didEnablePlan planSelection: ChooseBackupPlanViewController.PlanSelection
    ) {
        guard let navigationController else {
            owsFailDebug("Missing nav controller!")
            return
        }

        navigationController.popToViewController(self, animated: true) {
            self.db.read { tx in
                self.viewModel.reloadViewState(
                    backupSettingsStore: self.backupSettingsStore,
                    tx: tx
                )
            }

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
            self.present(welcomeToBackupsSheet, animated: true)
        }
    }
}

// MARK: -

private class BackupSettingsViewModel: ObservableObject {
    protocol ActionsDelegate: AnyObject {
        func enableBackups()
        func disableBackups()

        func loadBackupPlan() async throws -> BackupPlanLoadingState.LoadedBackupPlan
        func upgradeFromFreeToPaidPlan()
        func manageOrCancelPaidPlan()
        func resubscribeToPaidPlan()

        func performManualBackup()
        func setBackupFrequency(_ newBackupFrequency: BackupFrequency)
        func setShouldBackUpOnCellular(_ newShouldBackUpOnCellular: Bool)
    }

    enum BackupPlanLoadingState {
        enum LoadedBackupPlan {
            case free
            case paid(price: FiatMoney, renewalDate: Date)
            case paidButCanceled(expirationDate: Date)
        }

        case loading
        case loaded(LoadedBackupPlan)
        case networkError
        case genericError
    }

    @Published var backupPlanLoadingState: BackupPlanLoadingState
    @Published var areBackupsEnabled: Bool
    @Published var lastBackupDate: Date?
    @Published var lastBackupSizeBytes: UInt64?
    @Published var backupFrequency: BackupFrequency
    @Published var shouldBackUpOnCellular: Bool

    weak var actionsDelegate: ActionsDelegate?

    private let loadBackupPlanQueue: SerialTaskQueue

    init(
        areBackupsEnabled: Bool,
        lastBackupDate: Date?,
        lastBackupSizeBytes: UInt64?,
        backupFrequency: BackupFrequency,
        shouldBackUpOnCellular: Bool,
    ) {
        self.backupPlanLoadingState = .loading
        self.areBackupsEnabled = areBackupsEnabled
        self.lastBackupDate = lastBackupDate
        self.lastBackupSizeBytes = lastBackupSizeBytes
        self.backupFrequency = backupFrequency
        self.shouldBackUpOnCellular = shouldBackUpOnCellular

        self.loadBackupPlanQueue = SerialTaskQueue()
    }

    func reloadViewState(
        backupSettingsStore: BackupSettingsStore,
        tx: DBReadTransaction
    ) {
        areBackupsEnabled = backupSettingsStore.backupPlan(tx: tx) != nil
        lastBackupDate = backupSettingsStore.lastBackupDate(tx: tx)
        lastBackupSizeBytes = backupSettingsStore.lastBackupSizeBytes(tx: tx)
        backupFrequency = backupSettingsStore.backupFrequency(tx: tx)
        shouldBackUpOnCellular = backupSettingsStore.shouldBackUpOnCellular(tx: tx)

        loadBackupPlan()
    }

    // MARK: -

    func enableBackups() {
        guard !areBackupsEnabled else {
            owsFail("Attempting to enable backups, but they're already enabled!")
        }

        actionsDelegate?.enableBackups()
    }

    func disableBackups() {
        guard areBackupsEnabled else {
            owsFail("Attempting to disable backups, but they're already disabled!")
        }

        actionsDelegate?.disableBackups()
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
        guard case .loaded(.free) = backupPlanLoadingState else {
            owsFail("Attempting to upgrade from free plan, but not on free plan!")
        }

        actionsDelegate?.upgradeFromFreeToPaidPlan()
    }

    func manageOrCancelPaidPlan() {
        guard case .loaded(.paid) = backupPlanLoadingState else {
            owsFail("Attempting to manage/cancel paid plan, but not on paid plan!")
        }

        actionsDelegate?.manageOrCancelPaidPlan()
    }

    func resubscribeToPaidPlan() {
        guard case .loaded(.paidButCanceled) = backupPlanLoadingState else {
            owsFail("Attempting to restart paid plan, but not on paid-but-canceled plan!")
        }

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
}

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

            if viewModel.areBackupsEnabled {
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
                    BackupEnabledView(
                        lastBackupDate: viewModel.lastBackupDate,
                        lastBackupSizeBytes: viewModel.lastBackupSizeBytes,
                        backupFrequency: Binding(
                            get: { viewModel.backupFrequency },
                            set: { viewModel.setBackupFrequency($0) }
                        ),
                        shouldBackUpOnCellular: Binding(
                            get: { viewModel.shouldBackUpOnCellular },
                            set: { viewModel.setShouldBackUpOnCellular($0) }
                        )
                    )
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
            } else {
                SignalSection {
                    Button {
                        viewModel.enableBackups()
                    } label: {
                        Text(OWSLocalizedString(
                            "BACKUP_SETTINGS_REENABLE_BACKUPS_BUTTON_TITLE",
                            comment: "Title for a button allowing users to re-enable Backups, after it had been previously disabled."
                        ))
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUPS_DISABLED_SECTION_FOOTER",
                        comment: "Footer for a menu section related to settings for when Backups are disabled."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                }
            }
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
                    case .paid, .paidButCanceled:
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
                case .paidButCanceled(let expirationDate):
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
                    case .paidButCanceled:
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
                    case .paidButCanceled:
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

private struct BackupEnabledView: View {
    let lastBackupDate: Date?
    let lastBackupSizeBytes: UInt64?
    @Binding var backupFrequency: BackupFrequency
    @Binding var shouldBackUpOnCellular: Bool

    var body: some View {
        HStack {
            let lastBackupMessage: String? = {
                guard let lastBackupDate else {
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
            if let lastBackupSizeBytes {
                Text(lastBackupSizeBytes.formatted(.byteCount(style: .decimal)))
                    .foregroundStyle(Color.Signal.secondaryLabel)
            }
        }

        Picker(
            OWSLocalizedString(
                "BACKUP_SETTINGS_ENABLED_BACKUP_FREQUENCY_LABEL",
                comment: "Label for a menu item explaining the frequency of automatic backups."
            ),
            selection: $backupFrequency
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
                isOn: $shouldBackUpOnCellular
            )
        }

        NavigationLink {
            Text(LocalizationNotNeeded("Coming soon!"))
        } label: {
            Text(OWSLocalizedString(
                "BACKUP_SETTINGS_ENABLED_VIEW_BACKUP_KEY_LABEL",
                comment: "Label for a menu item offering to show the user their backup key."
            ))
        }
    }
}

// MARK: -

#if DEBUG

private extension BackupSettingsViewModel {
    static func forPreview(
        areBackupsEnabled: Bool = true,
        planLoadResult: Result<BackupPlanLoadingState.LoadedBackupPlan, Error>,
    ) -> BackupSettingsViewModel {
        class PreviewActionsDelegate: ActionsDelegate {
            private let planLoadResult: Result<BackupPlanLoadingState.LoadedBackupPlan, Error>
            init(planLoadResult: Result<BackupPlanLoadingState.LoadedBackupPlan, Error>) {
                self.planLoadResult = planLoadResult
            }

            func enableBackups() { print("Enabling!") }
            func disableBackups() { print("Disabling!") }

            func loadBackupPlan() async throws -> BackupSettingsViewModel.BackupPlanLoadingState.LoadedBackupPlan {
                try! await Task.sleep(nanoseconds: 2.clampedNanoseconds)
                return try planLoadResult.get()
            }
            func upgradeFromFreeToPaidPlan() { print("Upgrading!") }
            func manageOrCancelPaidPlan() { print("Managing or canceling!") }
            func resubscribeToPaidPlan() { print("Resubscribing!") }

            func performManualBackup() { print("Manually backing up!") }
            func setBackupFrequency(_ newBackupFrequency: BackupFrequency) { print("Frequency: \(newBackupFrequency)") }
            func setShouldBackUpOnCellular(_ newShouldBackUpOnCellular: Bool) { print("Cellular: \(newShouldBackUpOnCellular)") }
        }

        let viewModel = BackupSettingsViewModel(
            areBackupsEnabled: areBackupsEnabled,
            lastBackupDate: Date().addingTimeInterval(-1 * .day),
            lastBackupSizeBytes: 2_400_000_000,
            backupFrequency: .daily,
            shouldBackUpOnCellular: false
        )
        let actionsDelegate = PreviewActionsDelegate(planLoadResult: planLoadResult)
        viewModel.actionsDelegate = actionsDelegate
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)

        viewModel.loadBackupPlan()
        return viewModel
    }
}

#Preview("Paid") {
    BackupSettingsView(viewModel: .forPreview(
        planLoadResult: .success(.paid(
            price: FiatMoney(currencyCode: "USD", value: 2.99),
            renewalDate: Date().addingTimeInterval(.week)
        ))
    ))
}

#Preview("Free") {
    BackupSettingsView(viewModel: .forPreview(
        planLoadResult: .success(.free)
    ))
}

#Preview("Expiring") {
    BackupSettingsView(viewModel: .forPreview(
        planLoadResult: .success(.paidButCanceled(
            expirationDate: Date().addingTimeInterval(.week)
        ))
    ))
}

#Preview("Network Error") {
    BackupSettingsView(viewModel: .forPreview(
        planLoadResult: .failure(OWSHTTPError.networkFailure(.genericTimeout))
    ))
}

#Preview("Generic Error") {
    BackupSettingsView(viewModel: .forPreview(
        planLoadResult: .failure(OWSGenericError(""))
    ))
}

#Preview("Disabled") {
    BackupSettingsView(viewModel: .forPreview(
        areBackupsEnabled: false,
        planLoadResult: .success(.free),
    ))
}

#endif
