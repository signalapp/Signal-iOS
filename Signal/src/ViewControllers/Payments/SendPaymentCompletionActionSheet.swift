//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SignalMessaging
import UIKit

@objc
public protocol SendPaymentCompletionDelegate {
    func didSendPayment()
}

// MARK: -

@objc
public class SendPaymentCompletionActionSheet: ActionSheetController {

    public typealias PaymentInfo = SendPaymentInfo
    public typealias RequestInfo = SendRequestInfo

    @objc
    public weak var delegate: SendPaymentCompletionDelegate?

    public enum Mode {
        case payment(paymentInfo: PaymentInfo)
        // TODO: Add support for requests.
        // case request(requestInfo: RequestInfo)

        var paymentInfo: PaymentInfo? {
            switch self {
            case .payment(let paymentInfo):
                return paymentInfo
            }
        }
    }

    private let mode: Mode

    private enum Step {
        case confirmPay(paymentInfo: PaymentInfo)
        case progressPay(paymentInfo: PaymentInfo)
        case successPay(paymentInfo: PaymentInfo)
        case failurePay(paymentInfo: PaymentInfo, error: Error)
        // TODO: Add support for requests.
        //        case confirmRequest(paymentAmount: TSPaymentAmount,
        //                            currencyConversion: CurrencyConversionInfo?)
        //        case failureRequest
    }

    private var currentStep: Step {
        didSet {
            if self.isViewLoaded {
                updateContentsForMode()
            }
        }
    }

    private let outerStack = UIStackView()

    private let innerStack = UIStackView()

    private let headerStack = UIStackView()

    private let balanceLabel = SendPaymentHelper.buildBottomLabel()

    private var outerBackgroundView: UIView?

    private var helper: SendPaymentHelper?

    private var currentCurrencyConversion: CurrencyConversionInfo? { helper?.currentCurrencyConversion }

    public required init(mode: Mode, delegate: SendPaymentCompletionDelegate) {
        self.mode = mode
        self.delegate = delegate

        // TODO: Add support for requests.
        switch mode {
        case .payment(let paymentInfo):
            currentStep = .confirmPay(paymentInfo: paymentInfo)
        }

        super.init(theme: .default)

        helper = SendPaymentHelper(delegate: self)
    }

    @objc
    public func present(fromViewController: UIViewController) {
        self.customHeader = outerStack
        self.isCancelable = true
        fromViewController.presentFormSheet(self, animated: true)
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        createSubviews()

        helper?.refreshObservedValues()

        // Try to optimistically prepare a payment before
        // user approves it to reduce perceived latency
        // when sending outgoing payments.
        if let paymentInfo = mode.paymentInfo {
            tryToPreparePayment(paymentInfo: paymentInfo)
        } else {
            owsFailDebug("Missing paymentInfo.")
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContentsForMode()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad && CurrentAppContext().interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }

        helper?.refreshObservedValues()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateContentsForMode()
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.isIPad ? .all : .portrait
    }

    private func createSubviews() {

        outerStack.axis = .vertical
        outerStack.alignment = .fill
        outerBackgroundView = outerStack.addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)

        innerStack.axis = .vertical
        innerStack.alignment = .fill
        innerStack.layoutMargins = UIEdgeInsets(top: 32, leading: 20, bottom: 22, trailing: 20)
        innerStack.isLayoutMarginsRelativeArrangement = true

        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.distribution = .equalSpacing
        headerStack.layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        headerStack.isLayoutMarginsRelativeArrangement = true

        outerStack.addArrangedSubview(headerStack)
        outerStack.addArrangedSubview(innerStack)
    }

    private func updateContentsForMode() {

        outerBackgroundView?.backgroundColor = Theme.actionSheetBackgroundColor

        switch currentStep {
        case .confirmPay(let paymentInfo):
            updateContentsForConfirmPay(paymentInfo: paymentInfo)
        case .progressPay(let paymentInfo):
            updateContentsForProgressPay(paymentInfo: paymentInfo)
        case .successPay(let paymentInfo):
            updateContentsForSuccessPay(paymentInfo: paymentInfo)
        case .failurePay(let paymentInfo, let error):
            updateContentsForFailurePay(paymentInfo: paymentInfo, error: error)
        // TODO: Add support for requests.
        //        case .confirmRequest:
        //            // TODO: Payment requests
        //            owsFailDebug("Requests not yet supported.")
        //        case .failureRequest:
        //            owsFailDebug("Requests not yet supported.")
        }
    }

    private func setContents(_ subviews: [UIView]) {
        AssertIsOnMainThread()

        innerStack.removeAllSubviews()
        for subview in subviews {
            innerStack.addArrangedSubview(subview)
        }
    }

    private func updateHeader(canCancel: Bool) {
        AssertIsOnMainThread()

        headerStack.removeAllSubviews()

        let cancelLabel = UILabel()
        cancelLabel.text = CommonStrings.cancelButton
        cancelLabel.font = UIFont.ows_dynamicTypeBodyClamped
        if canCancel {
            cancelLabel.textColor = Theme.primaryTextColor
            cancelLabel.isUserInteractionEnabled = true
            cancelLabel.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                    action: #selector(didTapCancel)))
        } else {
            cancelLabel.textColor = Theme.secondaryTextAndIconColor
        }
        cancelLabel.setCompressionResistanceHigh()
        cancelLabel.setContentHuggingHigh()

        let titleLabel = UILabel()
        // TODO: Add support for requests.
        titleLabel.text = NSLocalizedString("PAYMENTS_NEW_PAYMENT_CONFIRM_PAYMENT_TITLE",
                                            comment: "Title for the 'confirm payment' ui in the 'send payment' UI.")
        titleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        let spacer = UIView.container()
        spacer.setCompressionResistanceHigh()
        spacer.setContentHuggingHigh()

        headerStack.addArrangedSubview(cancelLabel)
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(spacer)

        // We use the spacer to balance the layout.
        spacer.autoMatch(.width, to: .width, of: cancelLabel)
    }

    private func updateContentsForConfirmPay(paymentInfo: PaymentInfo) {
        AssertIsOnMainThread()

        updateHeader(canCancel: true)

        updateBalanceLabel()

        setContents([
            buildConfirmPaymentRows(paymentInfo: paymentInfo),
            UIView.spacer(withHeight: 32),
            buildConfirmPaymentButtons(),
            UIView.spacer(withHeight: vSpacingAboveBalance),
            balanceLabel
        ])
    }

    private func updateContentsForProgressPay(paymentInfo: PaymentInfo) {
        AssertIsOnMainThread()

        updateHeader(canCancel: false)

        let animationName = (Theme.isDarkThemeEnabled
                                ? "payments_spinner_dark"
                                : "payments_spinner")
        let animationView = AnimationView(name: animationName)
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.loopMode = .loop
        animationView.contentMode = .scaleAspectFit
        animationView.play()
        animationView.autoSetDimensions(to: .square(48))

        // To void layout jitter, we use a label
        // that occupies exactly the same height.
        let bottomLabel = buildBottomLabel()
        bottomLabel.text = NSLocalizedString("PAYMENTS_NEW_PAYMENT_PROCESSING",
                                             comment: "Indicator that a new payment is being processed in the 'send payment' UI.")

        setContents([
            buildConfirmPaymentRows(paymentInfo: paymentInfo),
            UIView.spacer(withHeight: 32),
            // To void layout jitter, this view replaces the "bottom button"
            // in the layout, exactly matching its height.
            wrapBottomControl(animationView),
            UIView.spacer(withHeight: vSpacingAboveBalance),
            bottomLabel
        ])
    }

    private func updateContentsForSuccessPay(paymentInfo: PaymentInfo) {
        AssertIsOnMainThread()

        updateHeader(canCancel: false)

        let animationView = AnimationView(name: "payments_spinner_success")
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        animationView.play()
        animationView.autoSetDimensions(to: .square(48))

        // To void layout jitter, we use a label
        // that occupies exactly the same height.
        let bottomLabel = buildBottomLabel()
        bottomLabel.text = CommonStrings.doneButton

        setContents([
            buildConfirmPaymentRows(paymentInfo: paymentInfo),
            UIView.spacer(withHeight: 32),
            // To void layout jitter, this view replaces the "bottom button"
            // in the layout, exactly matching its height.
            wrapBottomControl(animationView),
            UIView.spacer(withHeight: vSpacingAboveBalance),
            bottomLabel
        ])
    }

    private func wrapBottomControl(_ bottomControl: UIView) -> UIView {
        let bottomStack = UIStackView(arrangedSubviews: [bottomControl])
        bottomStack.axis = .vertical
        bottomStack.alignment = .center
        bottomStack.distribution = .equalCentering
        // To void layout jitter, this view replaces the "bottom button"
        // in the layout, exactly matching its height.
        bottomStack.autoSetDimension(.height, toSize: bottomControlHeight)
        return bottomStack
    }

    private func updateContentsForFailurePay(paymentInfo: PaymentInfo, error: Error) {
        AssertIsOnMainThread()

        updateHeader(canCancel: false)

        let animationView = AnimationView(name: "payments_spinner_fail")
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        animationView.play()
        animationView.autoSetDimensions(to: .square(48))

        // To void layout jitter, we use an empty placeholder label
        // that occupies the exact same height
        let bottomLabel = buildBottomLabel()
        bottomLabel.text = Self.formatPaymentFailure(error, withErrorPrefix: true)

        setContents([
            buildConfirmPaymentRows(paymentInfo: paymentInfo),
            UIView.spacer(withHeight: 32),
            // To void layout jitter, this view replaces the "bottom button"
            // in the layout, exactly matching its height.
            wrapBottomControl(animationView),
            UIView.spacer(withHeight: vSpacingAboveBalance),
            bottomLabel
        ])
    }

    private func buildConfirmPaymentRows(paymentInfo: PaymentInfo) -> UIView {

        var rows = [UIView]()

        @discardableResult
        func addRow(titleView: UIView,
                    valueView: UIView,
                    titleIconView: UIView? = nil) -> UIView {

            valueView.setCompressionResistanceHorizontalHigh()
            valueView.setContentHuggingHorizontalHigh()

            let subviews: [UIView]
            if let titleIconView = titleIconView {
                subviews = [titleView, titleIconView, UIView.hStretchingSpacer(), valueView]
            } else {
                subviews = [titleView, valueView]
            }

            let row = UIStackView(arrangedSubviews: subviews)
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 8

            rows.append(row)
            return row
        }

        @discardableResult
        func addRow(title: String,
                    value: String,
                    titleIconView: UIView? = nil,
                    isTotal: Bool = false) -> UIView {

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .ows_dynamicTypeBodyClamped
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.lineBreakMode = .byTruncatingTail

            let valueLabel = UILabel()
            valueLabel.text = value
            if isTotal {
                valueLabel.font = .ows_dynamicTypeTitle2Clamped
                valueLabel.textColor = Theme.primaryTextColor
            } else {
                valueLabel.font = .ows_dynamicTypeBodyClamped
                valueLabel.textColor = Theme.secondaryTextAndIconColor
            }

            return addRow(titleView: titleLabel,
                          valueView: valueLabel,
                          titleIconView: titleIconView)
        }

        let recipientDescription = recipientDescriptionWithSneakyTransaction(paymentInfo: paymentInfo)
        addRow(title: recipientDescription,
               value: formatMobileCoinAmount(paymentInfo.paymentAmount))

        if let currencyConversion = paymentInfo.currencyConversion {
            if let fiatAmountString = PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentInfo.paymentAmount,
                                                                        currencyConversionInfo: currencyConversion) {
                let fiatFormat = NSLocalizedString("PAYMENTS_NEW_PAYMENT_FIAT_CONVERSION_FORMAT",
                                                   comment: "Format for the 'fiat currency conversion estimate' indicator. Embeds {{ the fiat currency code }}.")

                let currencyConversionInfoView = UIImageView.withTemplateImageName("info-outline-24",
                                                                                   tintColor: Theme.secondaryTextAndIconColor)
                currencyConversionInfoView.autoSetDimensions(to: .square(16))
                currencyConversionInfoView.setCompressionResistanceHigh()

                let row = addRow(title: String(format: fiatFormat, currencyConversion.currencyCode),
                                 value: fiatAmountString,
                                 titleIconView: currencyConversionInfoView)

                row.isUserInteractionEnabled = true
                row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCurrencyConversionInfo)))
            } else {
                owsFailDebug("Could not convert to fiat.")
            }
        }

        addRow(title: NSLocalizedString("PAYMENTS_NEW_PAYMENT_ESTIMATED_FEE",
                                        comment: "Label for the 'payment estimated fee' indicator."),
               value: formatMobileCoinAmount(paymentInfo.estimatedFeeAmount))

        let separator = UIView()
        separator.backgroundColor = Theme.hairlineColor
        separator.autoSetDimension(.height, toSize: 1)
        let separatorRow = UIStackView(arrangedSubviews: [separator])
        separatorRow.axis = .horizontal
        separatorRow.alignment = .center
        separatorRow.distribution = .fill
        rows.append(separatorRow)

        let totalAmount = paymentInfo.paymentAmount.plus(paymentInfo.estimatedFeeAmount)
        addRow(title: NSLocalizedString("PAYMENTS_NEW_PAYMENT_PAYMENT_TOTAL",
                                        comment: "Label for the 'total payment amount' indicator."),
               value: formatMobileCoinAmount(totalAmount),
               isTotal: true)

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16

        UIView.matchHeightsOfViews(rows)

        return stack
    }

    private func recipientDescriptionWithSneakyTransaction(paymentInfo: PaymentInfo) -> String {
        guard let recipient = paymentInfo.recipient as? SendPaymentRecipientImpl else {
            owsFailDebug("Invalid recipient.")
            return ""
        }
        let otherUserName: String
        switch recipient {
        case .address(let recipientAddress):
            otherUserName = databaseStorage.read { transaction in
                self.contactsManager.displayName(for: recipientAddress, transaction: transaction)
            }
        case .publicAddress(let recipientPublicAddress):
            otherUserName = PaymentsImpl.formatAsBase58(publicAddress: recipientPublicAddress)
        }
        let userFormat = NSLocalizedString("PAYMENTS_NEW_PAYMENT_RECIPIENT_AMOUNT_FORMAT",
                                           comment: "Format for the 'payment recipient amount' indicator. Embeds {{ the name of the recipient of the payment }}.")
        return String(format: userFormat, otherUserName)
    }

    public static func formatPaymentFailure(_ error: Error, withErrorPrefix: Bool) -> String {
        let errorDescription: String = {
            switch error {
            case let paymentsError as PaymentsError:
                switch paymentsError {
                case .insufficientFunds:
                    if let paymentBalance = self.paymentsSwift.currentPaymentBalance {
                        let formattedBalance = PaymentsFormat.format(paymentAmount: paymentBalance.amount,
                                                                     isShortForm: false)
                        let format = NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_INSUFFICIENT_FUNDS_FORMAT",
                                                       comment: "Indicates that a payment failed due to insufficient funds. Embeds {{ current balance }}.")
                        return String(format: format, formattedBalance)
                    } else {
                        return NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_INSUFFICIENT_FUNDS",
                                                 comment: "Indicates that a payment failed due to insufficient funds.")
                    }
                case .outgoingVerificationTakingTooLong:
                    return NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_OUTGOING_VERIFICATION_TAKING_TOO_LONG",
                                             comment: "Indicates that an outgoing payment could not be verified in a timely way.")
                case .timeout,
                     .connectionFailure,
                     .serverRateLimited,
                     .authorizationFailure,
                     .invalidServerResponse,
                     .attestationVerificationFailed:
                    return NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_CONNECTIVITY_FAILURE",
                                             comment: "Indicates that a payment failed due to a connectivity failure.")
                case .outdatedClient:
                    return NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_OUTDATED_CLIENT",
                                             comment: "Indicates that a payment failed due to an outdated client.")
                case .userHasNoPublicAddress,
                     .invalidCurrency,
                     .invalidAmount,
                     .invalidFee,
                     .invalidModel,
                     .invalidInput:
                    return NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_INVALID_TRANSACTION",
                                             comment: "Indicates that a payment failed due to being invalid.")
                default:
                    return NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_UNKNOWN",
                                             comment: "Indicates that an unknown error occurred while sending a payment or payment request.")
                }
            default:
                return NSLocalizedString("PAYMENTS_NEW_PAYMENT_ERROR_UNKNOWN",
                                                     comment: "Indicates that an unknown error occurred while sending a payment or payment request.")
            }
        }()

        guard withErrorPrefix else {
            return errorDescription
        }
        // We don't use error prefixes for now.
        return errorDescription
    }

    private func buildConfirmPaymentButtons() -> UIView {
        buildBottomButtonStack([
            buildBottomButton(title: NSLocalizedString("PAYMENTS_NEW_PAYMENT_CONFIRM_PAYMENT_BUTTON",
                                                       comment: "Label for the 'confirm payment' button."),
                              target: self,
                              selector: #selector(didTapConfirmButton))
        ])
    }

    @objc
    public func updateBalanceLabel() {
        guard let helper = helper else {
            Logger.verbose("Missing helper.")
            return
        }
        helper.updateBalanceLabel(balanceLabel)
    }

    private let preparedPaymentPromise = AtomicOptional<Promise<PreparedPayment>>(nil)

    private func tryToPreparePayment(paymentInfo: PaymentInfo) {
        let promise: Promise<PreparedPayment> = firstly(on: .global()) { () -> Promise<PreparedPayment> in
            // NOTE: We should not pre-prepare a payment if defragmentation
            // is required.
            Self.paymentsSwift.prepareOutgoingPayment(recipient: paymentInfo.recipient,
                                                      paymentAmount: paymentInfo.paymentAmount,
                                                      memoMessage: paymentInfo.memoMessage,
                                                      paymentRequestModel: paymentInfo.paymentRequestModel,
                                                      isOutgoingTransfer: paymentInfo.isOutgoingTransfer,
                                                      canDefragment: false)
        }

        preparedPaymentPromise.set(promise)

        firstly {
            promise
        }.done(on: .global()) { (_: PreparedPayment) in
            Logger.info("Pre-prepared payment ready.")
        }.catch(on: .global()) { error in
            if case PaymentsError.defragmentationRequired = error {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebugUnlessMCNetworkFailure(error)
            }
        }
    }

    private func tryToSendPayment(paymentInfo: PaymentInfo) {

        self.currentStep = .progressPay(paymentInfo: paymentInfo)

        ModalActivityIndicatorViewController.presentAsInvisible(fromViewController: self) { [weak self] modalActivityIndicator in
            guard let self = self else { return }

            firstly(on: .global()) { () -> Promise<PreparedPayment> in
                guard let promise = self.preparedPaymentPromise.get() else {
                    throw OWSAssertionError("Missing preparedPaymentPromise.")
                }
                return firstly(on: .global()) { () -> Promise<PreparedPayment> in
                    return promise
                }.recover(on: .global()) { (error: Error) -> Promise<PreparedPayment> in
                    if case PaymentsError.defragmentationRequired = error {
                        // NOTE: We will always follow this code path if defragmentation
                        // is required.
                        Logger.info("Defragmentation required.")
                        return Self.paymentsSwift.prepareOutgoingPayment(recipient: paymentInfo.recipient,
                                                                         paymentAmount: paymentInfo.paymentAmount,
                                                                         memoMessage: paymentInfo.memoMessage,
                                                                         paymentRequestModel: paymentInfo.paymentRequestModel,
                                                                         isOutgoingTransfer: paymentInfo.isOutgoingTransfer,
                                                                         canDefragment: true)

                    } else {
                        throw error
                    }
                }
            }.then(on: .global()) { (preparedPayment: PreparedPayment) in
                Self.paymentsSwift.initiateOutgoingPayment(preparedPayment: preparedPayment)
            }.then { (paymentModel: TSPaymentModel) -> Promise<Void> in
                // Try to wait (with a timeout) for submission and verification to complete.
                let blockInterval: TimeInterval = kSecondInterval * 60
                return firstly(on: .global()) { () -> Promise<Void> in
                    Self.paymentsSwift.blockOnOutgoingVerification(paymentModel: paymentModel).asVoid()
                }.timeout(seconds: blockInterval, description: "Payments Verify Submission") {
                    PaymentsError.outgoingVerificationTakingTooLong
                }.recover(on: .global()) { (error: Error) -> Guarantee<()> in
                    Logger.warn("Could not verify outgoing payment: \(error).")
                    if let paymentsError = error as? PaymentsError,
                       paymentsError.isNetworkFailureOrTimeout {
                        return Guarantee.value(())
                    } else {
                        throw error
                    }
                }
            }.done { _ in
                AssertIsOnMainThread()

                self.didSucceedPayment(paymentInfo: paymentInfo)

                modalActivityIndicator.dismiss {}
            }.catch { error in
                AssertIsOnMainThread()
                owsFailDebugUnlessMCNetworkFailure(error)

                self.didFailPayment(paymentInfo: paymentInfo, error: error)

                modalActivityIndicator.dismiss {}
            }
        }
    }

    private static let autoDismissDelay: TimeInterval = 2.5

    private func didSucceedPayment(paymentInfo: PaymentInfo) {
        self.currentStep = .successPay(paymentInfo: paymentInfo)

        let delegate = self.delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay) { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                delegate?.didSendPayment()
            }
        }
    }

    private func didFailPayment(paymentInfo: PaymentInfo, error: Error) {
        self.currentStep = .failurePay(paymentInfo: paymentInfo, error: error)

        let delegate = self.delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay) { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                delegate?.didSendPayment()
            }
        }
    }

    // TODO: Add support for requests.
    private func tryToSendPaymentRequest(requestInfo: RequestInfo) {

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] modalActivityIndicator in
            guard let self = self else { return }

            firstly {
                PaymentsImpl.sendPaymentRequestMessagePromise(address: requestInfo.recipientAddress,
                                                              paymentAmount: requestInfo.paymentAmount,
                                                              memoMessage: requestInfo.memoMessage)
            }.done { _ in
                AssertIsOnMainThread()

                modalActivityIndicator.dismiss {
                    self.dismiss(animated: true)
                }
            }.catch { error in
                AssertIsOnMainThread()
                owsFailDebug("Error: \(error)")

                // TODO: Add support for requests.
                // self.currentStep = .failureRequest

                modalActivityIndicator.dismiss {}
            }
        }
    }

    // MARK: - Events

    @objc
    func didTapCancel() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func didTapConfirmButton(_ sender: UIButton) {
        switch currentStep {
        case .confirmPay(let paymentInfo):
            tryToSendPayment(paymentInfo: paymentInfo)
        // TODO: Add support for requests.
        //        case .confirmRequest(let paymentAmount, _):
        //            tryToSendPaymentRequest(paymentAmount)
        default:
            owsFailDebug("Invalid step.")
        }
    }

    @objc
    private func didTapCurrencyConversionInfo() {
        PaymentsSettingsViewController.showCurrencyConversionInfoAlert(fromViewController: self)
    }
}

// MARK: -

extension SendPaymentCompletionActionSheet: SendPaymentHelperDelegate {
    public func balanceDidChange() {}

    public func currencyConversionDidChange() {}
}
