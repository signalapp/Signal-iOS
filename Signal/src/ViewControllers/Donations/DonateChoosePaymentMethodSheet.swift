//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalServiceKit

class DonateChoosePaymentMethodSheet: OWSTableSheetViewController {
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

    private let buttonHeight: CGFloat = 48

    private var titleText: String {
        let currencyString = CurrencyFormatter.format(money: amount)
        switch donationMode {
        case .oneTime:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_ONE_TIME_DONATION",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money}}, such as \"$5\"."
            )
            return String(format: format, currencyString)
        case .monthly:
            let moneyPerMonthFormat = OWSLocalizedString(
                "SUSTAINER_VIEW_PRICING",
                comment: "Pricing text for sustainer view badges, embeds {{price}}"
            )
            let moneyPerMonthString = String(format: moneyPerMonthFormat, currencyString)
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_MONTHLY_DONATION",
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money per month}}, such as \"$5/month\"."
            )
            return String(format: format, moneyPerMonthString)
        case .gift:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_DONATION_ON_BEHALF_OF_A_FRIEND",
                comment: "When users make donations on a friend's behalf, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money}}, such as \"$5\"."
            )
            return String(format: format, currencyString)
        }
    }

    private var bodyText: String? {
        switch donationMode {
        case .oneTime:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_ONE_TIME_DONATION",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge for a month. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Boost\"." )
            return String(format: format, badge.localizedName)

        case .monthly:
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_MONTHLY_DONATION",
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Planet\"."
            )
            return String(format: format, badge.localizedName)

        case let .gift(recipientFullName):
            let format = OWSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_DONATION_ON_BEHALF_OF_A_FRIEND",
                comment: "When users make donations on a friend's behalf, they see a sheet that lets them pick a payment method. This is the subtitle on that sheet. Embeds {{recipient's name}}."
            )
            return String(format: format, recipientFullName)
        }
    }

    init(
        amount: FiatMoney,
        badge: ProfileBadge,
        donationMode: DonationMode,
        supportedPaymentMethods: Set<DonationPaymentMethod>,
        didChoosePaymentMethod: @escaping (DonateChoosePaymentMethodSheet, DonationPaymentMethod) -> Void
    ) {
        self.amount = amount
        self.badge = badge
        self.donationMode = donationMode
        self.supportedPaymentMethods = supportedPaymentMethods
        self.didChoosePaymentMethod = didChoosePaymentMethod

        super.init()
    }

    // MARK: - Updating table contents

    public override func tableContents() -> OWSTableContents {
        let infoStackView: UIView = {
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

            let titleLabel = UILabel()
            titleLabel.font = .dynamicTypeTitle2.semibold()
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.text = titleText
            stackView.addArrangedSubview(titleLabel)

            if let bodyText = bodyText {
                let bodyLabel = UILabel()
                bodyLabel.font = .dynamicTypeBody
                bodyLabel.textColor = Theme.primaryTextColor
                bodyLabel.textAlignment = .center
                bodyLabel.numberOfLines = 0
                bodyLabel.lineBreakMode = .byWordWrapping
                bodyLabel.text = bodyText
                stackView.addArrangedSubview(bodyLabel)
            }

            return stackView
        }()

        let section = OWSTableSection(items: [.init(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.contentView.addSubview(infoStackView)
            infoStackView.autoPinEdgesToSuperviewMargins()
            return cell
        })])
        section.hasBackground = false
        section.shouldDisableCellSelection = true

        return OWSTableContents(sections: [section])
    }

    public override func tableFooterView() -> UIView? {
        let paymentMethods: [DonationPaymentMethod]
        let applePayFirstRegions = PhoneNumberRegions(arrayLiteral: "1")

        if let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber,
           applePayFirstRegions.contains(e164: localNumber) {
            paymentMethods = [
                .applePay,
                .creditOrDebitCard,
                .paypal,
                .sepa,
                .ideal
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

        let stackView = UIStackView(arrangedSubviews: paymentMethodButtons)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        stackView.directionalLayoutMargins = .init(top: 0, leading: 20, bottom: 20, trailing: 20)
        stackView.isLayoutMarginsRelativeArrangement = true

        for button in paymentMethodButtons {
            button.autoSetDimension(.height, toSize: buttonHeight)
        }

        return stackView
    }

    private func createButtonFor(paymentMethod: DonationPaymentMethod) -> UIView {
        switch paymentMethod {
        case .applePay:
            return createApplePayButton()
        case .creditOrDebitCard:
            return createCreditOrDebitCardButton()
        case .paypal:
            return createPaypalButton()
        case .sepa:
            return createSEPAButton()
        case .ideal:
            return createIDEALButton()
        }
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
        action: @escaping () -> Void
    ) -> UIButton {
        var config = UIButton.Configuration.bordered()
        if #available(iOS 26, *), FeatureFlags.iOS26SDKIsAvailable {
#if compiler(>=6.2)
            config = UIButton.Configuration.glass()
#endif
        } else {
            config.background.cornerRadius = 12
            config.baseForegroundColor = .label
            config.baseBackgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .white
        }

        config.title = title
        config.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBodyClamped.semibold())
        config.image = image
        config.imagePadding = 8

        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { _ in action() }
        )
        return button
    }

    private func createCreditOrDebitCardButton() -> UIButton {
        var config = UIButton.Configuration.borderedProminent()
        if #available(iOS 26, *), FeatureFlags.iOS26SDKIsAvailable {
#if compiler(>=6.2)
            config = UIButton.Configuration.prominentGlass()
#endif
        } else {
            config.background.cornerRadius = 12
        }

        config.title = OWSLocalizedString(
            "DONATE_CHOOSE_CREDIT_OR_DEBIT_CARD_AS_PAYMENT_METHOD",
            comment: "When users make donations, they can choose which payment method they want to use. This is the text on the button that lets them choose to pay with credit or debit card."
        )
        config.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBodyClamped.semibold())
        config.image = UIImage(named: "payment")
        config.imagePadding = 8

        let button = UIButton(
            configuration: config,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.didChoosePaymentMethod(self, .creditOrDebitCard)
            }
        )
        button.tintColor = UIColor.Signal.accent
        return button
    }

    private func createSEPAButton() -> UIButton {
        createPaymentMethodButton(
            title: OWSLocalizedString(
                "DONATE_CHOOSE_BANK_TRANSFER_AS_PAYMENT_METHOD",
                comment: "When users make donations, they can choose which payment method they want to use. This is the text on the button that lets them choose to pay with bank transfer."
            ),
            image: UIImage(named: "building")
        ) { [weak self] in
            guard let self else { return }
            self.didChoosePaymentMethod(self, .sepa)
        }
    }

    private func createIDEALButton() -> UIButton {
        createPaymentMethodButton(
            title: LocalizationNotNeeded("iDEAL"),
            image: UIImage(named: "logo_ideal")
        ) { [weak self] in
            guard let self else { return }
            self.didChoosePaymentMethod(self, .ideal)
        }
    }
}
