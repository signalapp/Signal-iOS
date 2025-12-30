//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BadgeGiftingConfirmationViewController: OWSTableViewController2 {
    typealias PaymentMethodsConfiguration = DonationSubscriptionConfiguration.PaymentMethodsConfiguration

    // MARK: - View state

    let badge: ProfileBadge
    let price: FiatMoney
    private let paymentMethodsConfiguration: PaymentMethodsConfiguration
    let thread: TSContactThread

    private var previouslyRenderedDisappearingMessagesDuration: UInt32?

    override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    override var navbarBackgroundColorOverride: UIColor? { .clear }

    init(
        badge: ProfileBadge,
        price: FiatMoney,
        paymentMethodsConfiguration: PaymentMethodsConfiguration,
        thread: TSContactThread,
    ) {
        self.badge = badge
        self.price = price
        self.paymentMethodsConfiguration = paymentMethodsConfiguration
        self.thread = thread

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        title = OWSLocalizedString(
            "DONATION_ON_BEHALF_OF_A_FRIEND_CONFIRMATION_SCREEN_TITLE",
            comment: "Users can donate on a friend's behalf. This is the title on the screen where users confirm the donation, and can write a message for the friend.",
        )

        shouldAvoidKeyboard = true
        updateTableContents()

        tableView.keyboardDismissMode = .interactive
    }

    // MARK: - Callbacks

    func didCompleteDonation() {
        SignalApp.shared.presentConversationForThread(
            threadUniqueId: thread.uniqueId,
            action: .none,
            animated: false,
        )
        dismiss(animated: true) {
            SignalApp.shared.conversationSplitViewController?.present(
                BadgeGiftingThanksSheet(thread: self.thread, badge: self.badge),
                animated: true,
            )
        }
    }

    private func checkRecipientAndPresentChoosePaymentMethodSheet() {
        // We want to resign this SOMETIME before this VC dismisses and switches to the chat.
        // In addition to offering slightly better UX, resigning first responder status prevents it
        // from eating events after the VC is dismissed.
        messageTextView.resignFirstResponder()

        Task {
            guard await DonationViewsUtil.Gifts.showSafetyNumberConfirmationIfNecessary(for: self.thread) else {
                Logger.warn("[Gifting] User canceled flow")
                return
            }

            let recipientFullName = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                SSKEnvironment.shared.contactManagerRef.displayName(for: self.thread, transaction: transaction)
            }

            let sheet = DonateChoosePaymentMethodSheet(
                amount: self.price,
                badge: self.badge,
                donationMode: .gift(recipientFullName: recipientFullName),
                supportedPaymentMethods: DonationUtilities.supportedDonationPaymentMethods(
                    forDonationMode: .gift,
                    usingCurrency: self.price.currencyCode,
                    withConfiguration: self.paymentMethodsConfiguration,
                    localNumber: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber,
                ),
                didChoosePaymentMethod: { [weak self] sheet, paymentMethod in
                    sheet.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        switch paymentMethod {
                        case .applePay:
                            self.startApplePay()
                        case .creditOrDebitCard:
                            self.startCreditOrDebitCard()
                        case .paypal:
                            self.startPaypal()
                        case .sepa, .ideal:
                            owsFail("Bank transfer not supported for gift badges")
                        }
                    }
                },
            )

            self.present(sheet, animated: true)
        }
    }

    // MARK: - Table contents

    private lazy var avatarViewDataSource: ConversationAvatarDataSource = .thread(self.thread)

    private lazy var messageTextView: TextViewWithPlaceholder = {
        let view = TextViewWithPlaceholder()
        view.placeholderText = OWSLocalizedString(
            "DONATE_ON_BEHALF_OF_A_FRIEND_ADDITIONAL_MESSAGE_PLACEHOLDER",
            comment: "Users can donate on a friend's behalf and can optionally add a message. This is the placeholder in the text field for that additional message.",
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
            badged: true,
        )

        let (recipientName, disappearingMessagesDuration) = SSKEnvironment.shared.databaseStorageRef.read { transaction -> (String, UInt32) in
            avatarView.update(transaction) { config in
                config.dataSource = avatarViewDataSource
            }

            let recipientName = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: transaction)
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            let disappearingMessagesDuration = dmConfigurationStore.durationSeconds(for: thread, tx: transaction)
            return (recipientName, disappearingMessagesDuration)
        }

        let badgeSection = OWSTableSection()
        badgeSection.add(.init(customCellBlock: {
            let cell = AppSettingsViewsUtil.newCell()

            let badgeCellView = GiftBadgeCellView(badge: badge, price: price)
            cell.contentView.addSubview(badgeCellView)
            badgeCellView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let recipientSection = OWSTableSection()
        recipientSection.add(.init(customCellBlock: {
            let cell = AppSettingsViewsUtil.newCell()

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
                    useShortFormat: true,
                )
                disappearingMessagesTimerLabelView.font = .dynamicTypeSubheadline
                disappearingMessagesTimerLabelView.textAlignment = .center
                disappearingMessagesTimerLabelView.minimumScaleFactor = 0.8

                let disappearingMessagesTimerView = UIStackView(arrangedSubviews: [
                    iconView,
                    disappearingMessagesTimerLabelView,
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
        messageInfoSection.add(.init(customCellBlock: {
            let cell = AppSettingsViewsUtil.newCell()
            cell.layoutMargins = .zero

            let messageInfoLabel = UILabel()
            messageInfoLabel.text = OWSLocalizedString(
                "DONATE_ON_BEHALF_OF_A_FRIEND_ADDITIONAL_MESSAGE_INFO",
                comment: "Users can donate on a friend's behalf and can optionally add a message. This is tells users about that optional message.",
            )
            messageInfoLabel.font = .dynamicTypeSubheadline
            messageInfoLabel.textColor = .Signal.label
            messageInfoLabel.numberOfLines = 0
            cell.contentView.addSubview(messageInfoLabel)
            messageInfoLabel.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let messageTextSection = OWSTableSection()
        messageTextSection.add(self.textViewItem(messageTextView, minimumHeight: 102))

        var sections: [OWSTableSection] = [
            badgeSection,
            recipientSection,
            messageInfoSection,
            messageTextSection,
        ]

        if disappearingMessagesDuration != 0 {
            let disappearingMessagesInfoSection = OWSTableSection()
            disappearingMessagesInfoSection.hasBackground = false
            disappearingMessagesInfoSection.add(.init(customCellBlock: {
                let cell = AppSettingsViewsUtil.newCell()
                cell.layoutMargins = .zero

                let disappearingMessagesInfoLabel = UILabel()
                disappearingMessagesInfoLabel.font = .dynamicTypeSubheadline
                disappearingMessagesInfoLabel.textColor = .Signal.secondaryLabel
                disappearingMessagesInfoLabel.numberOfLines = 0

                let format = OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_DISAPPEARING_MESSAGES_NOTICE_FORMAT",
                    comment: "When users make donations on a friend's behalf, a message is sent. This text tells senders that their message will disappear, if the conversation has disappearing messages enabled. Embeds {{duration}}, such as \"1 week\".",
                )
                let durationString = String.formatDurationLossless(
                    durationSeconds: disappearingMessagesDuration,
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

    override open var bottomFooter: UIView? {
        get { bottomFooterContainer }
        set {}
    }

    private lazy var bottomFooterContainer: UIView = {
        let amountView: UIStackView = {
            let descriptionLabel = UILabel()
            descriptionLabel.text = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_PAYMENT_DESCRIPTION",
                comment: "Users can donate on a friend's behalf. This tells users that this will be a one-time donation.",
            )
            descriptionLabel.font = .dynamicTypeBody
            descriptionLabel.textColor = .Signal.label
            descriptionLabel.numberOfLines = 0

            let priceLabel = UILabel()
            priceLabel.text = CurrencyFormatter.format(money: price)
            priceLabel.font = .dynamicTypeHeadline
            priceLabel.textColor = .Signal.label
            priceLabel.numberOfLines = 1

            let view = UIStackView(arrangedSubviews: [descriptionLabel, priceLabel])
            view.axis = .horizontal
            view.distribution = .equalSpacing
            view.autoSetDimension(.height, toSize: 48)

            return view
        }()

        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                self?.checkRecipientAndPresentChoosePaymentMethodSheet()
            },
        )

        let stackView = UIStackView(arrangedSubviews: [
            amountView,
            continueButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16

        let view = UIView()
        view.preservesSuperviewLayoutMargins = true
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        return view
    }()
}

// MARK: - Database observer delegate

extension BadgeGiftingConfirmationViewController: DatabaseChangeDelegate {
    private func updateDisappearingMessagesTimerWithSneakyTransaction() {
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmSeconds = SSKEnvironment.shared.databaseStorageRef.read { tx in
            dmConfigurationStore.durationSeconds(for: thread, tx: tx)
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
    func textView(
        _ textView: TextViewWithPlaceholder,
        uiTextView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String,
    ) -> Bool {
        if text == "\n" {
            uiTextView.resignFirstResponder()
        }
        return true
    }
}
