//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import BonMot
import SignalServiceKit
import SignalMessaging
import Lottie
import SignalUI

class BoostSheetView: InteractiveSheetViewController {
    let boostVC = BoostViewController()
    override var interactiveScrollViews: [UIScrollView] { [boostVC.tableView] }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        contentView.addSubview(boostVC.view)
        boostVC.view.autoPinEdgesToSuperviewEdges()
        addChild(boostVC)

        minimizedHeight = 680
        allowsExpansion = false
    }

    override var sheetBackgroundColor: UIColor {
        return boostVC.tableBackgroundColor
    }
}

class BoostViewController: OWSTableViewController2 {
    private var currencyCode = Stripe.defaultCurrencyCode {
        didSet {
            guard oldValue != currencyCode else { return }
            customAmountTextField.setCurrencyCode(currencyCode)
            state = nil
            updateTableContents()
        }
    }
    private let customAmountTextField = OneTimeDonationCustomAmountTextField()
    private let headerAnimationView: AnimationView = {
        let animationView = AnimationView(name: "boost_badge")
        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .forceFinish
        animationView.contentMode = .scaleAspectFit
        animationView.autoSetDimensions(to: CGSize(square: 112))
        return animationView
    }()

    private var donationAmount: FiatMoney? {
        switch state {
        case .presetSelected(let amount):
            return amount
        case .customValueSelected:
            return customAmountTextField.amount
        default:
            return nil
        }
    }

    private var presets: [Currency.Code: DonationUtilities.Preset]? {
        didSet {
            customAmountTextField.setCurrencyCode(currencyCode)
        }
    }

    private var supportedCurrencyCodes: Set<Currency.Code> {
        guard let presets = presets else { return [] }
        return Set(presets.keys)
    }

    private var boostBadge: ProfileBadge?
    private var boostExpiration: UInt64? {
        profileManagerImpl.localUserProfile().profileBadgeInfo?.first { BoostBadgeIds.contains($0.badgeId) }?.expiration
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

    enum State: Equatable {
        case loading
        case presetSelected(amount: FiatMoney)
        case customValueSelected
        case donatedSuccessfully
    }
    private var state: State? = .loading {
        didSet {
            guard oldValue != state else { return }
            if oldValue == .customValueSelected { clearCustomTextField() }
            if state == .donatedSuccessfully || oldValue == .loading { updateTableContents() }
            updatePresetButtonSelection()
        }
    }

    func clearCustomTextField() {
        customAmountTextField.text = nil
        customAmountTextField.resignFirstResponder()
    }

    override func viewDidLoad() {
        shouldAvoidKeyboard = true

        super.viewDidLoad()

        firstly(on: .global()) {
            Promise.when(fulfilled: SubscriptionManager.getBoostBadge(), SubscriptionManager.getSuggestedBoostAmounts())
        }.then(on: .main) { [weak self] (boostBadge, presets) -> Promise<Void> in
            guard let self = self else { return Promise.value(()) }

            self.presets = presets
            self.boostBadge = boostBadge
            self.state = nil

            return self.profileManager.badgeStore.populateAssetsOnBadge(boostBadge)
        }.catch { error in
            owsFailDebug("Failed to fetch boost info \(error)")
        }

        customAmountTextField.placeholder = NSLocalizedString(
            "BOOST_VIEW_CUSTOM_AMOUNT_PLACEHOLDER",
            comment: "Default text for the custom amount field of the boost view."
        )
        customAmountTextField.delegate = self
        customAmountTextField.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "custom_amount_text_field")

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // If we're the root view, add a cancel button
        if navigationController?.viewControllers.first == self {
            navigationItem.leftBarButtonItem = .init(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(didTapDone)
            )
        }
    }

    @objc
    func didTapDone() {
        self.dismiss(animated: true)
    }

    func newCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        return cell
    }

    override var canBecomeFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // If we become the first responder, but the user was entering
        // a customValue, restore the first responder state to the text field.
        if result, case .customValueSelected = state {
            customAmountTextField.becomeFirstResponder()
        }
        return result
    }

    var presetButtons: [FiatMoney: UIView] = [:]
    func updatePresetButtonSelection() {
        for (amount, button) in presetButtons {
            if case .presetSelected(amount: amount) = self.state {
                button.layer.borderColor = Theme.accentBlueColor.cgColor
            } else {
                button.layer.borderColor = DonationViewsUtil.bubbleBorderColor.cgColor
            }
        }
    }

    func updateTableContents() {

        let contents = OWSTableContents()
        defer {
            self.contents = contents
            if case .customValueSelected = state { customAmountTextField.becomeFirstResponder() }
        }

        let section = OWSTableSection()
        section.hasBackground = false
        contents.addSection(section)

        section.customHeaderView = {
            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 28, right: 16)

            let animationProgress = headerAnimationView.currentProgress
            stackView.addArrangedSubview(headerAnimationView)
            if animationProgress < 1, state != .loading {
                headerAnimationView.play(fromProgress: animationProgress, toProgress: 1)
            }

            let titleLabel = UILabel()
            titleLabel.textAlignment = .center
            titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
            titleLabel.text = NSLocalizedString(
                "BOOST_VIEW_TITLE",
                comment: "Title for the donate to signal view"
            )
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(20, after: titleLabel)

            let bodyText: String
            if let expiration = self.boostExpiration, expiration > Date().ows_millisecondsSince1970 {
                let renewalFormat = NSLocalizedString(
                    "BOOST_VIEW_BODY_WITH_EXPIRATION_FORMAT",
                    comment: "The body text for the donate to signal view, embeds {{Expiration}}"
                )
                let renewalDate = Date(millisecondsSince1970: expiration)
                bodyText = String(format: renewalFormat, self.dateFormatter.string(from: renewalDate))
            } else {
                bodyText = NSLocalizedString("BOOST_VIEW_BODY", comment: "The body text for the donate to signal view")
            }

            let bodyTextView = LinkingTextView()
            bodyTextView.attributedText = .composed(of: [
                bodyText,
                " ",
                CommonStrings.learnMore.styled(with: .link(SupportConstants.subscriptionFAQURL))
            ]).styled(with: .color(Theme.primaryTextColor), .font(.ows_dynamicTypeBody))

            bodyTextView.linkTextAttributes = [
                .foregroundColor: Theme.accentBlueColor,
                .underlineColor: UIColor.clear,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            bodyTextView.textAlignment = .center
            stackView.addArrangedSubview(bodyTextView)

            return stackView
        }()

        if state == .loading {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newCell()
                    let stackView = UIStackView()
                    stackView.axis = .vertical
                    stackView.alignment = .center
                    stackView.layoutMargins = UIEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
                    stackView.isLayoutMarginsRelativeArrangement = true
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

        addApplePayItemsIfAvailable(to: section)

        // If ApplePay isn't available, show just a link to the website
        if !DonationUtilities.isApplePayAvailable {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newCell()

                    let donateButton = OWSFlatButton()
                    donateButton.setBackgroundColors(upColor: Theme.accentBlueColor)
                    donateButton.setTitleColor(.ows_white)
                    donateButton.setAttributedTitle(NSAttributedString.composed(of: [
                        NSLocalizedString(
                            "SETTINGS_DONATE",
                            comment: "Title for the 'donate to signal' link in settings."
                        ),
                        Special.noBreakSpace,
                        NSAttributedString.with(
                            image: #imageLiteral(resourceName: "open-20").withRenderingMode(.alwaysTemplate),
                            font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold
                        )
                    ]).styled(
                        with: .font(UIFont.ows_dynamicTypeBodyClamped.ows_semibold),
                        .color(.ows_white)
                    ))
                    donateButton.layer.cornerRadius = 24
                    donateButton.clipsToBounds = true
                    donateButton.setPressedBlock {
                        DonationViewsUtil.openDonateWebsite()
                    }

                    cell.contentView.addSubview(donateButton)
                    donateButton.autoPinEdgesToSuperviewMargins()
                    donateButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)

                    return cell
                },
                actionBlock: {}
            ))
        }
    }

    private func openDonateWebsite() {
        UIApplication.shared.open(TSConstants.donateUrl, options: [:], completionHandler: nil)
    }
}

// MARK: - ApplePay

extension BoostViewController: PKPaymentAuthorizationControllerDelegate {

    func addApplePayItemsIfAvailable(to section: OWSTableSection) {
        guard DonationUtilities.isApplePayAvailable, state != .loading else { return }

        // Currency Picker

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let currencyPickerButton = DonationCurrencyPickerButton(currentCurrencyCode: self.currencyCode) { [weak self] in
                    guard let self = self else { return }
                    let vc = CurrencyPickerViewController(
                        dataSource: StripeCurrencyPickerDataSource(
                            currentCurrencyCode: self.currencyCode,
                            supportedCurrencyCodes: self.supportedCurrencyCodes
                        )
                    ) { [weak self] currencyCode in
                        self?.currencyCode = currencyCode
                    }
                    self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
                cell.contentView.addSubview(currencyPickerButton)
                currencyPickerButton.autoPinEdgesToSuperviewEdges()

                return cell
            },
            actionBlock: {}
        ))

        // Preset donation options

        if let preset = presets?[currencyCode] {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newCell()

                    let vStack = UIStackView()
                    vStack.axis = .vertical
                    vStack.distribution = .fillEqually
                    vStack.spacing = 16
                    cell.contentView.addSubview(vStack)
                    vStack.autoPinEdgesToSuperviewMargins()

                    self.presetButtons.removeAll()

                    for (row, amounts) in preset.amounts.chunked(by: 3).enumerated() {
                        let hStack = UIStackView()
                        hStack.axis = .horizontal
                        hStack.distribution = .fillEqually
                        hStack.spacing = UIDevice.current.isIPhone5OrShorter ? 8 : 14

                        vStack.addArrangedSubview(hStack)

                        for (index, amount) in amounts.enumerated() {
                            let button = OWSFlatButton()
                            hStack.addArrangedSubview(button)
                            button.setBackgroundColors(
                                upColor: DonationViewsUtil.bubbleBackgroundColor,
                                downColor: DonationViewsUtil.bubbleBackgroundColor.withAlphaComponent(0.8)
                            )
                            button.layer.cornerRadius = 24
                            button.clipsToBounds = true
                            button.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth

                            func playEmojiAnimation(parentView: UIView?) {
                                guard let parentView = parentView else { return }
                                let animationNames = [
                                    "boost_smile",
                                    "boost_clap",
                                    "boost_heart_eyes",
                                    "boost_fire",
                                    "boost_shock",
                                    "boost_rockets"
                                ]

                                guard let selectedAnimation = animationNames[safe: (row * 3) + index] else {
                                    return owsFailDebug("Missing animation for preset")
                                }

                                let animationView = AnimationView(name: selectedAnimation)
                                animationView.loopMode = .playOnce
                                animationView.contentMode = .scaleAspectFit
                                animationView.backgroundBehavior = .forceFinish
                                parentView.addSubview(animationView)
                                animationView.autoPinEdge(.bottom, to: .top, of: button, withOffset: 20)
                                animationView.autoPinEdge(.leading, to: .leading, of: button)
                                animationView.autoMatch(.width, to: .width, of: button)
                                animationView.play { _ in
                                    animationView.removeFromSuperview()
                                }
                            }

                            button.setPressedBlock { [weak self] in
                                self?.state = .presetSelected(amount: amount)
                                playEmojiAnimation(parentView: self?.view)
                            }

                            button.setTitle(
                                title: DonationUtilities.format(money: amount),
                                font: .ows_regularFont(withSize: UIDevice.current.isIPhone5OrShorter ? 18 : 20),
                                titleColor: Theme.primaryTextColor
                            )

                            button.autoSetDimension(.height, toSize: 48)

                            self.presetButtons[amount] = button
                        }
                    }

                    self.updatePresetButtonSelection()

                    return cell
                },
                actionBlock: {}
            ))
        }

        // Custom donation option

        let applePayButtonIndex = IndexPath(row: section.items.count + 1, section: 0)
        let customAmountTextField = self.customAmountTextField
        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                customAmountTextField.backgroundColor = DonationViewsUtil.bubbleBackgroundColor
                customAmountTextField.layer.cornerRadius = 24
                customAmountTextField.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth
                customAmountTextField.layer.borderColor = DonationViewsUtil.bubbleBorderColor.cgColor

                customAmountTextField.font = .ows_dynamicTypeBodyClamped
                customAmountTextField.textColor = Theme.primaryTextColor

                cell.contentView.addSubview(customAmountTextField)
                customAmountTextField.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                customAmountTextField.becomeFirstResponder()
                self?.tableView.scrollToRow(at: applePayButtonIndex, at: .bottom, animated: true)
            }
        ))

        // Donate with Apple Pay button

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let applePayButton = ApplePayButton { [weak self] in
                    self?.requestApplePayDonation()
                }
                cell.contentView.addSubview(applePayButton)
                applePayButton.autoPinEdgesToSuperviewMargins()
                applePayButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)

                return cell
            },
            actionBlock: {}
        ))

        // Other options button

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let donateButton = OWSFlatButton()
                donateButton.setTitleColor(Theme.accentBlueColor)
                donateButton.setAttributedTitle(NSAttributedString.composed(of: [
                    NSLocalizedString(
                        "BOOST_VIEW_OTHER_WAYS",
                        comment: "Text explaining there are other ways to donate on the boost view."
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

                cell.contentView.addSubview(donateButton)
                donateButton.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {}
        ))
    }

    @objc
    func requestApplePayDonation() {
        guard let donationAmount = donationAmount else {
            presentToast(text: NSLocalizedString(
                "BOOST_VIEW_SELECT_AN_AMOUNT",
                comment: "Error text notifying the user they must select an amount on the donate to signal view"
            ), extraVInset: view.height - tableView.frame.maxY)
            return
        }

        guard !Stripe.isAmountTooSmall(donationAmount) else {
            presentToast(text: NSLocalizedString(
                "BOOST_VIEW_SELECT_A_LARGER_AMOUNT",
                comment: "Error text notifying the user they must select a large amount on the donate to signal view"
            ), extraVInset: view.height - tableView.frame.maxY)
            return
        }

        guard !Stripe.isAmountTooLarge(donationAmount) else {
            presentToast(text: NSLocalizedString(
                "BOOST_VIEW_SELECT_A_SMALLER_AMOUNT",
                comment: "Error text notifying the user they must select a smaller amount on the donate to signal view"
            ), extraVInset: view.height - tableView.frame.maxY)
            return
        }

        let request = DonationUtilities.newPaymentRequest(
            for: donationAmount,
            isRecurring: false
        )

        SubscriptionManager.terminateTransactionIfPossible = false
        let paymentController = PKPaymentAuthorizationController(paymentRequest: request)
        paymentController.delegate = self
        paymentController.present { presented in
            if !presented { owsFailDebug("Failed to present payment controller") }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        SubscriptionManager.terminateTransactionIfPossible = true
        controller.dismiss()
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard let donationAmount = donationAmount else {
            completion(.init(status: .failure, errors: [OWSAssertionError("Missing donation amount")]))
            return
        }

        enum BoostError: Error { case timeout, assertion }

        firstly {
            Stripe.boost(amount: donationAmount,
                         level: .boostBadge,
                         for: payment)
        }.done { intentId in
            completion(.init(status: .success, errors: nil))
            SubscriptionManager.terminateTransactionIfPossible = false

            do {
                try SubscriptionManager.createAndRedeemBoostReceipt(
                    for: intentId,
                    amount: donationAmount
                )
            } catch {

            }

            ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
                Promise.race(
                    NotificationCenter.default.observe(
                        once: SubscriptionManager.SubscriptionJobQueueDidFinishJobNotification,
                        object: nil
                    ),
                    NotificationCenter.default.observe(
                        once: SubscriptionManager.SubscriptionJobQueueDidFailJobNotification,
                        object: nil
                    )
                ).timeout(seconds: 30) {
                    return BoostError.timeout
                }.done { notification in
                    modal.dismiss {}

                    if notification.name == SubscriptionManager.SubscriptionJobQueueDidFailJobNotification {
                        throw BoostError.assertion
                    }

                    self.state = .donatedSuccessfully

                    guard let boostBadge = self.boostBadge else {
                        return owsFailDebug("Missing boost badge!")
                    }

                    // We're presented in a sheet context, so we must dismiss the sheet and then present
                    // the thank you sheet.
                    if self.parent is BoostSheetView {
                        let presentingVC = self.parent?.presentingViewController
                        self.parent?.dismiss(animated: true) {
                            presentingVC?.present(BadgeThanksSheet(badge: boostBadge, type: .boost), animated: true)
                        }
                    } else {
                        self.present(BadgeThanksSheet(badge: boostBadge, type: .boost), animated: true)
                    }
                }.catch { error in
                    modal.dismiss {}
                    guard let error = error as? BoostError else {
                        return owsFailDebug("Unexpected error \(error)")
                    }

                    switch error {
                    case .timeout:
                        self.presentStillProcessingSheet()
                    case .assertion:
                        self.presentBadgeCantBeAddedSheet()
                    }
                }
            }
        }.catch { error in
            SubscriptionManager.terminateTransactionIfPossible = false
            owsFailDebugUnlessNetworkFailure(error)
            completion(.init(status: .failure, errors: [error]))
        }
    }

    func presentStillProcessingSheet() {
        let title = NSLocalizedString("SUSTAINER_STILL_PROCESSING_BADGE_TITLE", comment: "Action sheet title for Still Processing Badge sheet")
        let message = NSLocalizedString("SUSTAINER_VIEW_STILL_PROCESSING_BADGE_MESSAGE", comment: "Action sheet message for Still Processing Badge sheet")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(OWSActionSheets.okayAction)
        self.navigationController?.topViewController?.presentActionSheet(actionSheet)
    }

    func presentBadgeCantBeAddedSheet() {
        let title = NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_TITLE", comment: "Action sheet title for Couldn't Add Badge sheet")
        let message = NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_MESSAGE", comment: "Action sheet message for Couldn't Add Badge sheet")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("CONTACT_SUPPORT", comment: "Button text to initiate an email to signal support staff"),
            style: .default,
            handler: { [weak self] _ in
                let localizedSheetTitle = NSLocalizedString("EMAIL_SIGNAL_TITLE",
                                                            comment: "Title for the fallback support sheet if user cannot send email")
                let localizedSheetMessage = NSLocalizedString("EMAIL_SIGNAL_MESSAGE",
                                                              comment: "Description for the fallback support sheet if user cannot send email")
                guard ComposeSupportEmailOperation.canSendEmails else {
                    let fallbackSheet = ActionSheetController(title: localizedSheetTitle,
                                                              message: localizedSheetMessage)
                    let buttonTitle = NSLocalizedString("BUTTON_OKAY", comment: "Label for the 'okay' button.")
                    fallbackSheet.addAction(ActionSheetAction(title: buttonTitle, style: .default))
                    self?.presentActionSheet(fallbackSheet)
                    return
                }
                let supportVC = ContactSupportViewController()
                let navVC = OWSNavigationController(rootViewController: supportVC)
                self?.presentFormSheet(navVC, animated: true)
            }
        ))

        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW", comment: "Sustainer view Not Now Action sheet button"),
            style: .cancel,
            handler: nil
        ))
        self.navigationController?.topViewController?.presentActionSheet(actionSheet)
    }
}

extension BoostViewController: OneTimeDonationCustomAmountTextFieldDelegate {
    func oneTimeDonationCustomAmountTextFieldStateDidChange(_ textField: OneTimeDonationCustomAmountTextField) {
        state = .customValueSelected
    }
}
