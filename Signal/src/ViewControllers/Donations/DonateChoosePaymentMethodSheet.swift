//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalServiceKit
import SignalMessaging

class DonateChoosePaymentMethodSheet: InteractiveSheetViewController {
    enum DonationMode {
        case oneTime
        case monthly
        case gift
    }

    private let amount: FiatMoney
    private let badge: ProfileBadge?
    private let donationMode: DonationMode
    private let didChoosePaymentMethod: (DonateChoosePaymentMethodSheet) -> Void

    private let scrollView = UIScrollView()
    override var interactiveScrollViews: [UIScrollView] { [scrollView] }
    override var sheetBackgroundColor: UIColor {
        OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
    }

    private let minHeight: CGFloat = 478
    private let hMargin: CGFloat = 32
    private let vMargin: CGFloat = 32
    private let buttonHeight: CGFloat = 48

    private var titleText: String {
        let currencyString = DonationUtilities.format(money: amount)
        switch donationMode {
        case .oneTime:
            let format = NSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_ONE_TIME_DONATION",
                value: "Donate %1$@ to Signal",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay. This is the title on that sheet. Embeds {{amount of money}}, such as \"$5\"."
            )
            return String(format: format, currencyString)
        case .monthly:
            let moneyPerMonthFormat = NSLocalizedString(
                "SUSTAINER_VIEW_PRICING",
                comment: "Pricing text for sustainer view badges, embeds {{price}}"
            )
            let moneyPerMonthString = String(format: moneyPerMonthFormat, currencyString)
            let format = NSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_MONTHLY_DONATION",
                value: "Donate %1$@ to Signal",
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay. This is the title on that sheet. Embeds {{amount of money per month}}, such as \"$5/month\"."
            )
            return String(format: format, moneyPerMonthString)
        case .gift:
            owsFail("Not yet supported.")
        }
    }

    private var bodyText: String? {
        guard let badge = badge else { return nil }

        let format: String
        switch donationMode {
        case .oneTime:
            format = NSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_ONE_TIME_DONATION",
                value: "Earn the %1$@ badge for one month",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge for a month. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Boost\"."
            )
        case .monthly:
            format = NSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_MONTHLY_DONATION",
                value: "Get the %1$@ badge",
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Planet\"."
            )
        case .gift:
            owsFail("Not yet supported.")
        }
        return String(format: format, badge.localizedName)
    }

    init(
        amount: FiatMoney,
        badge: ProfileBadge?,
        donationMode: DonationMode,
        didChoosePaymentMethod: @escaping (DonateChoosePaymentMethodSheet) -> Void
    ) {
        self.amount = amount
        self.badge = badge
        self.donationMode = donationMode
        self.didChoosePaymentMethod = didChoosePaymentMethod

        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View callbacks

    override public func viewDidLoad() {
        super.viewDidLoad()

        contentView.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        minimizedHeight = minHeight

        render()
    }

    override public func themeDidChange() {
        super.themeDidChange()
        render()
    }

    // MARK: - Rendering

    private func render() {
        let infoStackView: UIView = {
            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = 6

            if let assets = self.badge?.assets {
                let badgeImageView = UIImageView(image: assets.universal112)
                badgeImageView.autoSetDimensions(to: CGSize(square: 112))
                stackView.addArrangedSubview(badgeImageView)
                stackView.setCustomSpacing(12, after: badgeImageView)
            }

            let titleLabel = UILabel()
            titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.text = self.titleText
            stackView.addArrangedSubview(titleLabel)

            if let bodyText = self.bodyText {
                let bodyLabel = UILabel()
                bodyLabel.font = .ows_dynamicTypeBody
                bodyLabel.textColor = Theme.primaryTextColor
                bodyLabel.textAlignment = .center
                bodyLabel.numberOfLines = 0
                bodyLabel.lineBreakMode = .byWordWrapping
                bodyLabel.text = bodyText
                stackView.addArrangedSubview(bodyLabel)
            }

            return stackView
        }()

        let paymentButtonContainerView: UIView = {
            // When we add other payment methods, we should hide this button if
            // Apple Pay is unavailable.
            let applePayButton = ApplePayButton { [weak self] in
                guard let self = self else { return }
                self.didChoosePaymentMethod(self)
            }

            let stackView = UIStackView(arrangedSubviews: [applePayButton])
            stackView.axis = .vertical
            stackView.alignment = .fill
            stackView.spacing = 12

            applePayButton.autoSetDimension(.height, toSize: buttonHeight)

            return stackView
        }()

        let outerStackView = UIStackView(arrangedSubviews: [
            infoStackView,
            paymentButtonContainerView
        ])
        outerStackView.axis = .vertical
        outerStackView.spacing = 24
        outerStackView.alignment = .fill
        outerStackView.distribution = .fill
        outerStackView.layoutMargins = .init(hMargin: hMargin, vMargin: vMargin)
        outerStackView.isLayoutMarginsRelativeArrangement = true

        scrollView.removeAllSubviews()
        scrollView.addSubview(outerStackView)
        scrollView.layoutMargins = .zero

        outerStackView.autoPinWidth(toWidthOf: scrollView)
    }
}
