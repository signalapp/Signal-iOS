//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import SignalUI

final public class CLVReminderViews {

    fileprivate let reminderViewCell = UITableViewCell()
    fileprivate let reminderStackView = UIStackView()
    fileprivate let expiredView = ExpirationNagView(
        dateProvider: Date.provider,
        appExpiry: DependenciesBridge.shared.appExpiry,
        osExpiry: OsExpiry.default,
        device: UIDevice.current
    )
    fileprivate var deregisteredView = UIView()
    fileprivate var outageView = UIView()
    fileprivate var archiveReminderView = UIView()
    fileprivate let paymentsReminderView = UIView()
    fileprivate var usernameCorruptedReminderView = UIView()
    fileprivate var usernameLinkCorruptedReminderView = UIView()

    public weak var chatListViewController: ChatListViewController?

    init() {
        AssertIsOnMainThread()

        reminderStackView.axis = .vertical
        reminderStackView.spacing = 0
        reminderViewCell.selectionStyle = .none
        reminderViewCell.contentView.addSubview(reminderStackView)
        reminderStackView.autoPinEdgesToSuperviewEdges()
        reminderViewCell.accessibilityIdentifier = "reminderViewCell"
        reminderStackView.accessibilityIdentifier = "reminderStackView"

        let deregisteredText: String
        let deregisteredActionTitle: String
        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true {
            deregisteredText = OWSLocalizedString(
                "DEREGISTRATION_WARNING",
                comment: "Label warning the user that they have been de-registered."
            )
            deregisteredActionTitle = OWSLocalizedString(
                "DEREGISTRATION_WARNING_ACTION_TITLE",
                comment: "If the user has been deregistered, they'll see a warning. This is This is the call to action on that warning."
            )
        } else {
            deregisteredText = OWSLocalizedString(
                "UNLINKED_WARNING",
                comment: "Label warning the user that they have been unlinked from their primary device."
            )
            deregisteredActionTitle = OWSLocalizedString(
                "UNLINKED_WARNING_ACTION_TITLE",
                comment: "If this device has become unlinked from their primary device, they'll see a warning. This is the call to action on that warning."
            )
        }
        deregisteredView = ReminderView(
            style: .warning,
            text: deregisteredText,
            actionTitle: deregisteredActionTitle,
            tapAction: { [weak self] in self?.didTapDeregisteredView() }
        )
        reminderStackView.addArrangedSubview(deregisteredView)
        deregisteredView.accessibilityIdentifier = "deregisteredView"

        reminderStackView.addArrangedSubview(expiredView)
        expiredView.accessibilityIdentifier = "expiredView"

        outageView = ReminderView(
            style: .warning,
            text: OWSLocalizedString(
                "OUTAGE_WARNING",
                comment: "Label warning the user that the Signal service may be down."
            )
        )
        reminderStackView.addArrangedSubview(outageView)
        outageView.accessibilityIdentifier = "outageView"

        archiveReminderView = ReminderView(
            style: .info,
            text: {
                let shouldKeepMutedChatsArchived = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                    return SSKPreferences.shouldKeepMutedChatsArchived(transaction: transaction)
                }
                if shouldKeepMutedChatsArchived {
                    return OWSLocalizedString(
                        "INBOX_VIEW_ARCHIVE_MODE_MUTED_CHATS_REMINDER",
                        comment: "Label reminding the user that they are in archive mode, and that muted chats remain archived when they receive a new message."
                    )
                } else {
                    return OWSLocalizedString(
                        "INBOX_VIEW_ARCHIVE_MODE_REMINDER",
                        comment: "Label reminding the user that they are in archive mode, and that chats are unarchived when they receive a new message."
                    )
                }
            }()
        )
        reminderStackView.addArrangedSubview(archiveReminderView)
        archiveReminderView.accessibilityIdentifier = "archiveReminderView"

        reminderStackView.addArrangedSubview(paymentsReminderView)
        paymentsReminderView.accessibilityIdentifier = "paymentsReminderView"

        usernameCorruptedReminderView = ReminderView(
            style: .info,
            text: OWSLocalizedString(
                "REMINDER_VIEW_USERNAME_CORRUPTED_WARNING",
                comment: "Label warning the user that something is wrong with their username."
            ),
            actionTitle: OWSLocalizedString(
                "REMINDER_VIEW_USERNAME_CORRUPTED_FIX_BUTTON",
                comment: "Button below the warning to fix a corrupted username."
            ),
            tapAction: { [weak self] in self?.didTapUsernameCorruptedReminderView() }
        )
        usernameLinkCorruptedReminderView = ReminderView(
            style: .info,
            text: OWSLocalizedString(
                "REMINDER_VIEW_USERNAME_LINK_CORRUPTED_WARNING",
                comment: "Label warning the user that something is wrong with their username link."
            ),
            actionTitle: OWSLocalizedString(
                "REMINDER_VIEW_USERNAME_LINK_CORRUPTED_FIX_BUTTON",
                comment: "Button below the warning to fix a username link."
            ),
            tapAction: { [weak self] in self?.didTapUsernameLinkCorruptedReminderView() }
        )
        reminderStackView.addArrangedSubviews([
            usernameCorruptedReminderView,
            usernameLinkCorruptedReminderView
        ])
    }

    @objc
    private func didTapDeregisteredView() {
        AssertIsOnMainThread()

        guard let chatListViewController else {
            return
        }

        RegistrationUtils.showReregistrationUI(
            fromViewController: chatListViewController,
            appReadiness: chatListViewController.appReadiness
        )
    }

    @objc
    private func didTapUsernameCorruptedReminderView() {
        guard let chatListViewController else {
            return
        }

        UsernameSelectionCoordinator(
            currentUsername: nil,
            isAttemptingRecovery: true,
            usernameSelectionDelegate: chatListViewController,
            context: .init(
                databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                networkManager: SSKEnvironment.shared.networkManagerRef,
                storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef,
                usernameEducationManager: DependenciesBridge.shared.usernameEducationManager,
                localUsernameManager: DependenciesBridge.shared.localUsernameManager
            )
        )
        .present(fromViewController: chatListViewController)
    }

    @objc
    private func didTapUsernameLinkCorruptedReminderView() {
        guard let chatListViewController else {
            return
        }

        chatListViewController.showAppSettings(mode: .corruptedUsernameLinkResolution)
    }

    public var hasVisibleReminders: Bool {
        (
            !self.archiveReminderView.isHidden ||
            !self.deregisteredView.isHidden ||
            !self.outageView.isHidden ||
            !self.expiredView.isHidden ||
            !self.paymentsReminderView.isHidden ||
            !self.usernameCorruptedReminderView.isHidden ||
            !self.usernameLinkCorruptedReminderView.isHidden
        )
    }
}

// MARK: -

extension ChatListViewController {

    public var unreadPaymentNotificationsCount: UInt {
        get { viewState.unreadPaymentNotificationsCount }
        set { viewState.unreadPaymentNotificationsCount = newValue }
    }

    fileprivate var firstUnreadPaymentModel: TSPaymentModel? {
        get { viewState.firstUnreadPaymentModel }
        set { viewState.firstUnreadPaymentModel = newValue }
    }

    var hasBackupFailureState: CLVViewState.BackupFailureBadgeType? {
        get { viewState.hasBackupFailure }
        set { viewState.hasBackupFailure = newValue }
    }

    public var reminderViewCell: UITableViewCell { reminderViews.reminderViewCell }

    fileprivate var reminderStackView: UIStackView { reminderViews.reminderStackView }
    fileprivate var expiredView: ExpirationNagView { reminderViews.expiredView }
    fileprivate var deregisteredView: UIView { reminderViews.deregisteredView }
    fileprivate var outageView: UIView { reminderViews.outageView }
    fileprivate var archiveReminderView: UIView { reminderViews.archiveReminderView }
    fileprivate var paymentsReminderView: UIView { reminderViews.paymentsReminderView }
    fileprivate var usernameCorruptedReminderView: UIView { reminderViews.usernameCorruptedReminderView }
    fileprivate var usernameLinkCorruptedReminderView: UIView { reminderViews.usernameLinkCorruptedReminderView }

    public var reminderViews: CLVReminderViews { viewState.reminderViews }

    public func updateArchiveReminderView() {
        archiveReminderView.isHidden = viewState.chatListMode != .archive
    }

    public func updateRegistrationReminderView() {
        let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction
        deregisteredView.isHidden = !tsRegistrationState.isDeregistered
    }

    public func updateOutageDetectionReminderView() {
        outageView.isHidden = !OutageDetection.shared.hasOutage
    }

    public func updateExpirationReminderView() {
        expiredView.update()
    }

    public func updatePaymentReminderView() {
        if unreadPaymentNotificationsCount == 1, let firstUnreadPaymentModel = self.firstUnreadPaymentModel {
            self.paymentsReminderView.isHidden = false

            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                self.configureUnreadPaymentsBannerSingle(
                    paymentsReminderView,
                    paymentModel: firstUnreadPaymentModel,
                    transaction: transaction
                )
            }
        } else if unreadPaymentNotificationsCount == 0 || firstUnreadPaymentModel == nil {
            self.paymentsReminderView.isHidden = true
        } else {
            self.paymentsReminderView.isHidden = false
            self.configureUnreadPaymentsBannerMultiple(paymentsReminderView, unreadCount: unreadPaymentNotificationsCount)
        }
    }

    public func updateUsernameReminderView() {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            updateUsernameStateViews(tx: tx)
        }
    }

    public func updateBackupErrorStateWithSneakyTransaction() {
        var result: CLVViewState.BackupFailureBadgeType?
        let stateManager = DependenciesBridge.shared.backupFailureStateManager
        let backupSettingsStore = BackupSettingsStore()

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            if backupSettingsStore.getLastBackupFailed(tx: tx) {
                result = []
                CLVViewState.BackupFailureBadgeType.allCases.forEach { type in
                    if stateManager.shouldShowErrorBadge(target: type.target, tx: tx) {
                        result?.update(with: type)
                    }
                }
            }
        }

        self.hasBackupFailureState = result
    }

    public func updateUnreadPaymentNotificationsCountWithSneakyTransaction() {
        AssertIsOnMainThread()

        guard SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled else {
            var needsUpdate = false

            if unreadPaymentNotificationsCount > 0 {
                unreadPaymentNotificationsCount = 0
                needsUpdate = true
            }

            if firstUnreadPaymentModel != nil {
                firstUnreadPaymentModel = nil
                needsUpdate = true
            }

            if needsUpdate {
                updatePaymentReminderView()
            }

            return
        }

        let (unreadPaymentNotificationsCount, firstUnreadPaymentModel) = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return (
                PaymentFinder.unreadCount(transaction: transaction),
                PaymentFinder.firstUnreadPaymentModel(transaction: transaction)
            )
        }

        self.unreadPaymentNotificationsCount = unreadPaymentNotificationsCount
        self.firstUnreadPaymentModel = firstUnreadPaymentModel

        updatePaymentReminderView()
    }

    /// Update reminder views as appropriate for the current username state.
    private func updateUsernameStateViews(tx: DBReadTransaction) {
        let currentUsernameState = DependenciesBridge.shared.localUsernameManager
            .usernameState(tx: tx)

        switch currentUsernameState {
        case .unset, .available:
            usernameCorruptedReminderView.isHidden = true
            usernameLinkCorruptedReminderView.isHidden = true
        case .linkCorrupted:
            usernameCorruptedReminderView.isHidden = true
            usernameLinkCorruptedReminderView.isHidden = false
        case .usernameAndLinkCorrupted:
            usernameCorruptedReminderView.isHidden = false
            usernameLinkCorruptedReminderView.isHidden = true
        }
    }
}

extension ChatListViewController: UsernameSelectionDelegate {
    func usernameSelectionDidDismissAfterConfirmation(username: String) {
        self.presentToast(
            text: String(
                format: OWSLocalizedString(
                    "USERNAME_RESET_SUCCESSFUL_TOAST",
                    comment: "A message in a toast informing the user their username, link, and QR code have successfully been reset. Embeds {{ the user's new username }}."
                ),
                username
            ),
            extraVInset: 8
        )
    }
}
