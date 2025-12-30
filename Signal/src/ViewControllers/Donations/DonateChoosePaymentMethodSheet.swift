//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class DonateChoosePaymentMethodSheet: StackSheetViewController {
    enum DonationMode {
        case oneTime
        case monthly
        case gift(recipientFullName: String)
    }

    private let amount: FiatMoney
    private let badge: ProfileBadge
    private let donationMode: DonationMode
    private let supportedPaymentMethods: Set<DonationPaymentMethod>
    private let didChoosePaymentMethod: (DonateChoosePaymentMethodSheet, DonationPaymentMethod) -> Void

    private let buttonHeight: CGFloat = if #available(iOS 26, *) { 52 } else { 48 }

    private var titleText: String {
        let currencyString = CurrencyFormatter.format(money: amount)
        switch donationMode {
        case .oneTime:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_ONE_TIME_DONATION",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money}}, such as \"$5\".",
            )
            return String(format: format, currencyString)
        case .monthly:
            let moneyPerMonthFormat = OWSLocalizedString(
                "SUSTAINER_VIEW_PRICING",
                comment: "Pricing text for sustainer view badges, embeds {{price}}",
            )
            let moneyPerMonthString = String(format: moneyPerMonthFormat, currencyString)
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_MONTHLY_DONATION",
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money per month}}, such as \"$5/month\".",
            )
            return String(format: format, moneyPerMonthString)
        case .gift:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_DONATION_ON_BEHALF_OF_A_FRIEND",
                comment: "When users make donations on a friend's behalf, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money}}, such as \"$5\".",
            )
            return String(format: format, currencyString)
        }
    }

    private var bodyText: String? {
        switch donationMode {
        case .oneTime:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_ONE_TIME_DONATION",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge for a month. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Boost\".",
            )
            return String(format: format, badge.localizedName)

        case .monthly:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_MONTHLY_DONATION",
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Planet\".",
            )
            return String(format: format, badge.localizedName)

        case let .gift(recipientFullName):
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_DONATION_ON_BEHALF_OF_A_FRIEND",
                comment: "When users make donations on a friend's behalf, they see a sheet that lets them pick a payment method. This is the subtitle on that sheet. Embeds {{recipient's name}}.",
            )
            return String(format: format, recipientFullName)
        }
    }

    init(
        amount: FiatMoney,
        badge: ProfileBadge,
        donationMode: DonationMode,
        supportedPaymentMethods: Set<DonationPaymentMethod>,
        didChoosePaymentMethod: @escaping (DonateChoosePaymentMethodSheet, DonationPaymentMethod) -> Void,
    ) {
        self.amount = amount
        self.badge = badge
        self.donationMode = donationMode
        self.supportedPaymentMethods = supportedPaymentMethods
        self.didChoosePaymentMethod = didChoosePaymentMethod

        super.init()
    }

    override var stackViewInsets: UIEdgeInsets {
        .init(top: 32, leading: 0, bottom: 0, trailing: 0)
    }

    // MARK: - Updating table contents

    override func viewDidLoad() {
        super.viewDidLoad()

        stackView.addArrangedSubviews([headerStack(), buttonsStack()])
        stackView.spacing = 24
    }

    func headerStack() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 6

        if let assets = badge.assets {
            let badgeImageView = UIImageView(image: assets.universal160)
            badgeImageView.autoSetDimensions(to: CGSize(square: 80))
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(12, after: badgeImageView)
        }

        let titleLabel = UILabel.title2Label(text: titleText)
        stackView.addArrangedSubview(titleLabel)

        if let bodyText {
            let bodyLabel = UILabel.explanationTextLabel(text: bodyText)
            stackView.addArrangedSubview(bodyLabel)
        }

        return stackView
    }

    private func buttonsStack() -> UIView {
        let paymentMethods: [DonationPaymentMethod]
        let applePayFirstRegions = PhoneNumberRegions(arrayLiteral: "1")

        if
            let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber,
            applePayFirstRegions.contains(e164: localNumber)
        {
            paymentMethods = [
                .applePay,
                .creditOrDebitCard,
                .paypal,
                .sepa,
                .ideal,
            ]
        } else {
            paymentMethods = [
                .ideal,
                .creditOrDebitCard,
                .paypal,
                .applePay,
                .sepa,
            ]
        }

        let paymentMethodButtons = paymentMethods
            .filter(supportedPaymentMethods.contains)
            .map(createButtonFor(paymentMethod:))

        owsPrecondition(!paymentMethodButtons.isEmpty, "Expected at least one payment method")

        let stackView = UIStackView.verticalButtonStack(buttons: paymentMethodButtons)

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
    }

    private func createButtonFor(paymentMethod: DonationPaymentMethod) -> UIButton {
        var fixedHeight = true
        let button: UIButton = {
            switch paymentMethod {
            case .applePay:
                return createApplePayButton()
            case .creditOrDebitCard:
                fixedHeight = false
                return createCreditOrDebitCardButton()
            case .paypal:
                return createPaypalButton()
            case .sepa:
                fixedHeight = false
                return createSEPAButton()
            case .ideal:
                return createIDEALButton()
            }
        }()
        button.translatesAutoresizingMaskIntoConstraints = false
        if fixedHeight {
            button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        } else {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: buttonHeight).isActive = true
        }

        return button
    }

    private func createApplePayButton() -> ApplePayButton {
        ApplePayButton { [weak self] in
            guard let self else { return }
            self.didChoosePaymentMethod(self, .applePay)
        }
    }

    private func createPaypalButton() -> PaypalButton {
        PaypalButton { [weak self] in
            guard let self else { return }
            self.didChoosePaymentMethod(self, .paypal)
        }
    }

    private func createPaymentMethodButton(
        title: String,
        image: UIImage?,
        action: @escaping () -> Void,
    ) -> UIButton {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = UIButton.Configuration.glass()
        } else {
            configuration = .bordered()
            configuration.background.cornerRadius = 12
            configuration.baseForegroundColor = .label
            configuration.baseBackgroundColor = .Signal.secondaryGroupedBackground
        }

        configuration.title = title
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        configuration.image = image
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 12)

        let button = UIButton(
            configuration: configuration,
            primaryAction: UIAction { _ in action() },
        )
        return button
    }

    private func createCreditOrDebitCardButton() -> UIButton {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .prominentGlass()
        } else {
            configuration = .borderedProminent()
            configuration.background.cornerRadius = 12
        }

        configuration.title = OWSLocalizedString(
            "DONATE_CHOOSE_CREDIT_OR_DEBIT_CARD_AS_PAYMENT_METHOD",
            comment: "When users make donations, they can choose which payment method they want to use. This is the text on the button that lets them choose to pay with credit or debit card.",
        )
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        configuration.image = UIImage(named: "payment")
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 12)

        let button = UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.didChoosePaymentMethod(self, .creditOrDebitCard)
            },
        )
        button.tintColor = UIColor.Signal.accent
        return button
    }

    private func createSEPAButton() -> UIButton {
        createPaymentMethodButton(
            title: OWSLocalizedString(
                "DONATE_CHOOSE_BANK_TRANSFER_AS_PAYMENT_METHOD",
                comment: "When users make donations, they can choose which payment method they want to use. This is the text on the button that lets them choose to pay with bank transfer.",
            ),
            image: UIImage(named: "building"),
        ) { [weak self] in
            guard let self else { return }
            self.didChoosePaymentMethod(self, .sepa)
        }
    }

    private func createIDEALButton() -> UIButton {
        createPaymentMethodButton(
            title: LocalizationNotNeeded("iDEAL"),
            image: UIImage(named: "logo_ideal"),
        ) { [weak self] in
            guard let self else { return }
            self.didChoosePaymentMethod(self, .ideal)
        }
    }
}
