//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit
import SignalMessaging
import UIKit

@objc
public extension ChatListViewController {

    func reloadTableDataAndResetCellContentCache() {
        AssertIsOnMainThread()

        cellContentCache.clear()
        conversationCellHeightCache = nil
        reloadTableData()
    }

    func reloadTableData() {
        AssertIsOnMainThread()
        InstrumentsMonitor.measure(category: "runtime", parent: "ChatListViewController", name: "reloadTableData") {
            var selectedThreadIds: Set<String> = []
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                if let key = tableDataSource.thread(forIndexPath: indexPath, expectsSuccess: false)?.uniqueId {
                    selectedThreadIds.insert(key)
                }
            }

            tableView.reloadData()

            if !selectedThreadIds.isEmpty {
                var threadIdsToBeSelected = selectedThreadIds
                for section in 0..<tableDataSource.numberOfSections(in: tableView) {
                    for row in 0..<tableDataSource.tableView(tableView, numberOfRowsInSection: section) {
                        let indexPath = IndexPath(row: row, section: section)
                        if let key = tableDataSource.thread(forIndexPath: indexPath, expectsSuccess: false)?.uniqueId, threadIdsToBeSelected.contains(key) {
                            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
                            threadIdsToBeSelected.remove(key)
                            if threadIdsToBeSelected.isEmpty {
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    func updateCellVisibility() {
        AssertIsOnMainThread()

        for cell in tableView.visibleCells {
            guard let cell = cell as? ChatListCell else {
                continue
            }
            updateCellVisibility(cell: cell, isCellVisible: true)
        }
    }

    func updateCellVisibility(cell: ChatListCell, isCellVisible: Bool) {
        AssertIsOnMainThread()

        cell.isCellVisible = self.isViewVisible && isCellVisible
    }

    func ensureCellAnimations() {
        AssertIsOnMainThread()

        for cell in tableView.visibleCells {
            guard let cell = cell as? ChatListCell else {
                continue
            }
            cell.ensureCellAnimations()
        }
    }

    // MARK: -

    func showBadgeExpirationSheetIfNeeded() {
        Logger.info("[Subscriptions] Checking whether we should show badge expiration sheet...")

        guard !hasShownBadgeExpiration else { // Do this once per launch
            Logger.info("[Subscriptions] Not showing badge expiration sheet, because we've already done so")
            return
        }

        let (
            expiredBadgeID,
            shouldShowExpirySheet,
            mostRecentSubscriptionBadgeChargeFailure,
            hasCurrentSubscription
        ) = databaseStorage.read { transaction in (
            SubscriptionManager.mostRecentlyExpiredBadgeID(transaction: transaction),
            SubscriptionManager.showExpirySheetOnHomeScreenKey(transaction: transaction),
            SubscriptionManager.getMostRecentSubscriptionBadgeChargeFailure(transaction: transaction),
            subscriptionManager.hasCurrentSubscription(transaction: transaction)
        )}

        guard let expiredBadgeID = expiredBadgeID else {
            Logger.info("[Subscriptions] No expired badge ID, not showing sheet")
            return
        }

        guard shouldShowExpirySheet else {
            Logger.info("[Subscriptions] Not showing badge expiration sheet because the flag is off")
            return
        }

        Logger.info("[Subscriptions] showing expiry sheet for expired badge \(expiredBadgeID)")

        if BoostBadgeIds.contains(expiredBadgeID) {
            firstly {
                SubscriptionManager.getBoostBadge()
            }.done(on: .global()) { boostBadge in
                firstly {
                    self.profileManager.badgeStore.populateAssetsOnBadge(boostBadge)
                }.done(on: .main) {
                    // Make sure we're still the active VC
                    guard UIApplication.shared.frontmostViewController == self.conversationSplitViewController,
                          self.conversationSplitViewController?.selectedThread == nil else { return }

                    let badgeSheet = BadgeExpirationSheet(badge: boostBadge,
                                                          mode: .boostExpired(hasCurrentSubscription: hasCurrentSubscription))
                    badgeSheet.delegate = self
                    self.present(badgeSheet, animated: true)
                    self.hasShownBadgeExpiration = true
                    self.databaseStorage.write { transaction in
                        SubscriptionManager.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
                    }
                }.catch { error in
                    owsFailDebug("Failed to fetch boost badge assets for expiry \(error)")
                }
            }.catch { error in
                owsFailDebug("Failed to fetch boost badge for expiry \(error)")
            }
        } else if SubscriptionBadgeIds.contains(expiredBadgeID) {
            // Fetch current subscriptions, required to populate badge assets
            firstly {
                SubscriptionManager.getSubscriptions()
            }.done(on: .global()) { (subscriptions: [SubscriptionLevel]) in
                let subscriptionLevel = subscriptions.first { $0.badge.id == expiredBadgeID }
                guard let subscriptionLevel = subscriptionLevel else {
                    owsFailDebug("Unable to find matching subscription level for expired badge")
                    return
                }

                firstly {
                    self.profileManager.badgeStore.populateAssetsOnBadge(subscriptionLevel.badge)
                }.done(on: .main) {
                    // Make sure we're still the active VC
                    guard UIApplication.shared.frontmostViewController == self.conversationSplitViewController,
                          self.conversationSplitViewController?.selectedThread == nil else { return }

                    let mode: BadgeExpirationSheetState.Mode
                    if let mostRecentSubscriptionBadgeChargeFailure = mostRecentSubscriptionBadgeChargeFailure {
                        mode = .subscriptionExpiredBecauseOfChargeFailure(chargeFailure: mostRecentSubscriptionBadgeChargeFailure)
                    } else {
                        mode = .subscriptionExpiredBecauseNotRenewed
                    }
                    let badgeSheet = BadgeExpirationSheet(badge: subscriptionLevel.badge, mode: mode)
                    badgeSheet.delegate = self
                    self.present(badgeSheet, animated: true)
                    self.hasShownBadgeExpiration = true
                    self.databaseStorage.write { transaction in
                        SubscriptionManager.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
                    }
                }.catch { error in
                    owsFailDebug("Failed to fetch subscription badge assets for expiry \(error)")
                }

            }.catch { error in
                owsFailDebug("Failed to fetch subscriptions for expiry \(error)")
            }
        }
    }

    // MARK: -

    func configureUnreadPaymentsBannerSingle(_ paymentsReminderView: UIView,
                                             paymentModel: TSPaymentModel,
                                             transaction: SDSAnyReadTransaction) {

        guard paymentModel.isIncoming,
              !paymentModel.isUnidentified,
              let address = paymentModel.address,
              let paymentAmount = paymentModel.paymentAmount,
              paymentAmount.isValid else {
            configureUnreadPaymentsBannerMultiple(paymentsReminderView, unreadCount: 1)
            return
        }
        guard nil != TSContactThread.getWithContactAddress(address, transaction: transaction) else {
            configureUnreadPaymentsBannerMultiple(paymentsReminderView, unreadCount: 1)
            return
        }

        let userName = contactsManager.shortDisplayName(for: address, transaction: transaction)
        let formattedAmount = PaymentsFormat.format(paymentAmount: paymentAmount,
                                                    isShortForm: true,
                                                    withCurrencyCode: true,
                                                    withSpace: true)
        let format = NSLocalizedString("PAYMENTS_NOTIFICATION_BANNER_1_WITH_DETAILS_FORMAT",
                                       comment: "Format for the payments notification banner for a single payment notification with details. Embeds: {{ %1$@ the name of the user who sent you the payment, %2$@ the amount of the payment }}.")
        let title = String(format: format, userName, formattedAmount)

        let avatarView = ConversationAvatarView(sizeClass: .customDiameter(Self.paymentsBannerAvatarSize), localUserDisplayMode: .asUser)
        avatarView.update(transaction) { config in
            config.dataSource = .address(address)
        }

        let paymentsHistoryItem = PaymentsHistoryItem(paymentModel: paymentModel,
                                                      displayName: userName)

        configureUnreadPaymentsBanner(paymentsReminderView,
                                      title: title,
                                      avatarView: avatarView) { [weak self] in
            self?.showAppSettings(mode: .payment(paymentsHistoryItem: paymentsHistoryItem))
        }
    }

    func configureUnreadPaymentsBannerMultiple(_ paymentsReminderView: UIView,
                                               unreadCount: UInt) {
        let title: String
        if unreadCount == 1 {
            title = NSLocalizedString("PAYMENTS_NOTIFICATION_BANNER_1",
                                      comment: "Label for the payments notification banner for a single payment notification.")
        } else {
            let format = NSLocalizedString("PAYMENTS_NOTIFICATION_BANNER_N_FORMAT",
                                           comment: "Format for the payments notification banner for multiple payment notifications. Embeds: {{ the number of unread payment notifications }}.")
            title = String(format: format, OWSFormat.formatUInt(unreadCount))
        }

        let iconView = UIImageView.withTemplateImageName(Theme.iconName(.paymentNotification),
                                                         tintColor: (Theme.isDarkThemeEnabled
                                                                        ? .ows_gray15
                                                                        : .ows_white))
        iconView.autoSetDimensions(to: .square(24))
        let iconCircleView = OWSLayerView.circleView(size: CGFloat(Self.paymentsBannerAvatarSize))
        iconCircleView.backgroundColor = (Theme.isDarkThemeEnabled
                                            ? .ows_gray80
                                            : .ows_gray95)
        iconCircleView.addSubview(iconView)
        iconView.autoCenterInSuperview()

        configureUnreadPaymentsBanner(paymentsReminderView,
                                      title: title,
                                      avatarView: iconCircleView) { [weak self] in
            self?.showAppSettings(mode: .payments)
        }
    }

    private static let paymentsBannerAvatarSize: UInt = 40

    private class PaymentsBannerView: UIView {
        let block: () -> Void

        required init(block: @escaping () -> Void) {
            self.block = block

            super.init(frame: .zero)

            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc
        func didTap() {
            block()
        }
    }

    private func configureUnreadPaymentsBanner(_ paymentsReminderView: UIView,
                                               title: String,
                                               avatarView: UIView,
                                               block: @escaping () -> Void) {
        paymentsReminderView.removeAllSubviews()

        let paymentsBannerView = PaymentsBannerView(block: block)
        paymentsReminderView.addSubview(paymentsBannerView)
        paymentsBannerView.autoPinEdgesToSuperviewEdges()

        if UIDevice.current.isIPad {
            paymentsReminderView.backgroundColor = (Theme.isDarkThemeEnabled
                                                        ? .ows_gray75
                                                        : .ows_gray05)
        } else {
            paymentsReminderView.backgroundColor = (Theme.isDarkThemeEnabled
                                                        ? .ows_gray90
                                                        : .ows_gray02)
        }

        avatarView.setCompressionResistanceHigh()
        avatarView.setContentHuggingHigh()

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        let viewLabel = UILabel()
        viewLabel.text = CommonStrings.viewButton
        viewLabel.textColor = Theme.accentBlueColor
        viewLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped

        let textStack = UIStackView(arrangedSubviews: [ titleLabel, viewLabel ])
        textStack.axis = .vertical
        textStack.alignment = .leading

        let dismissButton = OWSLayerView.circleView(size: 20)
        dismissButton.backgroundColor = (Theme.isDarkThemeEnabled
                                            ? .ows_gray65
                                            : .ows_gray05)
        dismissButton.setCompressionResistanceHigh()
        dismissButton.setContentHuggingHigh()

        let dismissIcon = UIImageView.withTemplateImageName("x-16",
                                                            tintColor: (Theme.isDarkThemeEnabled
                                                                            ? .ows_white
                                                                            : .ows_gray60))
        dismissIcon.autoSetDimensions(to: .square(16))
        dismissButton.addSubview(dismissIcon)
        dismissIcon.autoCenterInSuperview()

        let stack = UIStackView(arrangedSubviews: [ avatarView,
                                                    textStack,
                                                    dismissButton ])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.layoutMargins = UIEdgeInsets(
            top: OWSTableViewController2.cellVInnerMargin,
            left: OWSTableViewController2.cellHOuterLeftMargin(in: view),
            bottom: OWSTableViewController2.cellVInnerMargin,
            right: OWSTableViewController2.cellHOuterRightMargin(in: view)
        )
        stack.isLayoutMarginsRelativeArrangement = true
        paymentsBannerView.addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()
    }
}

// MARK: -

public enum ShowAppSettingsMode {
    case none
    case payments
    case payment(paymentsHistoryItem: PaymentsHistoryItem)
    case paymentsTransferIn
    case appearance
    case avatarBuilder
    case subscriptions
    case boost
    case proxy
}

// MARK: -

public extension ChatListViewController {
    func createAvatarBarButtonViewWithSneakyTransaction() -> UIView {
        let avatarView = ConversationAvatarView(sizeClass: .twentyEight, localUserDisplayMode: .asUser)
        databaseStorage.read { readTx in
            avatarView.update(readTx) { config in
                if let address = tsAccountManager.localAddress(with: readTx) {
                    config.dataSource = .address(address)
                    config.applyConfigurationSynchronously()
                }
            }
        }
        return avatarView
    }

    @objc
    func createSettingsBarButtonItem() -> UIBarButtonItem {
        let contextButton = ContextMenuButton()
        contextButton.showsContextMenuAsPrimaryAction = true
        contextButton.contextMenu = settingsContextMenu()
        contextButton.accessibilityLabel = CommonStrings.openSettingsButton

        let avatarImageView = createAvatarBarButtonViewWithSneakyTransaction()
        contextButton.addSubview(avatarImageView)
        avatarImageView.autoPinEdgesToSuperviewEdges()

        let wrapper = UIView.container()
        wrapper.addSubview(contextButton)
        contextButton.autoPinEdgesToSuperviewEdges()

        if unreadPaymentNotificationsCount > 0 {
            PaymentsViewUtils.addUnreadBadge(toView: wrapper)
        }

        return .init(customView: wrapper)
    }

    func settingsContextMenu() -> ContextMenu {
        var contextMenuActions: [ContextMenuAction] = []
        if renderState.inboxCount > 0 {
            contextMenuActions.append(
                ContextMenuAction(
                    title: NSLocalizedString("HOME_VIEW_TITLE_SELECT_CHATS", comment: "Title for the 'Select Chats' option in the ChatList."),
                    image: Theme.isDarkThemeEnabled ? UIImage(named: "check-circle-solid-24")?.tintedImage(color: .white) : UIImage(named: "check-circle-outline-24"),
                    attributes: [],
                    handler: { [weak self] (_) in
                        self?.willEnterMultiselectMode()
                    }))
        }
        contextMenuActions.append(
            ContextMenuAction(
                title: CommonStrings.openSettingsButton,
                image: Theme.isDarkThemeEnabled ? UIImage(named: "settings-solid-24")?.tintedImage(color: .white) : UIImage(named: "settings-outline-24"),
                attributes: [],
                handler: { [weak self] (_) in
                        self?.showAppSettings(mode: .none)
            }))
        if renderState.archiveCount > 0 {
            contextMenuActions.append(
                ContextMenuAction(
                    title: NSLocalizedString("HOME_VIEW_TITLE_ARCHIVE", comment: "Title for the conversation list's 'archive' mode."),
                    image: Theme.isDarkThemeEnabled ? UIImage(named: "archive-solid-24")?.tintedImage(color: .white) : UIImage(named: "archive-outline-24"),
                    attributes: [],
                    handler: { [weak self] (_) in
                        self?.showArchivedConversations(offerMultiSelectMode: true)
                }))
        }
        return .init(contextMenuActions)
    }

    @objc
    func showAppSettings() {
        showAppSettings(mode: .none)
    }

    @objc
    func showAppSettingsInAppearanceMode() {
        showAppSettings(mode: .appearance)
    }

    @objc
    func showAppSettingsInProxyMode() {
        showAppSettings(mode: .proxy)
    }

    @objc
    func showAppSettingsInAvatarBuilderMode() {
        showAppSettings(mode: .avatarBuilder)
    }

    func showAppSettings(mode: ShowAppSettingsMode) {
        AssertIsOnMainThread()

        Logger.info("")

        // Dismiss any message actions if they're presented
            conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)

        let navigationController = AppSettingsViewController.inModalNavigationController()

        var completion: (() -> Void)?

        var viewControllers = navigationController.viewControllers
        switch mode {
        case .none:
            break
        case .payments:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            viewControllers += [ paymentsSettings ]
        case .payment(let paymentsHistoryItem):
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            let paymentsDetail = PaymentsDetailViewController(paymentItem: paymentsHistoryItem)
            viewControllers += [ paymentsSettings, paymentsDetail ]
        case .paymentsTransferIn:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            let paymentsTransferIn = PaymentsTransferInViewController()
            viewControllers += [ paymentsSettings, paymentsTransferIn ]
        case .appearance:
            let appearance = AppearanceSettingsTableViewController()
            viewControllers += [ appearance ]
        case .avatarBuilder:
            let profile = ProfileSettingsViewController()
            viewControllers += [ profile ]
            completion = { profile.presentAvatarSettingsView() }
        case .subscriptions:
            let subscriptions = SubscriptionViewController()
            viewControllers += [ subscriptions ]
        case .boost:
            let boost = BoostViewController()
            viewControllers += [ boost ]
        case .proxy:
            viewControllers += [ PrivacySettingsViewController(), AdvancedPrivacySettingsViewController(), ProxySettingsViewController() ]
        }
        navigationController.setViewControllers(viewControllers, animated: false)
        presentFormSheet(navigationController, animated: true, completion: completion)
    }
}

extension ChatListViewController: BadgeExpirationSheetDelegate {
    func badgeExpirationSheetActionTapped(_ action: BadgeExpirationSheetAction) {
        switch action {
        case .dismiss:
            break
        case .openBoostView:
            showAppSettings(mode: .boost)
        case .openSubscriptionsView:
            showAppSettings(mode: .subscriptions)
        }
    }
}

extension ChatListViewController: ThreadSwipeHandler {
    func updateUIAfterSwipeAction() {
        updateViewState()
    }
}

// MARK: - First conversation label

extension ChatListViewController {
    @objc
    func updateFirstConversationLabel() {
        let signalAccounts = suggestedAccountsForFirstContact(maxCount: 3)

        var contactNames = databaseStorage.read { transaction in
            signalAccounts.map { account in
                self.contactsManagerImpl.displayName(forSignalAccount: account, transaction: transaction)
            }
        }

        let formatString = { () -> String in
            switch contactNames.count {
            case 0:
                return OWSLocalizedString(
                    "HOME_VIEW_FIRST_CONVERSATION_OFFER_NO_CONTACTS",
                    comment: "A label offering to start a new conversation with your contacts, if you have no Signal contacts."
                )
            case 1:
                return OWSLocalizedString(
                    "HOME_VIEW_FIRST_CONVERSATION_OFFER_1_CONTACT_FORMAT",
                    comment: "Format string for a label offering to start a new conversation with your contacts, if you have 1 Signal contact.  Embeds {{The name of 1 of your Signal contacts}}."
                )
            case 2:
                return OWSLocalizedString(
                    "HOME_VIEW_FIRST_CONVERSATION_OFFER_2_CONTACTS_FORMAT",
                    comment: "Format string for a label offering to start a new conversation with your contacts, if you have 2 Signal contacts.  Embeds {{The names of 2 of your Signal contacts}}."
                )
            case 3:
                break
            default:
                owsFailDebug("Unexpectedly had \(contactNames.count) names, expected at most 3!")
                contactNames = Array(contactNames.prefix(3))
            }

            return OWSLocalizedString(
                "HOME_VIEW_FIRST_CONVERSATION_OFFER_3_CONTACTS_FORMAT",
                comment: "Format string for a label offering to start a new conversation with your contacts, if you have at least 3 Signal contacts.  Embeds {{The names of 3 of your Signal contacts}}."
            )
        }()

        let attributedString = NSAttributedString.make(
            fromFormat: formatString,
            attributedFormatArgs: contactNames.map { name in
                return .string(name, attributes: [.font: firstConversationLabel.font.ows_semibold])
            }
        )

        firstConversationLabel.attributedText = attributedString
    }

    private func suggestedAccountsForFirstContact(maxCount: UInt) -> [SignalAccount] {
        // Load all signal accounts even though we only need the first N;
        // we want the returned value to be stable so we need to sort.
        let sortedSignalAccounts = contactsManagerImpl.sortedSignalAccountsWithSneakyTransaction()

        // Get up to 3 accounts to suggest, excluding ourselves.
        var suggestedAccounts = [SignalAccount]()
        for account in sortedSignalAccounts {
            guard suggestedAccounts.count < maxCount else {
                break
            }

            guard !account.recipientAddress.isLocalAddress else {
                continue
            }

            suggestedAccounts.append(account)
        }

        return suggestedAccounts
    }
}
