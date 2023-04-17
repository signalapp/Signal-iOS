//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class CLVReminderViews: NSObject {

    fileprivate let reminderViewCell = UITableViewCell()
    fileprivate let reminderStackView = UIStackView()
    fileprivate let expiredView = ExpirationNagView()
    fileprivate var deregisteredView = UIView()
    fileprivate var outageView = UIView()
    fileprivate var archiveReminderView = UIView()
    fileprivate let paymentsReminderView = UIView()
    fileprivate var usernameValidationFailedView = UIView()

    @objc
    public weak var viewController: ChatListViewController?

    required override init() {
        AssertIsOnMainThread()

        super.init()

        reminderStackView.axis = .vertical
        reminderStackView.spacing = 0
        reminderViewCell.selectionStyle = .none
        reminderViewCell.contentView.addSubview(reminderStackView)
        reminderStackView.autoPinEdgesToSuperviewEdges()
        reminderViewCell.accessibilityIdentifier = "reminderViewCell"
        reminderStackView.accessibilityIdentifier = "reminderStackView"

        deregisteredView = ReminderView.nag(text: (TSAccountManager.shared.isPrimaryDevice
                                                    ? NSLocalizedString("DEREGISTRATION_WARNING",
                                                                        comment: "Label warning the user that they have been de-registered.")
                                                    : NSLocalizedString("UNLINKED_WARNING",
                                                                        comment: "Label warning the user that they have been unlinked from their primary device.")),
                                            tapAction: { [weak self] in
                                                self?.didTapDeregisteredView()
                                            })
        reminderStackView.addArrangedSubview(deregisteredView)
        deregisteredView.accessibilityIdentifier = "deregisteredView"

        reminderStackView.addArrangedSubview(expiredView)
        expiredView.accessibilityIdentifier = "expiredView"

        outageView = ReminderView.nag(text: NSLocalizedString("OUTAGE_WARNING",
                                                              comment: "Label warning the user that the Signal service may be down."),
                                      tapAction: nil)
        reminderStackView.addArrangedSubview(outageView)
        outageView.accessibilityIdentifier = "outageView"

        archiveReminderView = ReminderView.explanation(text: (databaseStorage.read { SSKPreferences.shouldKeepMutedChatsArchived(transaction: $0) }
                                                              ? NSLocalizedString("INBOX_VIEW_ARCHIVE_MODE_MUTED_CHATS_REMINDER",
                                                                                  comment: "Label reminding the user that they are in archive mode, and that muted chats remain archived when they receive a new message.")
                                                              : NSLocalizedString("INBOX_VIEW_ARCHIVE_MODE_REMINDER",
                                                                                  comment: "Label reminding the user that they are in archive mode, and that chats are unarchived when they receive a new message.")))
        reminderStackView.addArrangedSubview(archiveReminderView)
        archiveReminderView.accessibilityIdentifier = "archiveReminderView"

        reminderStackView.addArrangedSubview(paymentsReminderView)
        paymentsReminderView.accessibilityIdentifier = "paymentsReminderView"

        usernameValidationFailedView = ReminderView.nag(
            text: OWSLocalizedString(
                "UNREGISTERED_USERNAME_WARNING",
                comment: "Label warning the user that the validation of their username has failed."
            ),
            tapAction: { [weak self] in
                self?.didTapFailedUsernameValidationView()
            }
        )
        reminderStackView.addArrangedSubview(usernameValidationFailedView)
        usernameValidationFailedView.accessibilityIdentifier = "usernameValidationFailedView"
    }

    @objc
    private func didTapDeregisteredView() {
        AssertIsOnMainThread()
        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        RegistrationUtils.showReregistrationUI(from: viewController)
    }

    @objc
    private func didTapFailedUsernameValidationView() {
        AssertIsOnMainThread()
        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        guard let localAci = tsAccountManager.localUuid else {
            owsFailDebug("Missing local ACI.")
            return
        }

        let usernameSelectionCoordinator = UsernameSelectionCoordinator(
            localAci: localAci,
            currentUsername: nil,
            context: .init(
                usernameEducationManager: DependenciesBridge.shared.usernameEducationManager,
                networkManager: self.networkManager,
                databaseStorage: self.databaseStorage,
                usernameLookupManager: DependenciesBridge.shared.usernameLookupManager,
                schedulers: DependenciesBridge.shared.schedulers,
                storageServiceManager: self.storageServiceManager
            )
        )
        usernameSelectionCoordinator.present(fromViewController: viewController)

        databaseStorage.write { transaction in
            DependenciesBridge.shared.usernameValidationManager.clearUsernameHasFailedValidation(transaction.asV2Write)
        }
    }

    public var hasVisibleReminders: Bool {
        (
            !self.archiveReminderView.isHidden ||
            !self.deregisteredView.isHidden ||
            !self.outageView.isHidden ||
            !self.expiredView.isHidden ||
            !self.paymentsReminderView.isHidden ||
            !self.usernameValidationFailedView.isHidden
        )
    }
}

// MARK: -

extension ChatListViewController {

    @objc
    public var unreadPaymentNotificationsCount: UInt {
        get { viewState.unreadPaymentNotificationsCount }
        set { viewState.unreadPaymentNotificationsCount = newValue }
    }

    fileprivate var firstUnreadPaymentModel: TSPaymentModel? {
        get { viewState.firstUnreadPaymentModel }
        set { viewState.firstUnreadPaymentModel = newValue }
    }

    @objc
    public var reminderViewCell: UITableViewCell { reminderViews.reminderViewCell }

    fileprivate var reminderStackView: UIStackView { reminderViews.reminderStackView }
    fileprivate var expiredView: ExpirationNagView { reminderViews.expiredView }
    fileprivate var deregisteredView: UIView { reminderViews.deregisteredView }
    fileprivate var outageView: UIView { reminderViews.outageView }
    fileprivate var archiveReminderView: UIView { reminderViews.archiveReminderView }
    fileprivate var paymentsReminderView: UIView { reminderViews.paymentsReminderView }
    fileprivate var usernameValidationFailedView: UIView { reminderViews.usernameValidationFailedView }

    @objc
    public var reminderViews: CLVReminderViews { viewState.reminderViews }

    @objc
    public func updateReminderViews() {
        AssertIsOnMainThread()

        archiveReminderView.isHidden = chatListMode != .archive
        deregisteredView.isHidden = !tsAccountManager.isDeregistered || tsAccountManager.isTransferInProgress
        outageView.isHidden = !OutageDetection.shared.hasOutage

        expiredView.update()

        if unreadPaymentNotificationsCount == 1,
           let firstUnreadPaymentModel = self.firstUnreadPaymentModel {
            self.paymentsReminderView.isHidden = false

            databaseStorage.read { transaction in
                self.configureUnreadPaymentsBannerSingle(paymentsReminderView,
                                                         paymentModel: firstUnreadPaymentModel,
                                                         transaction: transaction)
            }
        } else if unreadPaymentNotificationsCount == 0 || firstUnreadPaymentModel == nil {
            self.paymentsReminderView.isHidden = true
        } else {
            self.paymentsReminderView.isHidden = false
            self.configureUnreadPaymentsBannerMultiple(paymentsReminderView,
                                                       unreadCount: unreadPaymentNotificationsCount)
        }

        databaseStorage.read { transaction in
            usernameValidationFailedView.isHidden = !DependenciesBridge.shared.usernameValidationManager.hasUsernameFailedValidation(transaction.asV2Read)
        }

        loadCoordinator.loadIfNecessary()
    }

    @objc
    public func updateUnreadPaymentNotificationsCountWithSneakyTransaction() {
        AssertIsOnMainThread()

        guard paymentsHelper.arePaymentsEnabled else {
            self.unreadPaymentNotificationsCount = 0
            self.firstUnreadPaymentModel = nil

            updateBarButtonItems()
            updateReminderViews()
            return
        }

        let (unreadPaymentNotificationsCount, firstUnreadPaymentModel) = databaseStorage.read { transaction in
            return (
                PaymentFinder.unreadCount(transaction: transaction),
                PaymentFinder.firstUnreadPaymentModel(transaction: transaction)
            )
        }

        self.unreadPaymentNotificationsCount = unreadPaymentNotificationsCount
        self.firstUnreadPaymentModel = firstUnreadPaymentModel

        updateBarButtonItems()
        updateReminderViews()
    }
}
