//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

class BadgeGiftingConfirmationViewController: OWSTableViewController2 {
    typealias PaymentMethodsConfiguration = SubscriptionManagerImpl.DonationConfiguration.PaymentMethodsConfiguration

    // MARK: - View state

    let badge: ProfileBadge
    let price: FiatMoney
    private let paymentMethodsConfiguration: PaymentMethodsConfiguration
    let thread: TSContactThread

    private var previouslyRenderedDisappearingMessagesDuration: UInt32?

    public override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    public override var navbarBackgroundColorOverride: UIColor? { .clear }

    public init(
        badge: ProfileBadge,
        price: FiatMoney,
        paymentMethodsConfiguration: PaymentMethodsConfiguration,
        thread: TSContactThread
    ) {
        self.badge = badge
        self.price = price
        self.paymentMethodsConfiguration = paymentMethodsConfiguration
        self.thread = thread
    }

    // MARK: - Callbacks

    public override func viewDidLoad() {
        self.shouldAvoidKeyboard = true

        super.viewDidLoad()

        databaseStorage.appendDatabaseChangeDelegate(self)

        title = OWSLocalizedString(
            "DONATION_ON_BEHALF_OF_A_FRIEND_CONFIRMATION_SCREEN_TITLE",
            comment: "Users can donate on a friend's behalf. This is the title on the screen where users confirm the donation, and can write a message for the friend."
        )

        updateTableContents()
        setUpBottomFooter()

        tableView.keyboardDismissMode = .onDrag
    }

    public override func themeDidChange() {
        super.themeDidChange()
        setUpBottomFooter()
    }

    func didCompleteDonation() {
        SignalApp.shared.presentConversationForThread(thread, action: .none, animated: false)
        dismiss(animated: true) {
            SignalApp.shared.conversationSplitViewController?.present(
                BadgeGiftingThanksSheet(thread: self.thread, badge: self.badge),
                animated: true
            )
        }
    }

    /// Queries the database to see if the recipient can receive gift badges.
    private func canReceiveGiftBadgesViaDatabase() -> Bool {
        databaseStorage.read { transaction -> Bool in
            self.profileManager.getUserProfile(for: self.thread.contactAddress, transaction: transaction)?.canReceiveGiftBadges ?? false
        }
    }

    enum ProfileFetchError: Error { case timeout }

    /// Fetches the recipient's profile, then queries the database to see if they can receive gift badges.
    /// Times out after 30 seconds.
    private func canReceiveGiftBadgesViaProfileFetch() -> Promise<Bool> {
        firstly {
            ProfileFetcherJob.fetchProfilePromise(address: self.thread.contactAddress, ignoreThrottling: true)
        }.timeout(seconds: 30) {
            ProfileFetchError.timeout
        }.map { [weak self] _ in
            self?.canReceiveGiftBadgesViaDatabase() ?? false
        }
    }

    /// Look up whether the recipient can receive gift badges.
    /// If the operation takes more half a second, we show a spinner.
    /// We first consult the database.
    /// If they are capable there, we don't need to fetch their profile.
    /// If they aren't (or we have no profile saved), we fetch the profile because we might have stale data.
    private func canReceiveGiftBadgesWithUi() -> Promise<Bool> {
        if canReceiveGiftBadgesViaDatabase() {
            return Promise.value(true)
        }

        let (resultPromise, resultFuture) = Promise<Bool>.pending()

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false,
                                                     presentationDelay: 0.5) { modal in
            firstly {
                self.canReceiveGiftBadgesViaProfileFetch()
            }.done(on: DispatchQueue.main) { canReceiveGiftBadges in
                modal.dismiss { resultFuture.resolve(canReceiveGiftBadges) }
            }.catch(on: DispatchQueue.main) { error in
                modal.dismiss { resultFuture.reject(error) }
            }
        }

        return resultPromise
    }

    private func checkRecipientAndPresentChoosePaymentMethodSheet() {
        // We want to resign this SOMETIME before this VC dismisses and switches to the chat.
        // In addition to offering slightly better UX, resigning first responder status prevents it
        // from eating events after the VC is dismissed.
        messageTextView.resignFirstResponder()

        firstly(on: DispatchQueue.main) { [weak self] () -> Promise<Bool> in
            guard let self = self else {
                throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
            }
            return self.canReceiveGiftBadgesWithUi()
        }.then(on: DispatchQueue.main) { [weak self] canReceiveGiftBadges -> Promise<DonationViewsUtil.Gifts.SafetyNumberConfirmationResult> in
            guard let self = self else {
                throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
            }
            guard canReceiveGiftBadges else {
                throw DonationViewsUtil.Gifts.SendGiftError.cannotReceiveGiftBadges
            }
            return DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(for: self.thread).promise
        }.done(on: DispatchQueue.main) { [weak self] safetyNumberConfirmationResult in
            guard let self = self else {
                throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
            }

            switch safetyNumberConfirmationResult {
            case .userDidNotConfirmSafetyNumberChange:
                throw DonationViewsUtil.Gifts.SendGiftError.userCanceledBeforeChargeCompleted
            case .userConfirmedSafetyNumberChangeOrNoChangeWasNeeded:
                break
            }

            let recipientFullName = self.databaseStorage.read { transaction in
                self.contactsManager.displayName(for: self.thread, transaction: transaction)
            }

            let sheet = DonateChoosePaymentMethodSheet(
                amount: self.price,
                badge: self.badge,
                donationMode: .gift(recipientFullName: recipientFullName),
                supportedPaymentMethods: DonationUtilities.supportedDonationPaymentMethods(
                    forDonationMode: .gift,
                    usingCurrency: self.price.currencyCode,
                    withConfiguration: self.paymentMethodsConfiguration,
                    localNumber: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
                )
            ) { [weak self] (sheet, paymentMethod) in
                sheet.dismiss(animated: true) { [weak self] in
                    guard let self else { return }
                    switch paymentMethod {
                    case .applePay:
                        self.startApplePay()
                    case .creditOrDebitCard:
                        self.startCreditOrDebitCard()
                    case .paypal:
                        self.startPaypal()
                    }
                }
            }

            self.present(sheet, animated: true)
        }.catch { error in
            if let error = error as? DonationViewsUtil.Gifts.SendGiftError {
                Logger.warn("[Gifting] Error \(error)")
                switch error {
                case .userCanceledBeforeChargeCompleted:
                    return
                case .cannotReceiveGiftBadges:
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "DONATION_ON_BEHALF_OF_A_FRIEND_RECIPIENT_CANNOT_RECEIVE_DONATION_ERROR_TITLE",
                            comment: "Users can donate on a friend's behalf. If the friend cannot receive these donations, an error dialog will be shown. This is the title of that error dialog."
                        ),
                        message: OWSLocalizedString(
                            "DONATION_ON_BEHALF_OF_A_FRIEND_RECIPIENT_CANNOT_RECEIVE_DONATION_ERROR_BODY",
                            comment: "Users can donate on a friend's behalf. If the friend cannot receive these donations, this error message will be shown."
                        )
                    )
                    return
                default:
                    break
                }
            }

            owsFailDebugUnlessNetworkFailure(error)
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_GENERIC_SEND_ERROR_TITLE",
                    comment: "Users can donate on a friend's behalf. If something goes wrong during this donation, such as a network error, an error dialog is shown. This is the title of that dialog."
                ),
                message: OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_GENERIC_SEND_ERROR_BODY",
                    comment: "Users can donate on a friend's behalf. If something goes wrong during this donation, such as a network error, this error message is shown."
                )
            )
        }
    }

    // MARK: - Table contents

    private lazy var avatarViewDataSource: ConversationAvatarDataSource = .thread(self.thread)

    lazy var messageTextView: TextViewWithPlaceholder = {
        let view = TextViewWithPlaceholder()
        view.placeholderText = OWSLocalizedString(
            "DONATE_ON_BEHALF_OF_A_FRIEND_ADDITIONAL_MESSAGE_PLACEHOLDER",
            comment: "Users can donate on a friend's behalf and can optionally add a message. This is the placeholder in the text field for that additional message."
        )
        view.returnKeyType = .done
        view.delegate = self
        return view
    }()

    var messageText: String {
        (messageTextView.text ?? "").ows_stripped()
    }

    private func updateTableContents() {
        let badge = badge
        let price = price
        let avatarViewDataSource = avatarViewDataSource
        let thread = thread
        let messageTextView = messageTextView

        let avatarView = ConversationAvatarView(
            sizeClass: .thirtySix,
            localUserDisplayMode: .asUser,
            badged: true
        )

        let (recipientName, disappearingMessagesDuration) = databaseStorage.read { transaction -> (String, UInt32) in
            avatarView.update(transaction) { config in
                config.dataSource = avatarViewDataSource
            }

            let recipientName = self.contactsManager.displayName(for: thread, transaction: transaction)
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let disappearingMessagesDuration = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)
            return (recipientName, disappearingMessagesDuration)
        }

        let badgeSection = OWSTableSection()
        badgeSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let badgeCellView = GiftBadgeCellView(badge: badge, price: price)
            cell.contentView.addSubview(badgeCellView)
            badgeCellView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let recipientSection = OWSTableSection()
        recipientSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let nameLabel = UILabel()
            nameLabel.text = recipientName
            nameLabel.font = .dynamicTypeBody
            nameLabel.numberOfLines = 0
            nameLabel.minimumScaleFactor = 0.5

            let avatarAndNameView = UIStackView(arrangedSubviews: [avatarView, nameLabel])
            avatarAndNameView.spacing = ContactCellView.avatarTextHSpacing

            let contactCellView = UIStackView()
            contactCellView.distribution = .equalSpacing

            contactCellView.addArrangedSubview(avatarAndNameView)

            if disappearingMessagesDuration != 0 {
                let iconView = UIImageView(image: UIImage(imageLiteralResourceName: "timer"))
                iconView.contentMode = .scaleAspectFit

                let disappearingMessagesTimerLabelView = UILabel()
                disappearingMessagesTimerLabelView.text = DateUtil.formatDuration(
                    seconds: disappearingMessagesDuration,
                    useShortFormat: true
                )
                disappearingMessagesTimerLabelView.font = .dynamicTypeBody2
                disappearingMessagesTimerLabelView.textAlignment = .center
                disappearingMessagesTimerLabelView.minimumScaleFactor = 0.8

                let disappearingMessagesTimerView = UIStackView(arrangedSubviews: [
                    iconView,
                    disappearingMessagesTimerLabelView
                ])
                disappearingMessagesTimerView.spacing = 4

                contactCellView.addArrangedSubview(disappearingMessagesTimerView)
            }

            cell.contentView.addSubview(contactCellView)
            contactCellView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let messageInfoSection = OWSTableSection()
        messageInfoSection.hasBackground = false
        messageInfoSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let messageInfoLabel = UILabel()
            messageInfoLabel.text = OWSLocalizedString(
                "DONATE_ON_BEHALF_OF_A_FRIEND_ADDITIONAL_MESSAGE_INFO",
                comment: "Users can donate on a friend's behalf and can optionally add a message. This is tells users about that optional message."
            )
            messageInfoLabel.font = .dynamicTypeBody2
            messageInfoLabel.textColor = Theme.primaryTextColor
            messageInfoLabel.numberOfLines = 0
            cell.contentView.addSubview(messageInfoLabel)
            messageInfoLabel.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let messageTextSection = OWSTableSection()
        messageTextSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            cell.contentView.addSubview(messageTextView)
            messageTextView.autoPinEdgesToSuperviewMargins()
            messageTextView.autoSetDimension(.height, toSize: 102, relation: .greaterThanOrEqual)

            return cell
        }))

        var sections: [OWSTableSection] = [
            badgeSection,
            recipientSection,
            messageInfoSection,
            messageTextSection
        ]

        if disappearingMessagesDuration != 0 {
            let disappearingMessagesInfoSection = OWSTableSection()
            disappearingMessagesInfoSection.hasBackground = false
            disappearingMessagesInfoSection.add(.init(customCellBlock: { [weak self] in
                guard let self else { return UITableViewCell() }
                let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

                let disappearingMessagesInfoLabel = UILabel()
                disappearingMessagesInfoLabel.font = .dynamicTypeBody2
                disappearingMessagesInfoLabel.textColor = Theme.secondaryTextAndIconColor
                disappearingMessagesInfoLabel.numberOfLines = 0

                let format = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_DISAPPEARING_MESSAGES_NOTICE_FORMAT",
                    comment: "When users make donations on a friend's behalf, a message is sent. This text tells senders that their message will disappear, if the conversation has disappearing messages enabled. Embeds {{duration}}, such as \"1 week\"."
                )
                let durationString = String.formatDurationLossless(
                    durationSeconds: disappearingMessagesDuration
                )
                disappearingMessagesInfoLabel.text = String(format: format, durationString)

                cell.contentView.addSubview(disappearingMessagesInfoLabel)
                disappearingMessagesInfoLabel.autoPinEdgesToSuperviewMargins()

                return cell
            }))

            sections.append(disappearingMessagesInfoSection)
        }

        contents = OWSTableContents(sections: sections)

        previouslyRenderedDisappearingMessagesDuration = disappearingMessagesDuration
    }

    // MARK: - Footer

    private let bottomFooterStackView = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomFooterStackView }
        set {}
    }

    private func setUpBottomFooter() {
        bottomFooterStackView.axis = .vertical
        bottomFooterStackView.alignment = .center
        bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor
        bottomFooterStackView.spacing = 16
        bottomFooterStackView.isLayoutMarginsRelativeArrangement = true
        bottomFooterStackView.preservesSuperviewLayoutMargins = true
        bottomFooterStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
        bottomFooterStackView.removeAllSubviews()

        let amountView: UIStackView = {
            let descriptionLabel = UILabel()
            descriptionLabel.text = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_PAYMENT_DESCRIPTION",
                comment: "Users can donate on a friend's behalf. This tells users that this will be a one-time donation."
            )
            descriptionLabel.font = .dynamicTypeBody
            descriptionLabel.numberOfLines = 0

            let priceLabel = UILabel()
            priceLabel.text = DonationUtilities.format(money: price)
            priceLabel.font = .dynamicTypeBody.semibold()
            priceLabel.numberOfLines = 0

            let view = UIStackView(arrangedSubviews: [descriptionLabel, priceLabel])
            view.axis = .horizontal
            view.distribution = .equalSpacing
            view.layoutMargins = cellOuterInsets
            view.isLayoutMarginsRelativeArrangement = true

            return view
        }()

        let continueButton = OWSButton(title: CommonStrings.continueButton) { [weak self] in
            self?.checkRecipientAndPresentChoosePaymentMethodSheet()
        }
        continueButton.dimsWhenHighlighted = true
        continueButton.layer.cornerRadius = 8
        continueButton.backgroundColor = .ows_accentBlue
        continueButton.titleLabel?.font = UIFont.dynamicTypeBody.semibold()

        for view in [amountView, continueButton] {
            bottomFooterStackView.addArrangedSubview(view)
            view.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
            view.autoPinWidthToSuperview(withMargin: 23)
        }
    }
}

// MARK: - Database observer delegate

extension BadgeGiftingConfirmationViewController: DatabaseChangeDelegate {
    private func updateDisappearingMessagesTimerWithSneakyTransaction() {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmSeconds = databaseStorage.read { tx in
            dmConfigurationStore.durationSeconds(for: thread, tx: tx.asV2Read)
        }
        if previouslyRenderedDisappearingMessagesDuration != dmSeconds {
            updateTableContents()
        }
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdate(thread: thread) {
            updateDisappearingMessagesTimerWithSneakyTransaction()
        }
    }

    func databaseChangesDidUpdateExternally() {
        updateDisappearingMessagesTimerWithSneakyTransaction()
    }

    func databaseChangesDidReset() {
        updateDisappearingMessagesTimerWithSneakyTransaction()
    }
}

// MARK: - Text view delegate

extension BadgeGiftingConfirmationViewController: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateSelection(_ textView: TextViewWithPlaceholder) {
        textView.scrollToFocus(in: tableView, animated: true)
    }

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        // Kick the tableview so it recalculates sizes
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil) { (_) in
                // And when the size changes have finished, make sure we're scrolled
                // to the focused line
                textView.scrollToFocus(in: self.tableView, animated: false)
            }
        }
    }

    func textView(_ textView: TextViewWithPlaceholder,
                  uiTextView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        if text == "\n" {
            uiTextView.resignFirstResponder()
        }
        return true
    }
}
