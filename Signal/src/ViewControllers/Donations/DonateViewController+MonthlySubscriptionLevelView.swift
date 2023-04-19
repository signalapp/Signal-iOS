//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonateViewController {
    internal class MonthlySubscriptionLevelView: UIStackView {
        private let background: UIView = {
            let result = UIView()
            result.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth
            result.layer.cornerRadius = DonateViewController.cornerRadius
            return result
        }()

        private let headingStackView: UIStackView = {
            let result = UIStackView()
            result.axis = .horizontal
            result.distribution = .fill
            result.spacing = 4
            return result
        }()

        private let headingLabel: UILabel = {
            let result = UILabel()
            result.font = .dynamicTypeBody
            result.numberOfLines = 0
            result.setContentHuggingHorizontalHigh()
            result.setCompressionResistanceHorizontalHigh()
            return result
        }()

        private let subheadingLabel: UILabel = {
            let result = UILabel()
            result.font = .dynamicTypeBody2
            result.numberOfLines = 0
            return result
        }()

        public let subscriptionLevel: SubscriptionLevel
        public let animationName: String

        public init(subscriptionLevel: SubscriptionLevel, animationName: String) {
            self.subscriptionLevel = subscriptionLevel
            self.animationName = animationName

            super.init(frame: .zero)

            axis = .horizontal
            alignment = .center
            layoutMargins = UIEdgeInsets(hMargin: 12, vMargin: 9)
            isLayoutMarginsRelativeArrangement = true
            spacing = 10

            addSubview(background)
            background.autoPinEdgesToSuperviewEdges()

            let badge = subscriptionLevel.badge
            let imageView = UIImageView()
            if let badgeImage = badge.assets?.universal64 {
                imageView.image = badgeImage
            } else {
                Logger.warn("[Donations] Badge image failed to load")
            }
            addArrangedSubview(imageView)
            imageView.autoSetDimensions(to: .init(square: 40))

            let textStackView = UIStackView(arrangedSubviews: [headingStackView, subheadingLabel])
            textStackView.axis = .vertical
            textStackView.alignment = .fill
            textStackView.isLayoutMarginsRelativeArrangement = true
            textStackView.spacing = 4
            addArrangedSubview(textStackView)
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func render(
            currencyCode: Currency.Code,
            currentSubscription: Subscription?,
            selectedSubscriptionLevel: SubscriptionLevel?
        ) {
            let isCurrentSubscription: Bool = {
                guard let currentSubscription = currentSubscription else { return false }
                return (
                    currentSubscription.active &&
                    currentSubscription.level == subscriptionLevel.level &&
                    currentSubscription.amount.currencyCode == currencyCode
                )
            }()
            let isSelectedInUi = selectedSubscriptionLevel?.level == subscriptionLevel.level

            background.layer.backgroundColor = DonateViewController.bubbleBackgroundColor
            background.layer.borderColor = isSelectedInUi
            ? DonateViewController.selectedColor
            : DonateViewController.bubbleBackgroundColor

            headingLabel.text = {
                let format = NSLocalizedString(
                    "DONATE_SCREEN_MONTHLY_SUBSCRIPTION_TITLE",
                    comment: "On the donation screen, you can see a list of monthly subscription levels. This text will be shown as the title for each level, telling you the price per month. Embeds {{currency string}}, such as \"$5\"."
                )
                guard let price = subscriptionLevel.amounts[currencyCode] else {
                    owsFail("[Donations] No price for this currency code. This should be impossible in the UI")
                }
                let currencyString = DonationUtilities.format(money: price)
                return String(format: format, currencyString)
            }()
            headingStackView.removeAllSubviews()
            headingStackView.addArrangedSubview(headingLabel)
            if isCurrentSubscription {
                let checkmark = UIImageView(image: UIImage(named: "check-20")?.withRenderingMode(.alwaysTemplate))
                checkmark.tintColor = Theme.primaryTextColor
                headingStackView.addArrangedSubview(checkmark)
                checkmark.setCompressionResistanceHorizontalHigh()
                checkmark.autoSetDimensions(to: CGSize(square: 15))
            }

            subheadingLabel.text = {
                if isCurrentSubscription, let currentSubscription = currentSubscription {
                    let format: String
                    if currentSubscription.cancelAtEndOfPeriod {
                        format = NSLocalizedString(
                            "DONATE_SCREEN_MONTHLY_SUBSCRIPTION_EXPIRES_ON_DATE",
                            comment: "On the donation screen, you can see a list of monthly subscription levels. If you already have one of these and it expires soon, this text is shown below it indicating when it will expire. Embeds {{formatted renewal date}}, such as \"June 9, 2010\"."
                        )
                    } else {
                        format = NSLocalizedString(
                            "DONATE_SCREEN_MONTHLY_SUBSCRIPTION_RENEWS_ON_DATE",
                            comment: "On the donation screen, you can see a list of monthly subscription levels. If you already have one of these, this text is shown below it indicating when it will renew. Embeds {{formatted renewal date}}, such as \"June 9, 2010\"."
                        )
                    }

                    let date = Date(timeIntervalSince1970: currentSubscription.endOfCurrentPeriod)
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    let dateString = dateFormatter.string(from: date)

                    return String(format: format, dateString)
                } else {
                    let format = NSLocalizedString(
                        "DONATE_SCREEN_MONTHLY_SUBSCRIPTION_SUBTITLE",
                        comment: "On the donation screen, you can see a list of monthly subscription levels. This text will be shown in the subtitle of each level, telling you which badge you'll get. Embeds {{localized badge name}}, such as \"Planet\"."
                    )
                    return String(format: format, subscriptionLevel.badge.localizedName)
                }
            }()
        }
    }
}
