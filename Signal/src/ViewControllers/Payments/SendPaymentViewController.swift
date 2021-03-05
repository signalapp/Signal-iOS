//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit
import Lottie

@objc
public protocol SendPaymentViewDelegate {
    func didSendPayment()
}

// MARK: -

// TODO: We either need a dismiss button or ensure that this isn't always visible.
@objc
public class SendPaymentViewController: OWSViewController {

    fileprivate typealias PaymentInfo = SendPaymentInfo

    @objc
    public weak var delegate: SendPaymentViewDelegate?

    private let recipient: SendPaymentRecipient
    private let paymentRequestModel: TSPaymentRequestModel?
    private let isOutgoingTransfer: Bool

    private let isStandaloneView: Bool

    private let rootStack = UIStackView()

    private let bigAmountLabel = UILabel()
    private let smallAmountLabel = UILabel()

    private let balanceLabel = SendPaymentHelper.buildBottomLabel()

    // MARK: - Amount

    private let amounts = Amounts()
    private var amount: Amount { amounts.currentAmount }
    private var otherCurrencyAmount: Amount? { amounts.otherCurrencyAmount }

    // MARK: -

    private var memoMessage: String?

    private var helper: SendPaymentHelper?

    private var currentCurrencyConversion: CurrencyConversionInfo? { helper?.currentCurrencyConversion }

    public required init(recipient: SendPaymentRecipient,
                         paymentRequestModel: TSPaymentRequestModel?,
                         isOutgoingTransfer: Bool,
                         isStandaloneView: Bool) {
        self.recipient = recipient
        self.isStandaloneView = isStandaloneView
        self.isOutgoingTransfer = isOutgoingTransfer

        if !FeatureFlags.paymentsRequests {
            owsAssertDebug(paymentRequestModel == nil)
            self.paymentRequestModel = nil
        } else {
            self.paymentRequestModel = paymentRequestModel

            if let paymentRequestModel = paymentRequestModel {
                owsAssertDebug(paymentRequestModel.paymentAmount.currency == .mobileCoin)

                if let requestAmountString = PaymentsImpl.formatAsDoubleString(picoMob: paymentRequestModel.paymentAmount.picoMob) {
                    let inputString = InputString.forString(requestAmountString, isFiat: false)
                    amounts.set(currentAmount: .mobileCoin(inputString: inputString), otherCurrencyAmount: nil)
                } else {
                    owsFailDebug("Could not apply request amount.")
                }
            }
        }

        super.init()

        helper = SendPaymentHelper(delegate: self)
        amounts.delegate = self
    }

    @objc
    public static func presentAsFormSheet(fromViewController: UIViewController,
                                          delegate: SendPaymentViewDelegate,
                                          recipientAddress: SignalServiceAddress,
                                          paymentRequestModel: TSPaymentRequestModel?,
                                          isOutgoingTransfer: Bool) {

        let recipientHasPaymentsEnabled = databaseStorage.read { transaction in
            Self.payments.arePaymentsEnabled(for: recipientAddress, transaction: transaction)
        }
        guard recipientHasPaymentsEnabled else {
            // TODO: Should we try to fill in this state before showing the error alert?
            ProfileFetcherJob.fetchProfile(address: recipientAddress, ignoreThrottling: true)

            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PAYMENTS_RECIPIENT_PAYMENTS_NOT_ENABLED",
                                                                      comment: "Indicator that a given user cannot receive payments because the have not enabled payments."))
            return
        }

        let recipient: SendPaymentRecipientImpl = .address(address: recipientAddress)
        let view = SendPaymentViewController(recipient: recipient,
                                             paymentRequestModel: paymentRequestModel,
                                             isOutgoingTransfer: isOutgoingTransfer,
                                             isStandaloneView: true)
        view.delegate = delegate
        let navigationController = OWSNavigationController(rootViewController: view)
        fromViewController.presentFormSheet(navigationController, animated: true)
    }

    @objc
    public static func presentInNavigationController(_ navigationController: UINavigationController,
                                                     delegate: SendPaymentViewDelegate,
                                                     recipientAddress: SignalServiceAddress,
                                                     paymentRequestModel: TSPaymentRequestModel?,
                                                     isOutgoingTransfer: Bool) {

        let recipientHasPaymentsEnabled = databaseStorage.read { transaction in
            Self.payments.arePaymentsEnabled(for: recipientAddress, transaction: transaction)
        }
        guard recipientHasPaymentsEnabled else {
            // TODO: Should we try to fill in this state before showing the error alert?
            ProfileFetcherJob.fetchProfile(address: recipientAddress, ignoreThrottling: true)

            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PAYMENTS_RECIPIENT_PAYMENTS_NOT_ENABLED",
                                                                      comment: "Indicator that a given user cannot receive payments because the have not enabled payments."))
            return
        }

        let recipient: SendPaymentRecipientImpl = .address(address: recipientAddress)
        let view = SendPaymentViewController(recipient: recipient,
                                             paymentRequestModel: paymentRequestModel,
                                             isOutgoingTransfer: isOutgoingTransfer,
                                             isStandaloneView: false)
        view.delegate = delegate
        navigationController.pushViewController(view, animated: true)
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        createSubviews()

        updateContents()

        helper?.refreshObservedValues()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        //
        // PAYMENTS TODO:
        if !UIDevice.current.isIPad && CurrentAppContext().interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }

        helper?.refreshObservedValues()
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    private func resetContents() {
        amounts.reset()

        memoMessage = ""
    }

    private func updateContents() {
        AssertIsOnMainThread()

        view.backgroundColor = Theme.backgroundColor
        navigationItem.title = nil
        if isStandaloneView {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop,
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

        let addMemoLabel = UILabel()
        addMemoLabel.text = NSLocalizedString("PAYMENTS_NEW_PAYMENT_ADD_MEMO",
                                              comment: "Label for the 'add memo' ui in the 'send payment' UI.")
        addMemoLabel.font = .ows_dynamicTypeBodyClamped
        addMemoLabel.textColor = Theme.accentBlueColor

        let addMemoStack = UIStackView(arrangedSubviews: [addMemoLabel])
        addMemoStack.axis = .vertical
        addMemoStack.alignment = .center
        addMemoStack.isLayoutMarginsRelativeArrangement = true
        addMemoStack.layoutMargins = UIEdgeInsets(hMargin: 0, vMargin: 12)
        addMemoStack.isUserInteractionEnabled = true
        addMemoStack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapAddMemo)))

        let vSpacerFactory = VSpacerFactory()

        let keyboardViews = buildKeyboard(vSpacerFactory: vSpacerFactory)

        let amountButtons = buildAmountButtons()

        let requiredViews = [
            bigAmountRow,
            smallAmountLabel,
            addMemoStack,
            amountButtons,
            balanceLabel
        ] + keyboardViews.keyboardRows
        for requiredView in requiredViews {
            requiredView.setCompressionResistanceVerticalHigh()
            requiredView.setContentHuggingHigh()
        }

        rootStack.removeAllSubviews()
        rootStack.addArrangedSubviews([
            vSpacerFactory.buildVSpacer(),
            bigAmountRow,
            vSpacerFactory.buildVSpacer(),
            smallAmountLabel,
            vSpacerFactory.buildVSpacer(),
            addMemoStack,
            vSpacerFactory.buildVSpacer()
        ] +
        keyboardViews.allRows
        + [
            vSpacerFactory.buildVSpacer(),
            amountButtons,
            vSpacerFactory.buildVSpacer(),
            balanceLabel
        ])

        vSpacerFactory.finalizeSpacers()

        UIView.matchHeightsOfViews(keyboardViews.keyboardRows)
    }

    struct KeyboardViews {
        let allRows: [UIView]
        let keyboardRows: [UIView]
    }

    private func buildKeyboard(vSpacerFactory: VSpacerFactory) -> KeyboardViews {

        let keyboardHSpacing: CGFloat = 25
        let buttonFont = UIFont.ows_dynamicTypeTitle1Clamped
        func buildAmountKeyboardButton(title: String, block: @escaping () -> Void) -> OWSButton {
            // PAYMENTS TODO: Highlight down state?
            let button = OWSButton(block: block)

            let label = UILabel()
            label.text = title
            label.font = buttonFont
            label.textColor = Theme.primaryTextColor
            button.addSubview(label)
            label.autoCenterInSuperview()

            return button
        }
        func buildAmountKeyboardButton(imageName: String, block: @escaping () -> Void) -> OWSButton {
            // PAYMENTS TODO: Highlight down state?
            let button = OWSButton(imageName: imageName,
                                   tintColor: Theme.primaryTextColor,
                                   block: block)
            return button
        }
        var keyboardRows = [UIView]()
        let buildAmountKeyboardRow = { (buttons: [OWSButton]) -> UIView in

            let buttons = buttons.map { (button) -> UIView in
                button.autoPinToAspectRatio(with: CGSize(width: 1, height: 1))
                let buttonSize = buttonFont.lineHeight * 2.0
                button.autoSetDimension(.height, toSize: buttonSize)

                let downStateView = OWSLayerView.circleView()
                button.downStateView = downStateView
                button.sendSubviewToBack(downStateView)
                downStateView.autoPinEdgesToSuperviewEdges()
                downStateView.backgroundColor = (Theme.isDarkThemeEnabled
                                                    ? UIColor.ows_gray90
                                                    : UIColor.ows_gray02)

                let buttonWrapper = UIView.container()
                buttonWrapper.addSubview(button)
                button.autoPinEdge(toSuperviewEdge: .top)
                button.autoPinEdge(toSuperviewEdge: .bottom)
                button.autoHCenterInSuperview()
                button.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
                button.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

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

        // Don't localize; use Arabic numeral literals.
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
            vSpacerFactory.buildVSpacer(),
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
            vSpacerFactory.buildVSpacer(),
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
            vSpacerFactory.buildVSpacer(),
            buildAmountKeyboardRow([
                buildAmountKeyboardButton(imageName: "decimal-32") { [weak self] in
                    self?.keyboardPressedPeriod()
                },
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
        let requestButton = buildBottomButton(title: NSLocalizedString("PAYMENTS_NEW_PAYMENT_REQUEST_BUTTON",
                                                                       comment: "Label for the 'new payment request' button."),
                                              target: self,
                                              selector: #selector(didTapRequestButton))
        let payButton = buildBottomButton(title: NSLocalizedString("PAYMENTS_NEW_PAYMENT_PAY_BUTTON",
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
        rootStack.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        rootStack.isLayoutMarginsRelativeArrangement = true
        view.addSubview(rootStack)
        rootStack.autoPinEdge(toSuperviewMargin: .leading)
        rootStack.autoPinEdge(toSuperviewMargin: .trailing)
        rootStack.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: rootStack, avoidNotch: true)

        bigAmountLabel.font = UIFont.ows_dynamicTypeLargeTitle1Clamped.withSize(60)
        bigAmountLabel.textAlignment = .center
        bigAmountLabel.adjustsFontSizeToFitWidth = true
        bigAmountLabel.minimumScaleFactor = 0.25
        bigAmountLabel.setContentHuggingVerticalHigh()
        bigAmountLabel.setCompressionResistanceVerticalHigh()

        smallAmountLabel.font = UIFont.ows_dynamicTypeBody2
        smallAmountLabel.textAlignment = .center
        smallAmountLabel.setContentHuggingVerticalHigh()
        smallAmountLabel.setCompressionResistanceVerticalHigh()
    }

    private func updateAmountLabels() {

        func disableSmallLabel() {
            smallAmountLabel.text = NSLocalizedString("PAYMENTS_NEW_PAYMENT_INVALID_AMOUNT",
                                                      comment: "Label for the 'invalid amount' button.")
            smallAmountLabel.textColor = UIColor.ows_accentRed
        }

        bigAmountLabel.attributedText = amount.formatForDisplayAttributed(withSpace: false)

        switch amount {
        case .mobileCoin:
            if let otherCurrencyAmount = self.otherCurrencyAmount {
                smallAmountLabel.attributedText = otherCurrencyAmount.formatForDisplayAttributed(withSpace: true)
            } else if let currencyConversion = currentCurrencyConversion,
                      let fiatCurrencyAmount = currencyConversion.convertToFiatCurrency(paymentAmount: parsedPaymentAmount),
                      let fiatString = PaymentsImpl.attributedFormat(fiatCurrencyAmount: fiatCurrencyAmount,
                                                                     currencyCode: currencyConversion.currencyCode,
                                                                     withSpace: true) {
                smallAmountLabel.attributedText = fiatString
            } else {
                disableSmallLabel()
            }
        case .fiatCurrency(_, let currencyConversion):
            if let otherCurrencyAmount = self.otherCurrencyAmount {
                smallAmountLabel.attributedText = otherCurrencyAmount.formatForDisplayAttributed(withSpace: true)
            } else {
                let paymentAmount = currencyConversion.convertFromFiatCurrencyToMOB(amount.asDouble)
                smallAmountLabel.attributedText = PaymentsImpl.attributedFormat(paymentAmount: paymentAmount,
                                                                                withSpace: true)
            }
        }
    }

    private func updateBalanceLabel() {
        SendPaymentHelper.updateBalanceLabel(balanceLabel)
    }

    private func showInvalidAmountAlert() {
        let errorMessage = NSLocalizedString("PAYMENTS_NEW_PAYMENT_INVALID_AMOUNT",
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
               let fiatString = PaymentsImpl.formatAsDoubleString(fiatCurrencyAmount) {
                // Store the otherCurrencyAmount.
                Logger.verbose("fiatCurrencyAmount: \(fiatCurrencyAmount)")
                Logger.verbose("fiatString: \(fiatString)")
                Logger.flush()
                amounts.set(currentAmount: .fiatCurrency(inputString: InputString.forString(fiatString, isFiat: true),
                                                         currencyConversion: currencyConversion),
                            otherCurrencyAmount: self.amount)
            } else {
                owsFailDebug("Could not switch to fiat currency.")
                resetContents()
            }
        case .fiatCurrency(_, let currencyConversion):
            let paymentAmount = currencyConversion.convertFromFiatCurrencyToMOB(amount.asDouble)
            if let mobString = PaymentsImpl.formatAsDoubleString(picoMob: paymentAmount.picoMob) {
                // Store the otherCurrencyAmount.
                amounts.set(currentAmount: .mobileCoin(inputString: InputString.forString(mobString, isFiat: false)),
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

    private var actionSheet: SendPaymentCompletionActionSheet?

    @objc
    func didTapPayButton(_ sender: UIButton) {
        let paymentAmount = parsedPaymentAmount
        guard paymentAmount.picoMob > 0 else {
            showInvalidAmountAlert()
            return
        }
        getEstimatedFeeAndSubmit(paymentAmount: paymentAmount)
    }

    private func getEstimatedFeeAndSubmit(paymentAmount: TSPaymentAmount) {
        ModalActivityIndicatorViewController.presentAsInvisible(fromViewController: self) { modalActivityIndicator in
            firstly {
                Self.paymentsSwift.getEstimatedFee(forPaymentAmount: paymentAmount)
            }.done { (estimatedFeeAmount: TSPaymentAmount) in
                AssertIsOnMainThread()

                modalActivityIndicator.dismiss {
                    self.showPaymentCompletionUI(paymentAmount: paymentAmount,
                                                 estimatedFeeAmount: estimatedFeeAmount)
                }
            }.catch { error in
                AssertIsOnMainThread()
                owsFailDebug("Error: \(error)")

                modalActivityIndicator.dismiss {
                    AssertIsOnMainThread()

                    // TODO: Copy.
                    OWSActionSheets.showErrorAlert(message: NSLocalizedString("PAYMENTS_ERROR_COULD_NOT_ESTIMATE_FEE",
                                                                              comment: "Error message indicating that the estimated fee for a payment could not be determined."))
                }
            }
        }
    }

    private func showPaymentCompletionUI(paymentAmount: TSPaymentAmount,
                                         estimatedFeeAmount: TSPaymentAmount) {
        // Snapshot the conversion rate.
        let currencyConversion = self.currentCurrencyConversion

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
}

// MARK: -

extension SendPaymentViewController: SendPaymentMemoViewDelegate {
    public func didChangeMemo(memoMessage: String?) {
        self.memoMessage = memoMessage
    }
}

// MARK: - Payment Keyboard

fileprivate extension SendPaymentViewController {

    private func keyboardPressedNumeral(_ numeralString: String) {
        let inputString = amount.inputString.append(.digit(digit: numeralString))
        updateAmountString(inputString)
    }

    private func keyboardPressedPeriod() {
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
            amounts.set(currentAmount: .mobileCoin(inputString: inputString),
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
        case .mobileCoin:
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
    public func didSendPayment() {
        let delegate = self.delegate
        self.dismiss(animated: true) {
            delegate?.didSendPayment()
        }
    }
}

// MARK: - Amount

private enum Amount {
    // inputString should be a raw double strings: e.g. 123456.789.
    // It should not be formatted: e.g. 123,456.789
    case mobileCoin(inputString: InputString)
    case fiatCurrency(inputString: InputString, currencyConversion: CurrencyConversionInfo)

    var isFiat: Bool {
        switch self {
        case .mobileCoin:
            return false
        case .fiatCurrency:
            return true
        }
    }

    var inputString: InputString {
        switch self {
        case .mobileCoin(let inputString):
            return inputString
        case .fiatCurrency(let inputString, _):
            return inputString
        }
    }

    var asDouble: Double {
        inputString.asDouble
    }

    var formatForDisplay: String {
        switch self {
        case .mobileCoin:
            guard let mobString = PaymentsImpl.format(mob: asDouble) else {
                owsFailDebug("Couldn't format MOB string: \(inputString.asString)")
                return inputString.asString
            }
            return mobString
        case .fiatCurrency:
            guard let fiatString = PaymentsImpl.format(fiatCurrencyAmount: asDouble,
                                                       minimumFractionDigits: 0) else {
                owsFailDebug("Couldn't format fiat string: \(inputString.asString)")
                return inputString.asString
            }
            return fiatString
        }
    }

    func formatForDisplayAttributed(withSpace: Bool) -> NSAttributedString {
        switch self {
        case .mobileCoin:
            return PaymentsImpl.attributedFormat(mobileCoinString: formatForDisplay,
                                                 withSpace: withSpace)
        case .fiatCurrency(_, let currencyConversion):
            return PaymentsImpl.attributedFormat(currencyString: formatForDisplay,
                                                 currencyCode: currencyConversion.currencyCode,
                                                 withSpace: withSpace)
        }
    }
}

// MARK: -

private protocol AmountsDelegate: class {
    func amountDidChange(oldValue: Amount, newValue: Amount)
}

// MARK: -

private class Amounts {
    weak var delegate: AmountsDelegate?

    private static var defaultMCAmount: Amount {
        .mobileCoin(inputString: InputString.defaultString(isFiat: false))
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

private enum InputChar: Equatable {
    case digit(digit: String)
    case decimal

    var asString: String {
        switch self {
        case .digit(let digit):
            return digit
        case .decimal:
            return "."
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
        guard let stringValue = PaymentsImpl.formatAsDoubleString(value) else {
            owsFailDebug("Couldn't format double: \(value)")
            return Self.defaultString(isFiat: isFiat)
        }
        return forString(stringValue, isFiat: isFiat)
    }

    static func forString(_ stringValue: String, isFiat: Bool) -> InputString {
        var result = InputString.defaultString(isFiat: isFiat)
        for char in stringValue {
            let charString = String(char)
            if charString == InputChar.decimal.asString {
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
        Logger.info("Before: \(self.asString), \(self.digitCountBeforeDecimal), \(self.digitCountAfterDecimal), \(result.asDouble)")
        Logger.info("Considering: \(result.asString), \(result.digitCountBeforeDecimal), \(result.digitCountAfterDecimal), \(result.asDouble)")
        guard result.isValid else {
            Logger.warn("Invalid result: \(self.asString) -> \(result.asString)")
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

    var digitCountBeforeDecimal: UInt {
        var result: UInt = 0
        for char in chars {
            switch char {
            case .digit:
                result += 1
            case .decimal:
                return result
            }
        }
        return result
    }

    var digitCountAfterDecimal: UInt {
        var result: UInt = 0
        var hasPassedDecimal = false
        for char in chars {
            switch char {
            case .digit:
                if hasPassedDecimal {
                    result += 1
                }
            case .decimal:
                hasPassedDecimal = true
            }
        }
        return result
    }

    var hasDecimal: Bool {
        !Array(chars.filter { $0 == .decimal }).isEmpty
    }

    var asString: String {
        chars.map { $0.asString }.joined()
    }

    var asDouble: Double {
        Self.parseAsDouble(asString)
    }

    private static func parseAsDouble(_ stringValue: String) -> Double {
        guard let value = Double(stringValue.ows_stripped()) else {
            // inputString should be parsable at all times.
            owsFailDebug("Invalid inputString.")
            return 0
        }
        return value
    }
}

// MARK: -

// This view's contents must adapt to a wide variety of form factors.
// We use vertical spacers of equal height to ensure the layout is
// both responsive and balanced.
class VSpacerFactory {
    private var spacers = [UIView]()

    func buildVSpacer() -> UIView {
        let spacer = UIView.container()
        spacer.setContentHuggingVerticalLow()
        spacers.append(spacer)
        return spacer
    }

    func finalizeSpacers() {
        UIView.matchHeightsOfViews(spacers)
    }
}
