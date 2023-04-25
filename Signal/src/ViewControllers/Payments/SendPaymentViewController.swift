//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalMessaging
import SignalUI

public protocol SendPaymentViewDelegate: AnyObject {
    func didSendPayment(success: Bool)
}

// MARK: -

public enum SendPaymentMode: UInt {
    case fromConversationView
    case fromPaymentSettings
    case fromTransferOutFlow

    var isModalRootView: Bool {
        switch self {
        case .fromConversationView:
            return true
        case .fromPaymentSettings,
             .fromTransferOutFlow:
            return false
        }
    }
}

// MARK: -

public class SendPaymentViewController: OWSViewController {

    private let mode: SendPaymentMode

    fileprivate typealias PaymentInfo = SendPaymentInfo

    public weak var delegate: SendPaymentViewDelegate?

    private let recipient: SendPaymentRecipient
    private let paymentRequestModel: TSPaymentRequestModel?
    private let isOutgoingTransfer: Bool

    private let rootStack = UIStackView()

    private let bigAmountLabel = UILabel()
    private let smallAmountLabel = UILabel()
    private let currencyConversionInfoView = UIImageView()

    private let balanceLabel = SendPaymentHelper.buildBottomLabel()

    // MARK: - Amount

    private let amounts = Amounts()
    private var amount: Amount { amounts.currentAmount }
    private var otherCurrencyAmount: Amount? { amounts.otherCurrencyAmount }

    // MARK: -

    private var memoMessage: String?

    private var hasMemoMessage: Bool {
        memoMessage?.strippedOrNil != nil
    }

    private var helper: SendPaymentHelper?

    private var currentCurrencyConversion: CurrencyConversionInfo? { helper?.currentCurrencyConversion }

    private var isIdentifiedPayment: Bool {
        recipient.isIdentifiedPayment
    }

    public var isUsingPresentedStyle: Bool {
        return presentingViewController != nil
    }

    open var tableBackgroundColor: UIColor {
        AssertIsOnMainThread()

        return Self.tableBackgroundColor(isUsingPresentedStyle: isUsingPresentedStyle)
    }

    public static func tableBackgroundColor(isUsingPresentedStyle: Bool) -> UIColor {
        AssertIsOnMainThread()

        if isUsingPresentedStyle {
            return Theme.tableView2PresentedBackgroundColor
        } else {
            return Theme.tableView2BackgroundColor
        }
    }

    public var cellBackgroundColor: UIColor {
        Self.cellBackgroundColor(isUsingPresentedStyle: isUsingPresentedStyle)
    }

    public static func cellBackgroundColor(isUsingPresentedStyle: Bool) -> UIColor {
        if isUsingPresentedStyle {
            return Theme.tableCell2PresentedBackgroundColor
        } else {
            return Theme.tableCell2BackgroundColor
        }
    }

    public var cellSelectedBackgroundColor: UIColor {
        if isUsingPresentedStyle {
            return Theme.tableCell2PresentedSelectedBackgroundColor
        } else {
            return Theme.tableCell2SelectedBackgroundColor
        }
    }

    public required init(recipient: SendPaymentRecipient,
                         paymentRequestModel: TSPaymentRequestModel?,
                         initialPaymentAmount: TSPaymentAmount?,
                         isOutgoingTransfer: Bool,
                         mode: SendPaymentMode) {
        self.recipient = recipient
        self.mode = mode
        self.isOutgoingTransfer = isOutgoingTransfer

        if Self.wasLastPaymentInFiat,
           let defaultFiatAmount = Amounts.defaultFiatAmount {
            amounts.set(currentAmount: defaultFiatAmount, otherCurrencyAmount: nil)
        } else {
            amounts.set(currentAmount: Amounts.defaultMCAmount, otherCurrencyAmount: nil)
        }

        if !FeatureFlags.paymentsRequests {
            owsAssertDebug(paymentRequestModel == nil)
            self.paymentRequestModel = nil
        } else {
            self.paymentRequestModel = paymentRequestModel

            if let paymentRequestModel = paymentRequestModel {
                owsAssertDebug(paymentRequestModel.paymentAmount.currency == .mobileCoin)

                if let requestAmountString = PaymentsFormat.formatAsDoubleString(picoMob: paymentRequestModel.paymentAmount.picoMob) {
                    let inputString = InputString.parseString(requestAmountString, isFiat: false)
                    amounts.set(currentAmount: .mobileCoin(inputString: inputString,
                                                           exactAmount: nil),
                                otherCurrencyAmount: nil)
                } else {
                    owsFailDebug("Could not apply request amount.")
                }
            }
        }

        if let initialPaymentAmount = initialPaymentAmount {
            owsAssertDebug(initialPaymentAmount.currency == .mobileCoin)

            if let amountString = PaymentsFormat.formatAsDoubleString(picoMob: initialPaymentAmount.picoMob) {
                let inputString = InputString.parseString(amountString, isFiat: false)
                amounts.set(currentAmount: .mobileCoin(inputString: inputString,
                                                       exactAmount: initialPaymentAmount),
                            otherCurrencyAmount: nil)
            } else {
                owsFailDebug("Could not apply initial amount.")
            }
        }

        super.init()

        helper = SendPaymentHelper(delegate: self)
        amounts.delegate = self
    }

    private enum PresentationMode {
        case fromConversationView(fromViewController: UIViewController)
        case inNavigationController(navigationController: UINavigationController)
    }

    private static func present(fromViewController: UIViewController,
                                presentationMode: PresentationMode,
                                delegate: SendPaymentViewDelegate,
                                recipientAddress: SignalServiceAddress,
                                paymentRequestModel: TSPaymentRequestModel?,
                                initialPaymentAmount: TSPaymentAmount? = nil,
                                isOutgoingTransfer: Bool,
                                mode: SendPaymentMode) {

        guard paymentsHelper.arePaymentsEnabled else {
            Logger.info("Payments not enabled.")
            showEnablePaymentsActionSheet()
            return
        }
        guard tsAccountManager.isRegisteredAndReady else {
            Logger.info("Local user is not registered and ready.")
            showNotRegisteredActionSheet()
            return
        }

        var hasProfileKeyForRecipient = false
        var hasSentMessagesToRecipient = false
        databaseStorage.read { transaction in
            guard nil == Self.profileManager.profileKeyData(for: recipientAddress,
                                                            transaction: transaction) else {
                hasProfileKeyForRecipient = true
                return
            }
            guard let thread = TSContactThread.getWithContactAddress(recipientAddress,
                                                                     transaction: transaction) else {
                hasSentMessagesToRecipient = false
                return
            }
            let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
            hasSentMessagesToRecipient = 0 < interactionFinder.outgoingMessageCount(transaction: transaction)
        }
        guard hasProfileKeyForRecipient else {
            let title = OWSLocalizedString("PAYMENTS_RECIPIENT_MISSING_PROFILE_KEY_TITLE",
                                          comment: "Title for error alert indicating that a given user cannot receive payments because of a pending message request.")
            let message = (hasSentMessagesToRecipient
                            ? OWSLocalizedString("PAYMENTS_RECIPIENT_MISSING_PROFILE_KEY_MESSAGE_W_MESSAGES",
                            comment: "Message for error alert indicating that a given user cannot receive payments because of a pending message request for a recipient that they have sent messages to.")
                            : OWSLocalizedString("PAYMENTS_RECIPIENT_MISSING_PROFILE_KEY_MESSAGE_WO_MESSAGES",
                            comment: "Message for error alert indicating that a given user cannot receive payments because of a pending message request for a recipient that they have not sent message to."))

            let actionSheet = ActionSheetController(title: title, message: message)

            if !hasSentMessagesToRecipient {
                switch mode {
                case .fromConversationView:
                    break
                case .fromTransferOutFlow:
                    owsFailDebug("not a valid mode for this method")
                case .fromPaymentSettings:
                    actionSheet.addAction(ActionSheetAction(
                        title: CommonStrings.sendMessage,
                        accessibilityIdentifier: "payments.settings.send_message",
                        style: .default,
                        handler: { [weak fromViewController] _ in
                            guard let fromViewController = fromViewController else { return }
                            // We want to get back to the app's main interface. This is shown inside
                            // Payment Settings, which is presented, and is part of the Send Payment
                            // flow, which is *also* presented.
                            let rootViewController = fromViewController.presentingViewController?.presentingViewController
                            owsAssertDebug(rootViewController != nil)
                            rootViewController?.dismiss(animated: true) {
                                SignalApp.shared().presentConversation(for: recipientAddress, action: .compose, animated: true)
                            }
                        }
                    ))
                }
            }

            actionSheet.addAction(OWSActionSheets.okayAction)

            fromViewController.presentActionSheet(actionSheet)

            return
        }

        let recipientHasPaymentsEnabled = databaseStorage.read { transaction in
            Self.paymentsHelper.arePaymentsEnabled(for: recipientAddress, transaction: transaction)
        }
        if recipientHasPaymentsEnabled {
            presentAfterRecipientCheck(presentationMode: presentationMode,
                                       delegate: delegate,
                                       recipientAddress: recipientAddress,
                                       paymentRequestModel: paymentRequestModel,
                                       initialPaymentAmount: initialPaymentAmount,
                                       isOutgoingTransfer: isOutgoingTransfer,
                                       mode: mode)
        } else {
            // Check whether recipient can receive payments.
            ModalActivityIndicatorViewController.presentAsInvisible(fromViewController: fromViewController) { modalActivityIndicator in
                firstly(on: DispatchQueue.global()) {
                    ProfileFetcherJob.fetchProfilePromise(address: recipientAddress, ignoreThrottling: true)
                }.done { (_) in
                    AssertIsOnMainThread()

                    modalActivityIndicator.dismiss {
                        Self.presentAfterRecipientCheck(presentationMode: presentationMode,
                                                        delegate: delegate,
                                                        recipientAddress: recipientAddress,
                                                        paymentRequestModel: paymentRequestModel,
                                                        initialPaymentAmount: initialPaymentAmount,
                                                        isOutgoingTransfer: isOutgoingTransfer,
                                                        mode: mode)
                    }
                }.catch { error in
                    AssertIsOnMainThread()
                    owsFailDebug("Error: \(error)")

                    modalActivityIndicator.dismiss {
                        AssertIsOnMainThread()

                        Self.showRecipientNotEnabledAlert()
                    }
                }
            }
        }
    }

    private static func presentAfterRecipientCheck(presentationMode: PresentationMode,
                                                   delegate: SendPaymentViewDelegate,
                                                   recipientAddress: SignalServiceAddress,
                                                   paymentRequestModel: TSPaymentRequestModel?,
                                                   initialPaymentAmount: TSPaymentAmount? = nil,
                                                   isOutgoingTransfer: Bool,
                                                   mode: SendPaymentMode) {

        let recipientHasPaymentsEnabled = databaseStorage.read { transaction in
            Self.paymentsHelper.arePaymentsEnabled(for: recipientAddress, transaction: transaction)
        }
        guard recipientHasPaymentsEnabled else {
            showRecipientNotEnabledAlert()
            return
        }

        let recipient: SendPaymentRecipientImpl = .address(address: recipientAddress)
        let view = SendPaymentViewController(recipient: recipient,
                                             paymentRequestModel: paymentRequestModel,
                                             initialPaymentAmount: initialPaymentAmount,
                                             isOutgoingTransfer: isOutgoingTransfer,
                                             mode: mode)
        view.delegate = delegate
        switch presentationMode {
        case .fromConversationView(let fromViewController):
            let navigationController = OWSNavigationController(rootViewController: view)
            fromViewController.presentFormSheet(navigationController, animated: true)
        case .inNavigationController(let navigationController):
            navigationController.pushViewController(view, animated: true)
        }
    }

    private static func showRecipientNotEnabledAlert() {
        OWSActionSheets.showActionSheet(title: OWSLocalizedString("PAYMENTS_RECIPIENT_PAYMENTS_NOT_ENABLED_TITLE",
                                                                 comment: "Title for error alert indicating that a given user cannot receive payments because they have not enabled payments."),
                                        message: OWSLocalizedString("PAYMENTS_RECIPIENT_PAYMENTS_NOT_ENABLED_MESSAGE",
                                                                   comment: "Message for error alert indicating that a given user cannot receive payments because they have not enabled payments."))
    }

    public static func presentFromConversationView(_ fromViewController: UIViewController,
                                                   delegate: SendPaymentViewDelegate,
                                                   recipientAddress: SignalServiceAddress,
                                                   paymentRequestModel: TSPaymentRequestModel?,
                                                   initialPaymentAmount: TSPaymentAmount? = nil,
                                                   isOutgoingTransfer: Bool) {
        present(fromViewController: fromViewController,
                presentationMode: .fromConversationView(fromViewController: fromViewController),
                delegate: delegate,
                recipientAddress: recipientAddress,
                paymentRequestModel: paymentRequestModel,
                initialPaymentAmount: initialPaymentAmount,
                isOutgoingTransfer: isOutgoingTransfer,
                mode: .fromConversationView)
    }

    public static func present(inNavigationController navigationController: UINavigationController,
                               delegate: SendPaymentViewDelegate,
                               recipientAddress: SignalServiceAddress,
                               paymentRequestModel: TSPaymentRequestModel?,
                               initialPaymentAmount: TSPaymentAmount? = nil,
                               isOutgoingTransfer: Bool,
                               mode: SendPaymentMode) {
        present(fromViewController: navigationController,
                presentationMode: .inNavigationController(navigationController: navigationController),
                delegate: delegate,
                recipientAddress: recipientAddress,
                paymentRequestModel: paymentRequestModel,
                initialPaymentAmount: initialPaymentAmount,
                isOutgoingTransfer: isOutgoingTransfer,
                mode: mode)
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = tableBackgroundColor

        addListeners()

        createSubviews()

        updateContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        helper?.refreshObservedValues()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad && CurrentAppContext().interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateContents()
    }

    private func addListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(isPaymentsVersionOutdatedDidChange),
            name: PaymentsConstants.isPaymentsVersionOutdatedDidChange,
            object: nil
        )
    }

    @objc
    private func isPaymentsVersionOutdatedDidChange() {
        guard UIApplication.shared.frontmostViewController == self else { return }
        if paymentsHelper.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .updateRequired)
        }
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    private func resetContents() {
        amounts.reset()

        memoMessage = nil
    }

    private func updateContents() {
        AssertIsOnMainThread()

        view.backgroundColor = tableBackgroundColor
        navigationItem.title = nil
        if mode.isModalRootView {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                               target: self,
                                                               action: #selector(didTapDismiss),
                                                               accessibilityIdentifier: "dismiss")
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = nil
        }

        updateAmountLabels()
        updateBalanceLabel()

        let swapCurrencyIconSize: CGFloat = 24
        let bigAmountLeft = UIView.container()
        let bigAmountRight: UIView
        if nil != currentCurrencyConversion {
            bigAmountRight = UIImageView.withTemplateImageName("payments-toggle-24",
                                                               tintColor: .ows_gray45)
            bigAmountRight.autoPinToSquareAspectRatio()
            bigAmountRight.isUserInteractionEnabled = true
            bigAmountRight.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                       action: #selector(didTapSwapCurrency)))
        } else {
            bigAmountRight = UIView.container()
        }
        bigAmountLeft.autoSetDimension(.width, toSize: swapCurrencyIconSize)
        bigAmountRight.autoSetDimension(.width, toSize: swapCurrencyIconSize)
        let bigAmountRow = UIStackView(arrangedSubviews: [bigAmountLeft, bigAmountLabel, bigAmountRight])
        bigAmountRow.axis = .horizontal
        bigAmountRow.alignment = .center
        bigAmountRow.spacing = 8

        let memoView: UIView
        if let hasMemoView = PaymentsViewUtils.buildMemoLabel(memoMessage: memoMessage) {
            memoView = hasMemoView
        } else {
            let addMemoLabel = UILabel()
            addMemoLabel.text = OWSLocalizedString("PAYMENTS_NEW_PAYMENT_ADD_MEMO",
                                                  comment: "Label for the 'add memo' ui in the 'send payment' UI.")
            addMemoLabel.font = .dynamicTypeBodyClamped
            addMemoLabel.textColor = Theme.accentBlueColor
            memoView = addMemoLabel
        }
        let memoStack = UIStackView(arrangedSubviews: [memoView])
        memoStack.axis = .vertical
        memoStack.alignment = .center
        memoStack.isLayoutMarginsRelativeArrangement = true
        memoStack.layoutMargins = UIEdgeInsets(hMargin: 0, vMargin: 12)
        memoStack.isUserInteractionEnabled = true
        memoStack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapAddMemo)))

        let spacerFactory = SpacerFactory()

        let keyboardViews = buildKeyboard(spacerFactory: spacerFactory)

        let amountButtons = buildAmountButtons()

        let smallAmountSpacerFactory = SpacerFactory()
        let smallAmountRow = UIStackView(arrangedSubviews: [
            smallAmountSpacerFactory.buildHSpacer(),
                                            smallAmountLabel,
                                            currencyConversionInfoView,
            smallAmountSpacerFactory.buildHSpacer()
                                            ])
        smallAmountSpacerFactory.finalizeSpacers()
        smallAmountRow.axis = .horizontal
        smallAmountRow.alignment = .center
        smallAmountRow.spacing = 8
        smallAmountRow.isUserInteractionEnabled = true
        smallAmountRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCurrencyConversionInfo)))

        var requiredViews = [UIView]()
        requiredViews += [
            bigAmountRow,
            smallAmountRow
        ]
        if isIdentifiedPayment {
            requiredViews.append(memoStack)
        }
        requiredViews += [
            amountButtons,
            balanceLabel
        ]
        requiredViews += keyboardViews.keyboardRows

        for requiredView in requiredViews {
            requiredView.setCompressionResistanceVerticalHigh()
            requiredView.setContentHuggingHigh()
        }

        rootStack.removeAllSubviews()
        rootStack.addArrangedSubviews([
            spacerFactory.buildVSpacer(),
            spacerFactory.buildVSpacer(),
            spacerFactory.buildVSpacer(),
            bigAmountRow,
            smallAmountRow,
            spacerFactory.buildVSpacer(),
            spacerFactory.buildVSpacer(),
            memoStack,
            spacerFactory.buildVSpacer(),
            spacerFactory.buildVSpacer(),
            spacerFactory.buildVSpacer()
        ] +
        keyboardViews.allRows
        + [
            spacerFactory.buildVSpacer(),
            spacerFactory.buildVSpacer(),
            spacerFactory.buildVSpacer(),
            amountButtons,
            spacerFactory.buildVSpacer(),
            balanceLabel
        ])

        spacerFactory.finalizeSpacers()

        UIView.matchHeightsOfViews(keyboardViews.keyboardRows)
    }

    struct KeyboardViews {
        let allRows: [UIView]
        let keyboardRows: [UIView]
    }

    private func buildKeyboard(spacerFactory: SpacerFactory) -> KeyboardViews {

        let keyboardHSpacing: CGFloat = 32
        let buttonFont = UIFont.dynamicTypeTitle1Clamped
        func buildAmountKeyboardButton(title: String, block: @escaping () -> Void) -> OWSButton {
            let button = OWSButton(block: block)

            let label = UILabel()
            label.text = title
            label.font = buttonFont
            label.textColor = Theme.primaryTextColor
            button.addSubview(label)
            button.backgroundColor = cellBackgroundColor
            label.autoCenterInSuperview()

            return button
        }
        func buildAmountKeyboardButton(imageName: String, block: @escaping () -> Void) -> OWSButton {
            let button = OWSButton(imageName: imageName,
                                   tintColor: Theme.primaryTextColor,
                                   block: block)
            button.backgroundColor = cellBackgroundColor
            return button
        }
        var keyboardRows = [UIView]()
        let buildAmountKeyboardRow = { (buttons: [OWSButton]) -> UIView in

            let buttons = buttons.map { (button) -> UIView in
                let buttonSize = buttonFont.lineHeight * 1.7
                button.autoSetDimension(.height, toSize: buttonSize)

                let downStateColor = (Theme.isDarkThemeEnabled
                                        ? UIColor.ows_gray90
                                        : UIColor.ows_gray02)
                let downStateImage = UIImage(color: downStateColor,
                                             size: CGSize(width: 1, height: 1))
                button.setBackgroundImage(downStateImage, for: .highlighted)

                // We clip the button to a circle so that the
                // down state is circular.
                let buttonClipView = OWSLayerView.circleView()
                buttonClipView.addSubview(button)
                button.autoPinEdgesToSuperviewEdges()
                buttonClipView.clipsToBounds = true

                let buttonWrapper = UIView.container()
                buttonWrapper.addSubview(buttonClipView)
                buttonClipView.autoPinEdge(toSuperviewEdge: .top)
                buttonClipView.autoPinEdge(toSuperviewEdge: .bottom)
                buttonClipView.autoHCenterInSuperview()
                buttonClipView.autoPinEdge(toSuperviewEdge: .leading)
                buttonClipView.autoPinEdge(toSuperviewEdge: .trailing)

                return buttonWrapper
            }

            let rowStack = UIStackView(arrangedSubviews: buttons)
            rowStack.axis = .horizontal
            rowStack.spacing = keyboardHSpacing
            rowStack.distribution = .fillEqually
            rowStack.alignment = .fill

            keyboardRows.append(rowStack)

            return rowStack
        }

        func buildDecimalButton() -> OWSButton {
            if let decimalSeparator = PaymentsConstants.decimalSeparator.nilIfEmpty {
                return buildAmountKeyboardButton(title: decimalSeparator) { [weak self] in
                    self?.keyboardPressedDecimal()
                }
            } else {
                return buildAmountKeyboardButton(imageName: "decimal-32") { [weak self] in
                    self?.keyboardPressedDecimal()
                }
            }
        }

        // Don't localize; use Arabic numeral literals.
        //
        // TODO: Localize or remove custom keyboard to support payments
        //       in locales that don't use arabic numerals.
        let allRows = [
            buildAmountKeyboardRow([
                buildAmountKeyboardButton(title: "1") { [weak self] in
                    self?.keyboardPressedNumeral("1")
                },
                buildAmountKeyboardButton(title: "2") { [weak self] in
                    self?.keyboardPressedNumeral("2")
                },
                buildAmountKeyboardButton(title: "3") { [weak self] in
                    self?.keyboardPressedNumeral("3")
                }
            ]),
            spacerFactory.buildVSpacer(),
            buildAmountKeyboardRow([
                buildAmountKeyboardButton(title: "4") { [weak self] in
                    self?.keyboardPressedNumeral("4")
                },
                buildAmountKeyboardButton(title: "5") { [weak self] in
                    self?.keyboardPressedNumeral("5")
                },
                buildAmountKeyboardButton(title: "6") { [weak self] in
                    self?.keyboardPressedNumeral("6")
                }
            ]),
            spacerFactory.buildVSpacer(),
            buildAmountKeyboardRow([
                buildAmountKeyboardButton(title: "7") { [weak self] in
                    self?.keyboardPressedNumeral("7")
                },
                buildAmountKeyboardButton(title: "8") { [weak self] in
                    self?.keyboardPressedNumeral("8")
                },
                buildAmountKeyboardButton(title: "9") { [weak self] in
                    self?.keyboardPressedNumeral("9")
                }
            ]),
            spacerFactory.buildVSpacer(),
            buildAmountKeyboardRow([
                buildDecimalButton(),
                buildAmountKeyboardButton(title: "0") { [weak self] in
                    self?.keyboardPressedNumeral("0")
                },
                buildAmountKeyboardButton(imageName: "delete-32") { [weak self] in
                    self?.keyboardPressedBackspace()
                }
            ])
        ]

        return KeyboardViews(allRows: allRows, keyboardRows: keyboardRows)
    }

    private func buildAmountButtons() -> UIView {
        let requestButton = buildBottomButton(title: OWSLocalizedString("PAYMENTS_NEW_PAYMENT_REQUEST_BUTTON",
                                                                       comment: "Label for the 'new payment request' button."),
                                              target: self,
                                              selector: #selector(didTapRequestButton))
        let payButton = buildBottomButton(title: OWSLocalizedString("PAYMENTS_NEW_PAYMENT_PAY_BUTTON",
                                                                   comment: "Label for the 'new payment' button."),
                                          target: self,
                                          selector: #selector(didTapPayButton))

        return buildBottomButtonStack(FeatureFlags.paymentsRequests
                                        ? [requestButton, payButton]
                                        : [payButton])
    }

    // MARK: -

    private func createSubviews() {

        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 0)
        rootStack.isLayoutMarginsRelativeArrangement = true
        view.addSubview(rootStack)
        rootStack.autoPinEdge(toSuperviewMargin: .leading, withInset: 20)
        rootStack.autoPinEdge(toSuperviewMargin: .trailing, withInset: 20)
        rootStack.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        rootStack.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        bigAmountLabel.font = UIFont.regularFont(ofSize: 60)
        bigAmountLabel.textAlignment = .center
        bigAmountLabel.adjustsFontSizeToFitWidth = true
        bigAmountLabel.minimumScaleFactor = 0.25
        bigAmountLabel.setContentHuggingVerticalHigh()
        bigAmountLabel.setCompressionResistanceVerticalHigh()

        smallAmountLabel.font = UIFont.dynamicTypeBody2
        smallAmountLabel.textColor = Theme.secondaryTextAndIconColor
        smallAmountLabel.textAlignment = .center
        smallAmountLabel.setContentHuggingVerticalHigh()
        smallAmountLabel.setCompressionResistanceVerticalHigh()

        currencyConversionInfoView.setTemplateImageName("info-outline-24",
                                                        tintColor: Theme.secondaryTextAndIconColor)
        currencyConversionInfoView.autoSetDimensions(to: .square(16))
        currencyConversionInfoView.setCompressionResistanceHigh()
    }

    private func updateAmountLabels() {

        let isZero = amount.inputString.isZero

        func hideConversionLabelOrShowWarning() {
            let shouldHaveValidValue = (!isZero && currentCurrencyConversion != nil)
            smallAmountLabel.text = (shouldHaveValidValue
                                        ? OWSLocalizedString("PAYMENTS_NEW_PAYMENT_INVALID_AMOUNT",
                                                            comment: "Label for the 'invalid amount' button.")
                                        : " ")
            smallAmountLabel.textColor = UIColor.ows_accentRed
            currencyConversionInfoView.tintColor = .clear
        }

        func enableSmallLabel(_ text: String) {
            smallAmountLabel.text = text
            smallAmountLabel.textColor = Theme.secondaryTextAndIconColor
            currencyConversionInfoView.tintColor = Theme.secondaryTextAndIconColor
        }

        bigAmountLabel.attributedText = amount.formatAsKeyboardInputAttributed(withSpace: false)

        switch amount {
        case .mobileCoin:
            if let otherCurrencyAmount = self.otherCurrencyAmount,
               let currencyConversion = otherCurrencyAmount.currencyConversion {
                let formattedAmount = otherCurrencyAmount.formatForDisplay(withSpace: true).string
                enableSmallLabel(Self.formatWithConversionFreshness(formattedAmount: formattedAmount,
                                                                    currencyConversion: currencyConversion,
                                                                    isZero: isZero))
            } else if let currencyConversion = currentCurrencyConversion,
                      let fiatCurrencyAmount = currencyConversion.convertToFiatCurrency(paymentAmount: parsedPaymentAmount),
                      let fiatString = PaymentsFormat.attributedFormat(fiatCurrencyAmount: fiatCurrencyAmount,
                                                                       currencyCode: currencyConversion.currencyCode,
                                                                       withSpace: true) {
                enableSmallLabel(Self.formatWithConversionFreshness(formattedAmount: fiatString.string,
                                                                    currencyConversion: currencyConversion,
                                                                    isZero: isZero))
            } else {
                hideConversionLabelOrShowWarning()
            }
        case .fiatCurrency(_, let currencyConversion):
            if let otherCurrencyAmount = self.otherCurrencyAmount {
                let formattedAmount = otherCurrencyAmount.formatForDisplay(withSpace: true).string
                enableSmallLabel(Self.formatWithConversionFreshness(formattedAmount: formattedAmount,
                                                                    currencyConversion: currencyConversion,
                                                                    isZero: isZero))
            } else {
                let paymentAmount = currencyConversion.convertFromFiatCurrencyToMOB(amount.asDouble)
                let formattedAmount = PaymentsFormat.attributedFormat(paymentAmount: paymentAmount,
                                                                      isShortForm: false,
                                                                      withSpace: true).string
                enableSmallLabel(Self.formatWithConversionFreshness(formattedAmount: formattedAmount,
                                                                    currencyConversion: currencyConversion,
                                                                    isZero: isZero))
            }
        }
    }

    static func formatWithConversionFreshness(formattedAmount: String,
                                              currencyConversion: CurrencyConversionInfo,
                                              isZero: Bool) -> String {
        guard !isZero else {
            return formattedAmount
        }
        let formattedFreshness = DateUtil.formatDateAsTime(currencyConversion.conversionDate)
        let conversionFormat = OWSLocalizedString("PAYMENTS_CURRENCY_CONVERSION_FRESHNESS_FORMAT",
                                                 comment: "Format for indicator of a payment amount converted to fiat currency with the freshness of the conversion rate. Embeds: {{ %1$@ the payment amount, %2$@ the freshness of the currency conversion rate }}.")
        return String(format: conversionFormat, formattedAmount, formattedFreshness)
    }

    private func updateBalanceLabel() {
        guard let helper = helper else {
            Logger.verbose("Missing helper.")
            return
        }
        helper.updateBalanceLabel(balanceLabel)
    }

    private func showInvalidAmountAlert() {
        let errorMessage = OWSLocalizedString("PAYMENTS_NEW_PAYMENT_INVALID_AMOUNT",
                                             comment: "Label for the 'invalid amount' button.")
        OWSActionSheets.showErrorAlert(message: errorMessage)
    }

    // MARK: - Events

    @objc
    func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func didTapAddMemo() {
        let view = SendPaymentMemoViewController(memoMessage: self.memoMessage)
        view.delegate = self
        navigationController?.pushViewController(view, animated: true)
    }

    private func updateAmount(_ amount: Amount) -> Amount {
        guard let currencyConversion = self.currentCurrencyConversion else {
            return amount
        }
        switch amount {
        case .mobileCoin:
            return amount
        case .fiatCurrency(let inputString, _):
            return .fiatCurrency(inputString: inputString, currencyConversion: currencyConversion)
        }
    }

    @objc
    func didTapSwapCurrency() {
        // If users repeatedly swap input currency, we don't want the
        // values to drift due to rounding errors.  So we keep around
        // the "other" currency amount and use it to swap if no changes
        // have been made since the last switch.
        if let otherCurrencyAmount = otherCurrencyAmount {
            amounts.set(currentAmount: updateAmount(otherCurrencyAmount),
                        otherCurrencyAmount: updateAmount(self.amount))
            return
        }

        switch amount {
        case .mobileCoin:
            if let currencyConversion = currentCurrencyConversion,
               let fiatCurrencyAmount = currencyConversion.convertToFiatCurrency(paymentAmount: parsedPaymentAmount),
               let fiatString = PaymentsFormat.formatAsDoubleString(fiatCurrencyAmount) {
                // Store the otherCurrencyAmount.
                amounts.set(currentAmount: .fiatCurrency(inputString: InputString.parseString(fiatString, isFiat: true),
                                                         currencyConversion: currencyConversion),
                            otherCurrencyAmount: self.amount)
            } else {
                owsFailDebug("Could not switch to fiat currency.")
                resetContents()
            }
        case .fiatCurrency(_, let currencyConversion):
            let paymentAmount = currencyConversion.convertFromFiatCurrencyToMOB(amount.asDouble)
            if let mobString = PaymentsFormat.formatAsDoubleString(picoMob: paymentAmount.picoMob) {
                // Store the otherCurrencyAmount.
                amounts.set(currentAmount: .mobileCoin(inputString: InputString.parseString(mobString,
                                                                                            isFiat: false),
                                                       exactAmount: nil),
                            otherCurrencyAmount: self.amount)
            } else {
                owsFailDebug("Could not switch from fiat currency.")
                resetContents()
            }
        }
    }

    @objc
    func didTapRequestButton(_ sender: UIButton) {
        // TODO: Add support for requests.
        //        guard let parsedAmount = parsedAmount,
        //              parsedAmount > 0 else {
        //            showInvalidAmountAlert()
        //            return
        //        }
        //        let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: parsedAmount)
        //        // Snapshot the conversion rate.
        //        let currencyConversion = self.currentCurrencyConversion
        //        currentStep = .confirmRequest(paymentAmount: paymentAmount, currencyConversion: currencyConversion)
    }

    // MARK: -

    private static let keyValueStore = SDSKeyValueStore(collection: "SendPaymentView")
    private static let wasLastPaymentInFiatKey = "wasLastPaymentInFiat"

    private static var wasLastPaymentInFiat: Bool {
        Self.databaseStorage.read { transaction in
            Self.keyValueStore.getBool(Self.wasLastPaymentInFiatKey,
                                       defaultValue: false,
                                       transaction: transaction)
        }
    }

    private func setWasLastPaymentInFiat(_ value: Bool) {
        Self.databaseStorage.write { transaction in
            Self.keyValueStore.setBool(value,
                                       key: Self.wasLastPaymentInFiatKey,
                                       transaction: transaction)
        }
    }

    // MARK: -
    private var actionSheet: SendPaymentCompletionActionSheet?

    @objc
    func didTapPayButton(_ sender: UIButton) {
        let paymentAmount = parsedPaymentAmount
        guard paymentAmount.picoMob > 0 else {
            showInvalidAmountAlert()
            return
        }

        setWasLastPaymentInFiat(amounts.currentAmount.isFiat)

        getEstimatedFeeAndSubmit(paymentAmount: paymentAmount)
    }

    private func getEstimatedFeeAndSubmit(paymentAmount: TSPaymentAmount) {
        ModalActivityIndicatorViewController.presentAsInvisible(fromViewController: self) { modalActivityIndicator in
            firstly {
                Self.paymentsSwift.getEstimatedFee(forPaymentAmount: paymentAmount)
            }.done { (estimatedFeeAmount: TSPaymentAmount) in
                AssertIsOnMainThread()

                modalActivityIndicator.dismiss {
                    self.tryToShowPaymentCompletionUI(paymentAmount: paymentAmount,
                                                      estimatedFeeAmount: estimatedFeeAmount)
                }
            }.catch { error in
                AssertIsOnMainThread()
                if case PaymentsError.insufficientFunds = error {
                    Logger.warn("Error: \(error)")
                } else {
                    owsFailDebugUnlessMCNetworkFailure(error)
                }

                modalActivityIndicator.dismiss {
                    AssertIsOnMainThread()

                    OWSActionSheets.showErrorAlert(
                        message: SendPaymentCompletionActionSheet.formatPaymentFailure(error,
                                                                                       withErrorPrefix: false)
                    )
                }
            }
        }
    }

    private func tryToShowPaymentCompletionUI(paymentAmount: TSPaymentAmount,
                                              estimatedFeeAmount: TSPaymentAmount) {
        guard paymentAmount.isValidAmount(canBeEmpty: false),
              estimatedFeeAmount.isValidAmount(canBeEmpty: false) else {
            showInvalidAmountAlert()
            return
        }
        let totalAmount = paymentAmount.plus(estimatedFeeAmount)
        guard let paymentBalance = paymentsSwift.currentPaymentBalance else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_CANNOT_SEND_PAYMENT_NO_BALANCE",
                                                                      comment: "Error message indicating that a payment could not be sent because the current balance is unavailable."))
            return
        }
        guard paymentBalance.amount.picoMob >= totalAmount.picoMob else {
            showInsufficientBalanceUI(paymentBalance: paymentBalance)
            return
        }

        showPaymentCompletionUI(paymentAmount: paymentAmount,
                                estimatedFeeAmount: estimatedFeeAmount)
    }

    private func showInsufficientBalanceUI(paymentBalance: PaymentBalance) {
        let messageFormat = OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_INSUFFICIENT_BALANCE_ALERT_MESSAGE_FORMAT",
                                              comment: "Message for the 'insufficient balance for payment' alert. Embeds: {{ The current payments balance }}.")
        let message = String(format: messageFormat, PaymentsFormat.format(paymentAmount: paymentBalance.amount,
                                                                          isShortForm: false,
                                                                          withCurrencyCode: true,
                                                                          withSpace: true))

        let actionSheet = ActionSheetController(title: OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_INSUFFICIENT_BALANCE_ALERT_TITLE",
                                                                         comment: "Title for the 'insufficient balance for payment' alert."),
                                                message: message)

        // There's no point doing a "transfer in" transaction in order to
        // enable a "transfer out".
        if mode != .fromTransferOutFlow {
            actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_ADD_MONEY",
                                                                             comment: "Label for the 'add money' button in the 'send payment' UI."),
                                                    accessibilityIdentifier: "payments.settings.add_money",
                                                    style: .default) { [weak self] _ in
                self?.didTapAddMoneyButton()
            })
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didTapAddMoneyButton() {
        switch mode {
        case .fromConversationView:
            dismiss(animated: true) {
                guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
                    owsFailDebug("could not identify frontmostViewController")
                    return
                }
                frontmostViewController.navigationController?.popToRootViewController(animated: true)
                SignalApp.shared().showAppSettings(mode: .paymentsTransferIn)
            }
        case .fromPaymentSettings:
            let paymentsTransferIn = PaymentsTransferInViewController()
            navigationController?.pushViewController(paymentsTransferIn, animated: true)
        case .fromTransferOutFlow:
            owsFailDebug("Unexpected interaction.")

            dismiss(animated: true) {
                guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
                    owsFailDebug("could not identify frontmostViewController")
                    return
                }
                guard let navigationController = frontmostViewController.navigationController else {
                    owsFailDebug("Missing navigationController.")
                    return
                }
                let paymentsTransferIn = PaymentsTransferInViewController()
                navigationController.pushViewController(paymentsTransferIn, animated: true)
            }
        }
    }

    private func showPaymentCompletionUI(paymentAmount: TSPaymentAmount,
                                         estimatedFeeAmount: TSPaymentAmount) {
        // Snapshot the conversion rate.
        let currencyConversion = self.currentCurrencyConversion

        Logger.verbose("paymentAmount: \(paymentAmount)")
        Logger.verbose("estimatedFeeAmount: \(estimatedFeeAmount)")

        let paymentInfo = PaymentInfo(recipient: recipient,
                                      paymentAmount: paymentAmount,
                                      estimatedFeeAmount: estimatedFeeAmount,
                                      currencyConversion: currencyConversion,
                                      paymentRequestModel: paymentRequestModel,
                                      memoMessage: memoMessage,
                                      isOutgoingTransfer: isOutgoingTransfer)
        let actionSheet = SendPaymentCompletionActionSheet(mode: .payment(paymentInfo: paymentInfo),
                                                           delegate: self)
        self.actionSheet = actionSheet
        actionSheet.present(fromViewController: self)
    }

    private static func showEnablePaymentsActionSheet() {
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }
        let title = OWSLocalizedString("SETTINGS_PAYMENTS_NOT_ENABLED_ALERT_TITLE",
                                      comment: "Title for the 'payments not enabled' alert.")
        let message = OWSLocalizedString("SETTINGS_PAYMENTS_NOT_ENABLED_ALERT_MESSAGE",
                                        comment: "Message for the 'payments not enabled' alert.")
        let actionSheet = ActionSheetController(title: title,
                                                message: message)

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("SETTINGS_PAYMENTS_ENABLE_ACTION",
                                                                         comment: "Label for the 'enable payments' button in the 'payments not enabled' alert."),
                                                accessibilityIdentifier: "payments.send.enable",
                                                style: .default) { _ in
            Self.didTapEnablePaymentsButton()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        frontmostViewController.presentActionSheet(actionSheet)
    }

    private static func showNotRegisteredActionSheet() {
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }
        let title = OWSLocalizedString("SETTINGS_PAYMENTS_NOT_REGISTERED_ALERT_TITLE",
                                      comment: "Title for the 'payments not registered' alert.")
        let message = OWSLocalizedString("SETTINGS_PAYMENTS_NOT_REGISTERED_ALERT_MESSAGE",
                                        comment: "Message for the 'payments not registered' alert.")
        let actionSheet = ActionSheetController(title: title, message: message)

        actionSheet.addAction(OWSActionSheets.okayAction)

        frontmostViewController.presentActionSheet(actionSheet)
    }

    private static func didTapEnablePaymentsButton() {
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }
        frontmostViewController.navigationController?.popToRootViewController(animated: true)
        SignalApp.shared().showAppSettings(mode: .payments)
    }

    @objc
    private func didTapCurrencyConversionInfo() {
        PaymentsSettingsViewController.showCurrencyConversionInfoAlert(fromViewController: self)
    }
}

// MARK: -

extension SendPaymentViewController: SendPaymentMemoViewDelegate {
    public func didChangeMemo(memoMessage: String?) {
        self.memoMessage = memoMessage?.nilIfEmpty

        updateContents()
    }
}

// MARK: - Payment Keyboard

fileprivate extension SendPaymentViewController {

    private func keyboardPressedNumeral(_ numeralString: String) {
        let inputString = amount.inputString.append(.digit(digit: numeralString))
        updateAmountString(inputString)
    }

    private func keyboardPressedDecimal() {
        let inputString = amount.inputString.append(.decimal)
        updateAmountString(inputString)
    }

    private func keyboardPressedBackspace() {
        let inputString = amount.inputString.removeLastChar()
        updateAmountString(inputString)
    }

    private func updateAmountString(_ inputString: InputString) {
        switch amount {
        case .mobileCoin:
            amounts.set(currentAmount: .mobileCoin(inputString: inputString,
                                                   exactAmount: nil),
                        otherCurrencyAmount: nil)
        case .fiatCurrency(_, let oldCurrencyConversion):
            let newCurrencyConversion = self.currentCurrencyConversion ?? oldCurrencyConversion
            amounts.set(currentAmount: .fiatCurrency(inputString: inputString,
                                                     currencyConversion: newCurrencyConversion),
                        otherCurrencyAmount: nil)
        }
    }

    private var parsedPaymentAmount: TSPaymentAmount {
        switch amount {
        case .mobileCoin(_, let exactAmount):
            if let exactAmount = exactAmount {
                return exactAmount
            }
            let picoMob = PaymentsConstants.convertMobToPicoMob(amount.asDouble)
            return TSPaymentAmount(currency: .mobileCoin, picoMob: picoMob)
        case .fiatCurrency(_, let currencyConversion):
            return currencyConversion.convertFromFiatCurrencyToMOB(amount.asDouble)
        }
    }
}

// MARK: -

extension SendPaymentViewController: SendPaymentHelperDelegate {
    @objc
    public func balanceDidChange() {
        updateBalanceLabel()
    }

    @objc
    public func currencyConversionDidChange() {
        guard isViewLoaded else {
            return
        }
        guard nil != currentCurrencyConversion else {
            Logger.warn("Currency conversion unavailable.")
            resetContents()
            return
        }

        if let otherCurrencyAmount = otherCurrencyAmount {
            amounts.set(currentAmount: updateAmount(self.amount),
                        otherCurrencyAmount: updateAmount(otherCurrencyAmount))
        } else {
            amounts.set(currentAmount: updateAmount(self.amount),
                        otherCurrencyAmount: nil)
        }

        updateAmountLabels()
        updateBalanceLabel()
    }
}

// MARK: -

extension SendPaymentViewController: SendPaymentCompletionDelegate {
    public func didSendPayment(success: Bool) {
        let delegate = self.delegate
        self.dismiss(animated: true) {
            delegate?.didSendPayment(success: success)
        }
    }
}

// MARK: - Amount

private enum Amount {
    // inputString should be a raw double strings: e.g. 123456.789.
    // It should not be formatted: e.g. 123,456.789
    case mobileCoin(inputString: InputString, exactAmount: TSPaymentAmount?)
    case fiatCurrency(inputString: InputString, currencyConversion: CurrencyConversionInfo)

    var isFiat: Bool {
        switch self {
        case .mobileCoin:
            return false
        case .fiatCurrency:
            return true
        }
    }

    var isZero: Bool {
        switch self {
        case .mobileCoin(let inputString, _):
            return inputString.isZero
        case .fiatCurrency(let inputString, _):
            return inputString.isZero
        }
    }

    var inputString: InputString {
        switch self {
        case .mobileCoin(let inputString, _):
            return inputString
        case .fiatCurrency(let inputString, _):
            return inputString
        }
    }

    var currencyConversion: CurrencyConversionInfo? {
        switch self {
        case .mobileCoin:
            return nil
        case .fiatCurrency(_, let currencyConversion):
            return currencyConversion
        }
    }

    var asDouble: Double {
        inputString.asDouble
    }

    var formatForDisplay: String {
        switch self {
        case .mobileCoin:
            guard let mobString = PaymentsFormat.format(mob: asDouble,
                                                        isShortForm: false) else {
                owsFailDebug("Couldn't format MOB string: \(inputString.asString(formatMode: .parsing))")
                return inputString.asString(formatMode: .display)
            }
            return mobString
        case .fiatCurrency:
            guard let fiatString = PaymentsFormat.format(fiatCurrencyAmount: asDouble,
                                                         minimumFractionDigits: 0) else {
                owsFailDebug("Couldn't format fiat string: \(inputString.asString(formatMode: .parsing))")
                return inputString.asString(formatMode: .display)
            }
            return fiatString
        }
    }

    var formatAsKeyboardInput: String {
        inputString.formatAsKeyboardInput
    }

    func formatForDisplay(withSpace: Bool) -> NSAttributedString {
        switch self {
        case .mobileCoin:
            return PaymentsFormat.attributedFormat(mobileCoinString: formatForDisplay,
                                                   withSpace: withSpace)
        case .fiatCurrency(_, let currencyConversion):
            return PaymentsFormat.attributedFormat(currencyString: formatForDisplay,
                                                   currencyCode: currencyConversion.currencyCode,
                                                   withSpace: withSpace)
        }
    }

    func formatAsKeyboardInputAttributed(withSpace: Bool) -> NSAttributedString {
        switch self {
        case .mobileCoin:
            return PaymentsFormat.attributedFormat(mobileCoinString: formatAsKeyboardInput,
                                                   withSpace: withSpace)
        case .fiatCurrency(_, let currencyConversion):
            return PaymentsFormat.attributedFormat(currencyString: formatAsKeyboardInput,
                                                   currencyCode: currencyConversion.currencyCode,
                                                   withSpace: withSpace)
        }
    }
}

// MARK: -

private protocol AmountsDelegate: AnyObject {
    func amountDidChange(oldValue: Amount, newValue: Amount)
}

// MARK: -

private class Amounts: Dependencies {

    weak var delegate: AmountsDelegate?

    public static var defaultMCAmount: Amount {
        .mobileCoin(inputString: InputString.defaultString(isFiat: false),
                    exactAmount: nil)
    }

    public static var defaultFiatAmount: Amount? {
        let currentCurrencyCode = Self.paymentsCurrencies.currentCurrencyCode
        guard let currencyConversion = Self.paymentsCurrenciesSwift.conversionInfo(forCurrencyCode: currentCurrencyCode) else {
            return nil
        }
        return .fiatCurrency(inputString: InputString.defaultString(isFiat: true),
                             currencyConversion: currencyConversion)
    }

    fileprivate private(set) var currentAmount: Amount = Amounts.defaultMCAmount
    fileprivate private(set) var otherCurrencyAmount: Amount?

    func set(currentAmount: Amount, otherCurrencyAmount: Amount?) {
        let oldValue = self.currentAmount

        self.currentAmount = currentAmount
        self.otherCurrencyAmount = otherCurrencyAmount

        delegate?.amountDidChange(oldValue: oldValue, newValue: currentAmount)
    }

    func reset() {
        set(currentAmount: Self.defaultMCAmount, otherCurrencyAmount: nil)
    }
}

// MARK: -

extension SendPaymentViewController: AmountsDelegate {
    fileprivate func amountDidChange(oldValue: Amount, newValue: Amount) {
        guard isViewLoaded else {
            return
        }
        if oldValue.isFiat != newValue.isFiat {
            updateContents()
        } else {
            updateAmountLabels()
        }
    }
}

// MARK: -

private enum FormatMode {
    case display
    case parsing
}

// MARK: -

private enum InputChar: Equatable {
    case digit(digit: String)
    case decimal

    func asString(formatMode: FormatMode) -> String {
        switch self {
        case .digit(let digit):
            return digit
        case .decimal:
            switch formatMode {
            case .display:
                return PaymentsConstants.decimalSeparator
            case .parsing:
                return "."
            }
        }
    }

    static func isDigit(_ value: String) -> Bool {
        "0123456789".contains(value)
    }
}

// MARK: -

private struct InputString: Equatable {
    let chars: [InputChar]
    let isFiat: Bool

    init(_ chars: [InputChar], isFiat: Bool) {
        self.chars = chars
        self.isFiat = isFiat
    }

    static func forDouble(_ value: Double, isFiat: Bool) -> InputString {
        guard let stringValue = PaymentsFormat.formatAsDoubleString(value) else {
            owsFailDebug("Couldn't format double: \(value)")
            return Self.defaultString(isFiat: isFiat)
        }
        return parseString(stringValue, isFiat: isFiat)
    }

    static func parseString(_ stringValue: String, isFiat: Bool) -> InputString {
        var result = InputString.defaultString(isFiat: isFiat)
        for char in stringValue {
            let charString = String(char)
            if charString == InputChar.decimal.asString(formatMode: .parsing) {
                result = result.append(InputChar.decimal)
            } else if InputChar.isDigit(charString) {
                result = result.append(InputChar.digit(digit: charString))
            } else {
                owsFailDebug("Ignoring invalid character: \(charString)")
            }
        }
        return result
    }

    static var defaultChar: InputChar { .digit(digit: "0") }
    static func defaultString(isFiat: Bool) -> InputString {
        InputString([defaultChar], isFiat: isFiat)
    }

    func append(_ char: InputChar) -> InputString {
        let result: InputString = {
            switch char {
            case .digit:
                // Avoid leading zeroes.
                //
                // "00" should be "0"
                // "01" should be "1"
                if self == Self.defaultString(isFiat: isFiat) {
                    return InputString([char], isFiat: isFiat)
                } else {
                    return InputString(chars + [char], isFiat: isFiat)
                }
            case .decimal:
                if hasDecimal {
                    // Don't allow two decimals.
                    return self
                } else {
                    return InputString(chars + [char], isFiat: isFiat)
                }
            }
        }()
        Logger.verbose("Before: \(self.asCharString) -> \(self.asString(formatMode: .parsing)), \(self.digitCountBeforeDecimal), \(self.digitCountAfterDecimal), \(result.asDouble)")
        Logger.verbose("Considering: \(result.asCharString) -> \(result.asString(formatMode: .parsing)), \(result.digitCountBeforeDecimal), \(result.digitCountAfterDecimal), \(result.asDouble)")
        guard result.isValid else {
            Logger.warn("Invalid result: \(self.asString(formatMode: .parsing)) -> \(result.asString(formatMode: .parsing))")
            return self
        }
        return result
    }

    func removeLastChar() -> InputString {
        if chars.count > 1 {
            return InputString(Array(chars.prefix(chars.count - 1)),
                               isFiat: isFiat)
        } else {
            return Self.defaultString(isFiat: isFiat)
        }
    }

    var isValid: Bool {
        (digitCountBeforeDecimal <= maxDigitsBeforeDecimal &&
            digitCountAfterDecimal <= maxDigitsAfterDecimal)
    }

    var isZero: Bool {
        !isNonZero
    }

    var isNonZero: Bool {
        for char in chars {
            switch char {
            case .digit(let digit):
                if digit != "0" {
                    return true
                }
            case .decimal:
                continue
            }
        }
        return false
    }

    static func maxDigitsBeforeDecimal(isFiat: Bool) -> UInt {
        // Max transaction size: 1 billion MOB.
        Logger.verbose("maxMobNonDecimalDigits: \(PaymentsConstants.maxMobNonDecimalDigits)")
        return isFiat ? 9 : PaymentsConstants.maxMobNonDecimalDigits
    }

    static func maxDigitsAfterDecimal(isFiat: Bool) -> UInt {
        // picoMob
        isFiat ? 2 : 12
    }

    var maxDigitsBeforeDecimal: UInt {
        Self.maxDigitsBeforeDecimal(isFiat: isFiat)
    }

    var maxDigitsAfterDecimal: UInt {
        Self.maxDigitsAfterDecimal(isFiat: isFiat)
    }

    var digitsBeforeDecimal: [String] {
        var result = [String]()
        for char in chars {
            switch char {
            case .digit(let digit):
                result.append(digit)
            case .decimal:
                return result
            }
        }
        return result
    }

    var digitCountBeforeDecimal: Int {
        digitsBeforeDecimal.count
    }

    var digitsAfterDecimal: [String] {
        var result = [String]()
        var hasPassedDecimal = false
        for char in chars {
            switch char {
            case .digit(let digit):
                if hasPassedDecimal {
                    result.append(digit)
                }
            case .decimal:
                hasPassedDecimal = true
            }
        }
        return result
    }

    var digitCountAfterDecimal: Int {
        digitsAfterDecimal.count
    }

    var hasDecimal: Bool {
        !Array(chars.filter { $0 == .decimal }).isEmpty
    }

    func asString(formatMode: FormatMode) -> String {
        chars.map { $0.asString(formatMode: formatMode) }.joined()
    }

    var asCharString: String {
        "[" + chars.map { $0.asString(formatMode: .parsing) }.joined(separator: ", ") + "]"
    }

    var asDouble: Double {
        Self.parseAsDouble(asString(formatMode: .parsing))
    }

    private static func parseAsDouble(_ stringValue: String) -> Double {
        guard let value = Double(stringValue.ows_stripped()) else {
            // inputString should be parseable at all times.
            Logger.verbose("stringValue: \(stringValue)")
            owsFailDebug("Invalid inputString.")
            return 0
        }
        return value
    }

    // We need to manually format (more or less) the exact input string
    // when redering the "keyboard input" so that every keystroke of
    // the custom keyboard updates the "keyboard input" in a WYSIWYG
    // fashion, e.g. if the user enters "0.0000000", we need to render
    // the exact number of zeros the user has entered.
    var formatAsKeyboardInput: String {
        let groupingSeparator = PaymentsConstants.groupingSeparator
        let decimalSeparator = PaymentsConstants.decimalSeparator
        let groupingSize = PaymentsConstants.groupingSize
        let shouldUseGroupingSeparatorsAfterDecimal = PaymentsConstants.shouldUseGroupingSeparatorsAfterDecimal

        func addGroupingSeparators(digits: [String], afterGroupsOfSize groupSize: Int) -> [String] {
            var result = [String]()
            for (index, digit) in digits.enumerated() {
                if index != 0,
                   index % groupSize == 0 {
                    result.append(groupingSeparator)
                }
                result.append(digit)
            }
            return result
        }

        var formattedChars = [String]()

        // e.g.:
        //
        // 1,234,567.890,123,456.
        // 0.000,000,001
        formattedChars.append(contentsOf: addGroupingSeparators(digits: digitsBeforeDecimal.reversed(),
                                                                afterGroupsOfSize: groupingSize).reversed())
        if hasDecimal {
            formattedChars.append(decimalSeparator)
        }

        if shouldUseGroupingSeparatorsAfterDecimal {
            formattedChars.append(contentsOf: addGroupingSeparators(digits: digitsAfterDecimal,
                                                                    afterGroupsOfSize: groupingSize))
        } else {
            formattedChars.append(contentsOf: digitsAfterDecimal)
        }

        let formatted = formattedChars.joined()
        return formatted
    }
}

// MARK: -

// This view's contents must adapt to a wide variety of form factors.
// We use vertical spacers of equal height to ensure the layout is
// both responsive and balanced.
class SpacerFactory {
    private var hSpacers = [UIView]()
    private var vSpacers = [UIView]()

    func buildHSpacer() -> UIView {
        let spacer = UIView.container()
        spacer.setContentHuggingHorizontalLow()
        hSpacers.append(spacer)
        return spacer
    }

    func buildVSpacer() -> UIView {
        let spacer = UIView.container()
        spacer.setContentHuggingVerticalLow()
        vSpacers.append(spacer)
        return spacer
    }

    func finalizeSpacers() {
        UIView.matchWidthsOfViews(hSpacers)
        UIView.matchHeightsOfViews(vSpacers)
    }
}
