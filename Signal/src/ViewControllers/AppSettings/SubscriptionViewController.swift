//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI
import SignalServiceKit
import UIKit
import BonMot
import PassKit

class SubscriptionViewController: OWSTableViewController2 {

    private var subscriptions: [SubscriptionLevel]? {
        didSet {
            if let newSubscriptions = subscriptions, selectedSubscription == nil {
                selectedSubscription = newSubscriptions.first ?? nil
            }
            updateTableContents()
        }
    }

    private var selectedSubscription: SubscriptionLevel?

    private var currencyCode = Stripe.defaultCurrencyCode {
        didSet {
            guard oldValue != currencyCode else { return }
            updateTableContents()
        }
    }

    private lazy var avatarView: ConversationAvatarView = {
        let newAvatarView = ConversationAvatarView(sizeClass: .eightyEight, badged: true)
        databaseStorage.read { readTx in
            newAvatarView.update(readTx) { config in
                if let address = tsAccountManager.localAddress(with: readTx) {
                    config.dataSource = .address(address)
                }
            }
        }
        return newAvatarView
    }()

    private let bottomFooterStackView = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomFooterStackView }
        set {}
    }

    static let bubbleBorderWidth: CGFloat = 1.5
    static let bubbleBorderColor = UIColor(rgbHex: 0xdedede)
    static var bubbleBackgroundColor: UIColor { Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white }
    private static let subscriptionBannerAvatarSize: UInt = 88

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Fetch available subscriptions
        firstly {
            SubscriptionManager.getSubscriptions()
        }.done(on: .main) { (fetchedSubscriptions: [SubscriptionLevel]) in
            self.subscriptions = fetchedSubscriptions
            Logger.debug("successfully fetched subscriptions")

            let badgeUpdatePromises = fetchedSubscriptions.map { return self.profileManager.badgeStore.populateAssetsOnBadge($0.badge) }
            firstly {
                return Promise.when(fulfilled: badgeUpdatePromises)
            }.done(on: .main) {
                self.updateTableContents()
            }.catch { error in
                owsFailDebug("Failed to fetch assets for badge \(error)")
            }

        }.catch(on: .main) { error in
            owsFailDebug("Failed to fetch subscriptions \(error)")
        }

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer {
            self.contents = contents
        }

        let section = OWSTableSection()
        section.hasBackground = false
        contents.addSection(section)

        section.customHeaderView = {
            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.layoutMargins = UIEdgeInsets(top: 0, left: 19, bottom: 0, right: 19)
            stackView.isLayoutMarginsRelativeArrangement = true

            stackView.addArrangedSubview(avatarView)
            stackView.setCustomSpacing(16, after: avatarView)

            // Title text
            let titleLabel = UILabel()
            titleLabel.textAlignment = .center
            titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
            titleLabel.text = NSLocalizedString(
                "SUSTAINER_VIEW_TITLE",
                comment: "Title for the signal sustainer view"
            )
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(20, after: titleLabel)

            // Body text
            let textView = LinkingTextView()
            let bodyFormat = NSLocalizedString("SUSTAINER_VIEW_WHY_DONATE_BODY", comment: "The body text for the signal sustainer view, embeds {{link to donation read more}}")
            let readMore = NSLocalizedString("SUSTAINER_VIEW_READ_MORE", comment: "Read More tappable text in sustainer view body")
            let body = String(format: bodyFormat, readMore)

            let bodyAttributedString = NSMutableAttributedString(string: body)
            bodyAttributedString.addAttributesToEntireString([.font: UIFont.ows_dynamicTypeBody, .foregroundColor: Theme.primaryTextColor])
            bodyAttributedString.addAttributes([.link: NSURL()], range: NSRange(location: body.utf16.count - readMore.utf16.count, length: readMore.utf16.count))

            textView.attributedText = bodyAttributedString
            textView.linkTextAttributes = [
                .foregroundColor: Theme.accentBlueColor,
                .underlineColor: UIColor.clear,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            textView.textAlignment = .center
            stackView.addArrangedSubview(textView)

            return stackView
        }()

        // TODO EB Disable currency swapping if a subscription already exists (pull currency code from storage service)
        if true {// DonationUtilities.isApplePayAvailable {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newCell()

                    let stackView = UIStackView()
                    stackView.axis = .horizontal
                    stackView.alignment = .center
                    stackView.spacing = 8
                    stackView.layoutMargins = UIEdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
                    stackView.isLayoutMarginsRelativeArrangement = true
                    cell.contentView.addSubview(stackView)
                    stackView.autoPinEdgesToSuperviewEdges()

                    let label = UILabel()
                    label.font = .ows_dynamicTypeBodyClamped
                    label.textColor = Theme.primaryTextColor
                    label.text = NSLocalizedString(
                        "SUSTAINER_VIEW_CURRENCY",
                        comment: "Set currency label in sustainer view"
                    )
                    stackView.addArrangedSubview(label)

                    let picker = OWSButton { [weak self] in
                        guard let self = self else { return }
                        let vc = CurrencyPickerViewController(
                            dataSource: StripeCurrencyPickerDataSource(currentCurrencyCode: self.currencyCode)
                        ) { [weak self] currencyCode in
                            self?.currencyCode = currencyCode
                        }
                        self.navigationController?.pushViewController(vc, animated: true)
                    }

                    picker.setAttributedTitle(NSAttributedString.composed(of: [
                        self.currencyCode,
                        Special.noBreakSpace,
                        NSAttributedString.with(
                            image: #imageLiteral(resourceName: "chevron-down-18").withRenderingMode(.alwaysTemplate),
                            font: .ows_regularFont(withSize: 17)
                        ).styled(
                            with: .color(Self.bubbleBorderColor)
                        )
                    ]).styled(
                        with: .font(.ows_regularFont(withSize: 17)),
                        .color(Theme.primaryTextColor)
                    ), for: .normal)

                    picker.setBackgroundImage(UIImage(color: Self.bubbleBackgroundColor), for: .normal)
                    picker.setBackgroundImage(UIImage(color: Self.bubbleBackgroundColor.withAlphaComponent(0.8)), for: .highlighted)

                    let pillView = PillView()
                    pillView.layer.borderWidth = Self.bubbleBorderWidth
                    pillView.layer.borderColor = Self.bubbleBorderColor.cgColor
                    pillView.clipsToBounds = true
                    pillView.addSubview(picker)
                    picker.autoPinEdgesToSuperviewEdges()
                    picker.autoSetDimension(.width, toSize: 74, relation: .greaterThanOrEqual)

                    stackView.addArrangedSubview(pillView)
                    pillView.autoSetDimension(.height, toSize: 36, relation: .greaterThanOrEqual)

                    let leadingSpacer = UIView.hStretchingSpacer()
                    let trailingSpacer = UIView.hStretchingSpacer()
                    stackView.insertArrangedSubview(leadingSpacer, at: 0)
                    stackView.addArrangedSubview(trailingSpacer)
                    leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)

                    return cell
                },
                actionBlock: {}
            ))

            // Subscription levels
            // TODO EB Can't load subscriptions UI
            // TODO EB Apple pay not available UI

            if let subscriptions = self.subscriptions {
                for (index, subscription) in subscriptions.enumerated() {
                    section.add(.init(
                        customCellBlock: { [weak self] in
                            guard let self = self else { return UITableViewCell() }
                            let cell = self.newSubscriptionCell()
                            cell.subscriptionID = subscription.level

                            let stackView = UIStackView()
                            stackView.axis = .horizontal
                            stackView.alignment = .center
                            stackView.layoutMargins = UIEdgeInsets(top: index == 0 ? 16 : 28, leading: 34, bottom: 16, trailing: 34)
                            stackView.isLayoutMarginsRelativeArrangement = true
                            stackView.spacing = 10
                            cell.contentView.addSubview(stackView)
                            stackView.autoPinEdgesToSuperviewEdges()

                            let isSelected = self.selectedSubscription?.level == subscription.level

                            // Background view
                            let background = UIView()
                            background.backgroundColor = Theme.backgroundColor
                            background.layer.borderWidth = Self.bubbleBorderWidth
                            background.layer.borderColor = isSelected ? Theme.accentBlueColor.cgColor : Self.bubbleBorderColor.cgColor
                            background.layer.cornerRadius = 12
                            stackView.addSubview(background)
                            background.autoPinEdgesToSuperviewEdges(withInsets: UIEdgeInsets(top: index == 0 ? 0 : 12, leading: 24, bottom: 0, trailing: 24))

                            let badge = subscription.badge
                            let imageView = UIImageView()
                            imageView.setContentHuggingHigh()
                            if let badgeImage = badge.assets?.universal160 {
                                imageView.image = badgeImage
                            }
                            stackView.addArrangedSubview(imageView)
                            imageView.autoSetDimensions(to: CGSize(square: 64))

                            let textStackView = UIStackView()
                            textStackView.axis = .vertical
                            textStackView.alignment = .leading
                            textStackView.spacing = 4

                            let localizedBadgeName = subscription.name
                            let titleLabel = UILabel()
                            titleLabel.text = localizedBadgeName
                            titleLabel.font = .ows_dynamicTypeBody.ows_semibold
                            titleLabel.numberOfLines = 0

                            let descriptionLabel = UILabel()
                            let descriptionFormat = NSLocalizedString("SUSTAINER_VIEW_BADGE_DESCRIPTION", comment: "Description text for sustainer view badges, embeds {{localized badge name}}")
                            descriptionLabel.text = String(format: descriptionFormat, localizedBadgeName)
                            descriptionLabel.font = .ows_dynamicTypeBody2
                            descriptionLabel.numberOfLines = 0

                            let pricingLabel = UILabel()
                            if let price = subscription.currency[self.currencyCode] {
                                let pricingFormat = NSLocalizedString("SUSTAINER_VIEW_PRICING", comment: "Pricing text for sustainer view badges, embeds {{price}}")
                                let currencyString = DonationUtilities.formatCurrency(price, currencyCode: self.currencyCode)
                                pricingLabel.text = String(format: pricingFormat, currencyString)
                                pricingLabel.font = .ows_dynamicTypeBody2
                                pricingLabel.numberOfLines = 0
                            }

                            textStackView.addArrangedSubviews([titleLabel, descriptionLabel, pricingLabel])
                            stackView.addArrangedSubview(textStackView)

                            return cell
                        },
                        actionBlock: {
                            self.selectedSubscription = subscription
                            self.updateTableContents()
                        }
                    ))
                }
            } else {
                // TODO EB Loading subscription UI / not available
                section.add(.init(
                    customCellBlock: { [weak self] in
                        guard let self = self else { return UITableViewCell() }
                        let cell = self.newCell()
                        let stackView = UIStackView()
                        stackView.axis = .vertical
                        stackView.alignment = .center
                        cell.contentView.addSubview(stackView)
                        stackView.autoPinEdgesToSuperviewEdges()

                        let activitySpinner: UIActivityIndicatorView
                        if #available(iOS 13, *) {
                            activitySpinner = UIActivityIndicatorView(style: .medium)
                        } else {
                            activitySpinner = UIActivityIndicatorView(style: .gray)
                        }

                        activitySpinner.startAnimating()

                        stackView.addArrangedSubview(activitySpinner)

                        return cell
                    },
                    actionBlock: {}
                ))
            }

            // Footer

            bottomFooterStackView.axis = .vertical
            bottomFooterStackView.alignment = .center
            bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor
            bottomFooterStackView.layoutMargins = UIEdgeInsets(top: 10, leading: 23, bottom: 10, trailing: 23)
            bottomFooterStackView.spacing = 16
            bottomFooterStackView.isLayoutMarginsRelativeArrangement = true
            bottomFooterStackView.removeAllSubviews()

            // Apple pay button
            let buttonType: PKPaymentButtonType
            if #available(iOS 14, *) {
                buttonType = .contribute
            } else {
                buttonType = .donate
            }

            let applePayContributeButton = PKPaymentButton(
                paymentButtonType: buttonType,
                paymentButtonStyle: Theme.isDarkThemeEnabled ? .white : .black
            )

            if #available(iOS 12, *) { applePayContributeButton.cornerRadius = 12 }
            applePayContributeButton.addTarget(self, action: #selector(self.requestApplePayDonation), for: .touchUpInside)

            bottomFooterStackView.addArrangedSubview(applePayContributeButton)
            applePayContributeButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
            applePayContributeButton.autoPinWidthToSuperview(withMargin: 23)

            // Other ways to donate

            let donateButton = OWSFlatButton()
            donateButton.setTitleColor(Theme.accentBlueColor)
            donateButton.setAttributedTitle(NSAttributedString.composed(of: [
                NSLocalizedString(
                    "DONATION_VIEW_OTHER_WAYS",
                    comment: "Text explaining there are other ways to donate on the donation view."
                ),
                Special.noBreakSpace,
                NSAttributedString.with(
                    image: #imageLiteral(resourceName: "open-20").withRenderingMode(.alwaysTemplate),
                    font: .ows_dynamicTypeBodyClamped
                )
            ]).styled(
                with: .font(.ows_dynamicTypeBodyClamped),
                .color(Theme.accentBlueColor)
            ))
            donateButton.setPressedBlock { [weak self] in
                self?.openDonateWebsite()
            }

            bottomFooterStackView.addArrangedSubview(donateButton)
        }

    }

    private func openDonateWebsite() {
        UIApplication.shared.open(URL(string: "https://signal.org/donate")!, options: [:], completionHandler: nil)
    }

    private func newCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        return cell
    }

    private func newSubscriptionCell() -> SubscriptionLevelCell {
        let cell = SubscriptionLevelCell()
        OWSTableItem.configureCell(cell)
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        cell.selectionStyle = .none
        return cell
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateTableContents()
    }

}

extension SubscriptionViewController: PKPaymentAuthorizationControllerDelegate {

    @objc
    fileprivate func requestApplePayDonation() {

        guard let subscription = selectedSubscription else {
            owsFailDebug("No selected subscription, can't invoke Apple Pay donation")
            return
        }

        guard let subscriptionAmount = subscription.currency[currencyCode] else {
            owsFailDebug("Failed to get amount for current currency code")
            return
        }

        //TODO EB DRY this up
        guard !Stripe.isAmountTooSmall(subscriptionAmount, in: currencyCode) else {
            owsFailDebug("Subscription amount is too small per Stripe API")
            return
        }

        guard !Stripe.isAmountTooLarge(subscriptionAmount, in: currencyCode) else {
            owsFailDebug("Subscription amount is too large per Stripe API")
            return
        }

        let request = DonationUtilities.newPaymentRequest(for: subscriptionAmount, currencyCode: currencyCode)


        let paymentController = PKPaymentAuthorizationController(paymentRequest: request)
        paymentController.delegate = self
        paymentController.present { presented in
            if !presented { owsFailDebug("Failed to present payment controller") }
        }
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {

        guard let selectedSubscription = self.selectedSubscription else {
            owsFailDebug("No currently selected subscription")
            let authResult = PKPaymentAuthorizationResult(status: .failure, errors: nil)
            completion(authResult)
            return
        }
        
        // TODO EB cancel chain if Apple Pay times out
        firstly {
            return try SubscriptionManager.setupNewSubscription(subscription: selectedSubscription, payment: payment, currencyCode: self.currencyCode)
        }.done(on: .main) {
            let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
            completion(authResult)
            self.fetchAndRedeemReceipts(newSubscriptionLevel: selectedSubscription)
        }.catch { error in
            let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
            completion(authResult)
            owsFailDebug("Error setting up subscription, \(error)")
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
    
    func fetchAndRedeemReceipts(newSubscriptionLevel: SubscriptionLevel) {
        var subscriberID: Data?
        SDSDatabaseStorage.shared.read { transaction in
            subscriberID = SubscriptionManager.getSubscriberID(transaction: transaction)
            
            guard let subscriberID = subscriberID else {
                owsFailDebug("Did not fetch subscriberID")
                return
            }
            
            firstly {
                return try SubscriptionManager.requestAndRedeemRecieptsIfNecessary(for: subscriberID, subscriptionLevel: newSubscriptionLevel)
            }.done(on: .main) { credential in
                Logger.debug("Got presentation \(credential)")
            }.catch { error in
                owsFailDebug("Failed to redeem with error \(error)")
            }
        }
    }

}

private class SubscriptionLevelCell: UITableViewCell {
    public var subscriptionID: UInt = 0
}
