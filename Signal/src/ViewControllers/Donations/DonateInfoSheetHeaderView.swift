//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

class DonateInfoSheetHeaderView: UIStackView {
    init(amount: FiatMoney, badge: ProfileBadge?, donationMode: DonationMode) {
        super.init(frame: .zero)

        axis = .vertical
        alignment = .center
        spacing = 6

        if let assets = badge?.assets {
            let badgeImageView = UIImageView(image: assets.universal112)
            badgeImageView.autoSetDimensions(to: CGSize(square: 112))
            addArrangedSubview(badgeImageView)
            setCustomSpacing(12, after: badgeImageView)
        }

        let titleLabel = UILabel()
        titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.text = Self.titleText(for: amount, donationMode: donationMode)
        addArrangedSubview(titleLabel)

        if let bodyText = Self.bodyText(for: badge, donationMode: donationMode) {
            let bodyLabel = UILabel()
            bodyLabel.font = .ows_dynamicTypeBody
            bodyLabel.textColor = Theme.primaryTextColor
            bodyLabel.textAlignment = .center
            bodyLabel.numberOfLines = 0
            bodyLabel.lineBreakMode = .byWordWrapping
            bodyLabel.text = bodyText
            addArrangedSubview(bodyLabel)
        }
    }

    required init(coder: NSCoder) {
        owsFail("init(coder:) has not been implemented")
    }

    private static func titleText(for amount: FiatMoney, donationMode: DonationMode) -> String {
        let currencyString = DonationUtilities.format(money: amount)
        switch donationMode {
        case .oneTime:
            let format = NSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_TITLE_FOR_ONE_TIME_DONATION",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money}}, such as \"$5\"."
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
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. This is the title on that sheet. Embeds {{amount of money per month}}, such as \"$5/month\"."
            )
            return String(format: format, moneyPerMonthString)
        case .gift:
            owsFail("Not yet supported.")
        }
    }

    private static func bodyText(for badge: ProfileBadge?, donationMode: DonationMode) -> String? {
        guard let badge = badge else { return nil }

        let format: String
        switch donationMode {
        case .oneTime:
            format = NSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_ONE_TIME_DONATION",
                comment: "When users make one-time donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge for a month. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Boost\"." )
        case .monthly:
            format = NSLocalizedString(
                "DONATE_CHOOSE_PAYMENT_METHOD_SHEET_SUBTITLE_FOR_MONTHLY_DONATION",
                comment: "When users make monthly donations, they see a sheet that lets them pick a payment method. It also tells them what they'll be doing when they pay: receive a badge. This is the subtitle on that sheet. Embeds {{localized badge name}}, such as \"Planet\"."
            )
        case .gift:
            owsFail("Not yet supported.")
        }
        return String(format: format, badge.localizedName)
    }
}
