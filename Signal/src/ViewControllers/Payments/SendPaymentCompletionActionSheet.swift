//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

@MainActor
protocol SendPaymentCompletionDelegate: AnyObject {
    func didSendPayment(success: Bool)
}

// MARK: -

class SendPaymentCompletionActionSheet: ActionSheetController, SendPaymentHelperDelegate {

    typealias PaymentInfo = SendPaymentInfo
    typealias RequestInfo = SendRequestInfo

    weak var delegate: SendPaymentCompletionDelegate?

    enum Mode {
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
    }

    private var currentStep: Step {
        didSet {
            if self.isViewLoaded {
                updateContentsForMode()
            }
        }
    }

    private let contentStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        return stackView
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancel()
            },
        )
        button.configuration?.title = CommonStrings.cancelButton
        button.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBodyClamped)
        button.configuration?.contentInsets.leading = 0
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    private let paymentInfoContainerView = UIView.container()

    private lazy var payButton = UIButton(
        configuration: .largePrimary(title: OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_CONFIRM_PAYMENT_BUTTON",
            comment: "Label for the 'confirm payment' button.",
        )),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapConfirmButton()
        },
    )

    private lazy var payButtonContainerView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = .buttonContainerLayoutMargins
        view.addSubview(payButton)
        payButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            payButton.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            payButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            payButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            payButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])
        return view
    }()

    private lazy var balanceLabel = SendPaymentHelper.buildBottomLabel()

    private lazy var balanceLabelContainerView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = .init(margin: 8)
        view.addSubview(balanceLabel)
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            balanceLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            balanceLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            balanceLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            balanceLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])
        return view
    }()

    private var helper: SendPaymentHelper?

    private var currentCurrencyConversion: CurrencyConversionInfo? { helper?.currentCurrencyConversion }

    // MARK: - UIViewController

    init(mode: Mode, delegate: SendPaymentCompletionDelegate) {
        self.mode = mode
        self.delegate = delegate

        // TODO: Add support for requests.
        switch mode {
        case .payment(let paymentInfo):
            currentStep = .confirmPay(paymentInfo: paymentInfo)
        }

        super.init()

        helper = SendPaymentHelper(delegate: self)
        isCancelable = true
    }

    func present(fromViewController: UIViewController) {
        fromViewController.presentFormSheet(self, animated: true)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        // Header
        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_CONFIRM_PAYMENT_TITLE",
            comment: "Title for the 'confirm payment' ui in the 'send payment' UI.",
        )
        titleLabel.font = .dynamicTypeHeadlineClamped
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        let headerView = UIView()
        headerView.addSubview(cancelButton)
        headerView.addSubview(titleLabel)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: headerView.layoutMarginsGuide.topAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: headerView.layoutMarginsGuide.centerYAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: headerView.layoutMarginsGuide.leadingAnchor),

            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.layoutMarginsGuide.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: headerView.layoutMarginsGuide.centerXAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.layoutMarginsGuide.trailingAnchor),
        ])
        contentStack.addArrangedSubview(headerView)
        contentStack.setCustomSpacing(16, after: headerView)

        contentStack.addArrangedSubview(paymentInfoContainerView)
        contentStack.setCustomSpacing(32, after: paymentInfoContainerView)

        contentStack.addArrangedSubview(payButtonContainerView)

        updateBalanceLabel()
        contentStack.addArrangedSubview(balanceLabelContainerView)

        customHeader = contentStack

        // Try to optimistically prepare a payment before
        // user approves it to reduce perceived latency
        // when sending outgoing payments.
        if let paymentInfo = mode.paymentInfo {
            tryToPreparePayment(paymentInfo: paymentInfo)
        } else {
            owsFailDebug("Missing paymentInfo.")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContentsForMode()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // For now, the design only allows for portrait layout on non-iPads
        if !UIDevice.current.isIPad, view.window?.windowScene?.interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.isIPad ? .all : .portrait
    }

    // MARK: - UI configuration

    private func updateContentsForMode() {
        switch currentStep {
        case .confirmPay(let paymentInfo):
            updateContentsForConfirmPay(paymentInfo: paymentInfo)
        case .progressPay(let paymentInfo):
            updateContentsForProgressPay(paymentInfo: paymentInfo)
        case .successPay(let paymentInfo):
            updateContentsForSuccessPay(paymentInfo: paymentInfo)
        case .failurePay(let paymentInfo, let error):
            updateContentsForFailurePay(paymentInfo: paymentInfo, error: error)
        }
    }

    // Rebuilds and replaces whole payment info view.
    private func updatePaymentInfoView(paymentInfo: PaymentInfo) {
        paymentInfoContainerView.removeAllSubviews()

        let paymentInfoView = buildConfirmPaymentRows(paymentInfo: paymentInfo)
        paymentInfoContainerView.addSubview(paymentInfoView)
        paymentInfoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            paymentInfoView.topAnchor.constraint(equalTo: paymentInfoContainerView.topAnchor),
            paymentInfoView.leadingAnchor.constraint(equalTo: paymentInfoContainerView.leadingAnchor),
            paymentInfoView.trailingAnchor.constraint(equalTo: paymentInfoContainerView.trailingAnchor),
            paymentInfoView.bottomAnchor.constraint(equalTo: paymentInfoContainerView.bottomAnchor),
        ])
    }

    // Removes all animation view displayed instead of Pay button and make Pay button visible.
    private func showPayButton() {
        payButton.isHidden = false

        for subview in payButtonContainerView.subviews {
            guard subview !== payButton else { continue }
            subview.removeFromSuperview()
        }

    }

    // Hide Pay button and show an animation view instead.
    private func showAnimationView(_ animationView: LottieAnimationView, size: CGSize) {
        payButton.isHidden = true

        for subview in payButtonContainerView.subviews {
            guard subview !== payButton else { continue }
            subview.removeFromSuperview()
        }

        payButtonContainerView.addSubview(animationView)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animationView.widthAnchor.constraint(equalToConstant: size.width),
            animationView.heightAnchor.constraint(equalToConstant: size.height),
            animationView.centerXAnchor.constraint(equalTo: payButtonContainerView.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: payButtonContainerView.centerYAnchor),
        ])
    }

    // Removes error message (if any) and makes balance label visible.
    private func showBalanceLabel() {
        balanceLabel.isHidden = false

        for subview in balanceLabelContainerView.subviews {
            guard subview !== balanceLabel else { continue }
            subview.removeFromSuperview()
        }
    }

    // Hide balance label and show an error text in its place.
    private func replaceBalanceWithErrorMessage(_ message: String) {
        balanceLabel.isHidden = true

        for subview in balanceLabelContainerView.subviews {
            guard subview !== balanceLabel else { continue }
            subview.removeFromSuperview()
        }

        let errorLabel = SendPaymentHelper.buildBottomLabel()
        errorLabel.text = message
        errorLabel.numberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        balanceLabelContainerView.addSubview(errorLabel)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorLabel.topAnchor.constraint(equalTo: balanceLabelContainerView.layoutMarginsGuide.topAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: balanceLabelContainerView.layoutMarginsGuide.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: balanceLabelContainerView.layoutMarginsGuide.trailingAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: balanceLabelContainerView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func updateContentsForConfirmPay(paymentInfo: PaymentInfo) {
        cancelButton.isEnabled = true

        updatePaymentInfoView(paymentInfo: paymentInfo)

        showPayButton()

        showBalanceLabel()
    }

    private func updateContentsForProgressPay(paymentInfo: PaymentInfo) {
        cancelButton.isEnabled = false

        updatePaymentInfoView(paymentInfo: paymentInfo)

        let animationName = Theme.isDarkThemeEnabled ? "payments_spinner_dark" : "payments_spinner"
        let animationView = LottieAnimationView(name: animationName)
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.loopMode = .loop
        animationView.contentMode = .scaleAspectFit
        animationView.play()
        showAnimationView(animationView, size: .square(48))

        replaceBalanceWithErrorMessage(OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_PROCESSING",
            comment: "Indicator that a new payment is being processed in the 'send payment' UI.",
        ))
    }

    private func updateContentsForSuccessPay(paymentInfo: PaymentInfo) {
        cancelButton.isEnabled = false

        updatePaymentInfoView(paymentInfo: paymentInfo)

        let animationView = LottieAnimationView(name: "payments_spinner_success")
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        animationView.play()
        showAnimationView(animationView, size: .square(48))

        replaceBalanceWithErrorMessage(CommonStrings.doneButton)
    }

    private func updateContentsForFailurePay(paymentInfo: PaymentInfo, error: Error) {
        cancelButton.isEnabled = false

        updatePaymentInfoView(paymentInfo: paymentInfo)

        let animationView = LottieAnimationView(name: "payments_spinner_fail")
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        animationView.play()
        showAnimationView(animationView, size: .square(48))

        replaceBalanceWithErrorMessage(Self.formatPaymentFailure(error, withErrorPrefix: true))
    }

    private func buildConfirmPaymentRows(paymentInfo: PaymentInfo) -> UIView {

        @discardableResult
        func addRow(
            to group: inout [UIView],
            titleView: UILabel,
            valueView: UILabel,
            titleIconView: UIView? = nil,
        ) -> UIView {
            valueView.setCompressionResistanceHorizontalHigh()
            valueView.setContentHuggingHorizontalHigh()

            let subviews: [UIView]
            if let titleIconView {
                subviews = [titleView, titleIconView, UIView.hStretchingSpacer(), valueView]
            } else {
                subviews = [titleView, valueView]
            }

            let row = UIStackView(arrangedSubviews: subviews)
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 8
            row.backgroundColor = .Signal.secondaryGroupedBackground
            row.translatesAutoresizingMaskIntoConstraints = false
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = .init(margin: 18)

            group.append(row)

            return row
        }

        @discardableResult
        func addRow(
            to group: inout [UIView],
            title: String,
            value: String,
            titleIconView: UIView? = nil,
            isTotal: Bool = false,
        ) -> UIView {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .dynamicTypeBodyClamped
            titleLabel.textColor = .Signal.label
            titleLabel.lineBreakMode = .byTruncatingTail

            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.adjustsFontSizeToFitWidth = true
            if isTotal {
                valueLabel.font = .dynamicTypeHeadlineClamped
                valueLabel.textColor = .Signal.label
            } else {
                valueLabel.font = .dynamicTypeBodyClamped
                valueLabel.textColor = .Signal.secondaryLabel
            }

            return addRow(
                to: &group,
                titleView: titleLabel,
                valueView: valueLabel,
                titleIconView: titleIconView,
            )
        }

        // Top group: Receiver, Amount, Fee.
        var topGroup = [UIView]()
        let recipientDescription = recipientDescriptionWithSneakyTransaction(paymentInfo: paymentInfo)
        addRow(
            to: &topGroup,
            title: recipientDescription,
            value: SendPaymentHelper.formatMobileCoinAmount(paymentInfo.paymentAmount),
        )

        if let currencyConversion = paymentInfo.currencyConversion {
            if
                let fiatAmountString = PaymentsFormat.formatAsFiatCurrency(
                    paymentAmount: paymentInfo.paymentAmount,
                    currencyConversionInfo: currencyConversion,
                )
            {
                let fiatFormat = OWSLocalizedString(
                    "PAYMENTS_NEW_PAYMENT_FIAT_CONVERSION_FORMAT",
                    comment: "Format for the 'fiat currency conversion estimate' indicator. Embeds {{ the fiat currency code }}.",
                )

                let currencyConversionInfoView = UIImageView.withTemplateImageName("info-compact", tintColor: .Signal.secondaryLabel)
                currencyConversionInfoView.autoSetDimensions(to: .square(16))
                currencyConversionInfoView.setCompressionResistanceHigh()

                let row = addRow(
                    to: &topGroup,
                    title: String.nonPluralLocalizedStringWithFormat(fiatFormat, currencyConversion.currencyCode),
                    value: fiatAmountString,
                    titleIconView: currencyConversionInfoView,
                )

                row.isUserInteractionEnabled = true
                row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCurrencyConversionInfo)))
            } else {
                owsFailDebug("Could not convert to fiat.")
            }
        }

        addRow(
            to: &topGroup,
            title: OWSLocalizedString(
                "PAYMENTS_NEW_PAYMENT_ESTIMATED_FEE",
                comment: "Label for the 'payment estimated fee' indicator.",
            ),
            value: SendPaymentHelper.formatMobileCoinAmount(paymentInfo.estimatedFeeAmount),
        )

        // Bottom group (of 1): Total
        var bottomGroup = [UIView]()
        let totalAmount = paymentInfo.paymentAmount.plus(paymentInfo.estimatedFeeAmount)
        addRow(
            to: &bottomGroup,
            title: OWSLocalizedString(
                "PAYMENTS_NEW_PAYMENT_PAYMENT_TOTAL",
                comment: "Label for the 'total payment amount' indicator.",
            ),
            value: SendPaymentHelper.formatMobileCoinAmount(totalAmount),
            isTotal: true,
        )

        let groups: [UIStackView] = [topGroup, bottomGroup].map { subviews in
            UIStackView.makeGroupedStyle(views: subviews)
        }

        let stack = UIStackView(arrangedSubviews: groups)
        stack.axis = .vertical
        stack.spacing = 24

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
            otherUserName = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                SSKEnvironment.shared.contactManagerRef.displayName(for: recipientAddress, tx: transaction).resolvedValue()
            }
        case .publicAddress(let recipientPublicAddress):
            otherUserName = PaymentsImpl.formatAsBase58(publicAddress: recipientPublicAddress)
        }
        let userFormat = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_RECIPIENT_AMOUNT_FORMAT",
            comment: "Format for the 'payment recipient amount' indicator. Embeds {{ the name of the recipient of the payment }}.",
        )
        return String.nonPluralLocalizedStringWithFormat(userFormat, otherUserName)
    }

    static func formatPaymentFailure(_ error: Error, withErrorPrefix: Bool) -> String {
        let errorDescription: String = {
            switch error {
            case let paymentsError as PaymentsError:
                switch paymentsError {
                case .insufficientFunds:
                    if let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance {
                        let formattedBalance = PaymentsFormat.format(
                            paymentAmount: paymentBalance.amount,
                            isShortForm: false,
                        )
                        let format = OWSLocalizedString(
                            "PAYMENTS_NEW_PAYMENT_ERROR_INSUFFICIENT_FUNDS_FORMAT",
                            comment: "Indicates that a payment failed due to insufficient funds. Embeds {{ current balance }}.",
                        )
                        return String.nonPluralLocalizedStringWithFormat(format, formattedBalance)
                    } else {
                        return OWSLocalizedString(
                            "PAYMENTS_NEW_PAYMENT_ERROR_INSUFFICIENT_FUNDS",
                            comment: "Indicates that a payment failed due to insufficient funds.",
                        )
                    }
                case .outgoingVerificationTakingTooLong:
                    return OWSLocalizedString(
                        "PAYMENTS_NEW_PAYMENT_ERROR_OUTGOING_VERIFICATION_TAKING_TOO_LONG",
                        comment: "Indicates that an outgoing payment could not be verified in a timely way.",
                    )
                case .timeout,
                     .connectionFailure,
                     .serverRateLimited,
                     .authorizationFailure,
                     .invalidServerResponse,
                     .attestationVerificationFailed:
                    return OWSLocalizedString(
                        "PAYMENTS_NEW_PAYMENT_ERROR_CONNECTIVITY_FAILURE",
                        comment: "Indicates that a payment failed due to a connectivity failure.",
                    )
                case .outdatedClient:
                    return OWSLocalizedString(
                        "PAYMENTS_NEW_PAYMENT_ERROR_OUTDATED_CLIENT",
                        comment: "Indicates that a payment failed due to an outdated client.",
                    )
                case .userHasNoPublicAddress,
                     .invalidCurrency,
                     .invalidAmount,
                     .invalidFee,
                     .invalidModel,
                     .invalidInput:
                    return OWSLocalizedString(
                        "PAYMENTS_NEW_PAYMENT_ERROR_INVALID_TRANSACTION",
                        comment: "Indicates that a payment failed due to being invalid.",
                    )
                default:
                    return OWSLocalizedString(
                        "PAYMENTS_NEW_PAYMENT_ERROR_UNKNOWN",
                        comment: "Indicates that an unknown error occurred while sending a payment or payment request.",
                    )
                }
            case let paymentsError as PaymentsUIError:
                switch paymentsError {
                case .paymentsLockFailed:
                    return OWSLocalizedString(
                        "PAYMENTS_NEW_PAYMENT_ERROR_PAYMENTS_LOCK_AUTH_FAILURE",
                        comment: "Indicates that a payment failed because the payments lock failed to authenticate.",
                    )
                case .paymentsLockCancelled:
                    return OWSLocalizedString(
                        "PAYMENTS_NEW_PAYMENT_ERROR_PAYMENTS_LOCK_AUTH_CANCELLED",
                        comment: "Indicates that a payment failed because the payments lock attempt was cancelled.",
                    )
                }
            default:
                return OWSLocalizedString(
                    "PAYMENTS_NEW_PAYMENT_ERROR_UNKNOWN",
                    comment: "Indicates that an unknown error occurred while sending a payment or payment request.",
                )
            }
        }()

        guard withErrorPrefix else {
            return errorDescription
        }
        // We don't use error prefixes for now.
        return errorDescription
    }

    private func updateBalanceLabel() {
        helper?.updateBalanceLabel(balanceLabel)
    }

    // MARK: - Payment Processing.

    private let preparedPaymentTask = AtomicOptional<Task<PreparedPayment, any Error>>(nil, lock: .init())

    private func tryToPreparePayment(paymentInfo: PaymentInfo) {
        let preparePaymentTask = Task {
            // NOTE: We should not pre-prepare a payment if defragmentation
            // is required.
            return try await SUIEnvironment.shared.paymentsSwiftRef.prepareOutgoingPayment(
                recipient: paymentInfo.recipient,
                paymentAmount: paymentInfo.paymentAmount,
                memoMessage: paymentInfo.memoMessage,
                isOutgoingTransfer: paymentInfo.isOutgoingTransfer,
                canDefragment: false,
            )
        }
        preparedPaymentTask.set(preparePaymentTask)
        Task {
            do {
                _ = try await preparePaymentTask.value
                Logger.info("Pre-prepared payment ready.")
            } catch {
                if case PaymentsError.defragmentationRequired = error {
                    Logger.warn("Error: \(error)")
                } else {
                    owsFailDebugUnlessMCNetworkFailure(error)
                }
            }
        }
    }

    private func tryToSendPayment(paymentInfo: PaymentInfo) {
        currentStep = .progressPay(paymentInfo: paymentInfo)

        ModalActivityIndicatorViewController.present(fromViewController: self, isInvisible: true, asyncBlock: { modalActivityIndicator in
            do {
                let authOutcome = await SSKEnvironment.shared.owsPaymentsLockRef.tryToUnlock()
                switch authOutcome {
                case .failure(let error):
                    throw PaymentsUIError.paymentsLockFailed(reason: "local authentication failed with error: \(error)")
                case .unexpectedFailure(let error):
                    throw PaymentsUIError.paymentsLockFailed(reason: "local authentication failed with unexpected error: \(error)")
                case .success:
                    break
                case .cancel:
                    throw PaymentsUIError.paymentsLockCancelled(reason: "local authentication cancelled")
                case .disabled:
                    break
                }

                guard let task = self.preparedPaymentTask.get() else {
                    throw OWSAssertionError("Missing preparedPaymentTask.")
                }
                let preparedPayment: PreparedPayment
                do {
                    preparedPayment = try await task.value
                } catch PaymentsError.defragmentationRequired {
                    // NOTE: We will always follow this code path if defragmentation
                    // is required.
                    Logger.info("Defragmentation required.")
                    preparedPayment = try await SUIEnvironment.shared.paymentsSwiftRef.prepareOutgoingPayment(
                        recipient: paymentInfo.recipient,
                        paymentAmount: paymentInfo.paymentAmount,
                        memoMessage: paymentInfo.memoMessage,
                        isOutgoingTransfer: paymentInfo.isOutgoingTransfer,
                        canDefragment: true,
                    )
                }

                let paymentModel = try await SUIEnvironment.shared.paymentsSwiftRef.initiateOutgoingPayment(preparedPayment: preparedPayment)

                // Try to wait (with a timeout) for submission and verification to complete.
                let blockInterval: TimeInterval = .minute
                do {
                    try await withCooperativeTimeout(seconds: blockInterval) {
                        _ = try await SUIEnvironment.shared.paymentsSwiftRef.blockOnOutgoingVerification(paymentModel: paymentModel)
                    }
                } catch is CooperativeTimeoutError {
                    throw PaymentsError.outgoingVerificationTakingTooLong
                } catch let error as PaymentsError where error.isNetworkFailureOrTimeout {
                    Logger.warn("Could not verify outgoing payment: \(error).")
                    // This is fine.
                }

                self.didSucceedPayment(paymentInfo: paymentInfo)
                modalActivityIndicator.dismiss()
            } catch {
                owsFailDebugUnlessMCNetworkFailure(error)
                modalActivityIndicator.dismiss()
                self.didFailPayment(paymentInfo: paymentInfo, error: error)
            }
        })
    }

    private static let autoDismissDelay: TimeInterval = 2.5

    private func didSucceedPayment(paymentInfo: PaymentInfo) {
        currentStep = .successPay(paymentInfo: paymentInfo)

        let delegate = self.delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                delegate?.didSendPayment(success: true)
            }
        }
    }

    private func didFailPayment(paymentInfo: PaymentInfo, error: Error) {
        currentStep = .failurePay(paymentInfo: paymentInfo, error: error)

        let delegate = self.delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                PaymentActionSheets.showBiometryAuthFailedActionSheet { _ in
                    delegate?.didSendPayment(success: false)
                }
            }
        }
    }

    // MARK: - Events

    private func didTapCancel() {
        dismiss(animated: true, completion: nil)
    }

    private func didTapConfirmButton() {
        switch currentStep {
        case .confirmPay(let paymentInfo):
            tryToSendPayment(paymentInfo: paymentInfo)
        default:
            owsFailDebug("Invalid step.")
        }
    }

    @objc
    private func didTapCurrencyConversionInfo() {
        PaymentsSettingsViewController.showCurrencyConversionInfoAlert(fromViewController: self)
    }

    // MARK: - SendPaymentHelperDelegate

    func balanceDidChange() {
        updateBalanceLabel()
    }

    func currencyConversionDidChange() {}
}

private extension UIStackView {
    static func makeGroupedStyle(views: [UIView]) -> UIStackView {
        // Add separators to all except the last view
        views.enumerated().forEach { offset, value in
            guard offset != views.count - 1 else { return }
            let separator = UIView()
            separator.backgroundColor = UIColor.Signal.opaqueSeparator
            separator.autoSetDimension(.height, toSize: 0.5)
            value.addSubview(separator)

            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: value.leadingAnchor, constant: CGFloat(16)),
                separator.trailingAnchor.constraint(equalTo: value.trailingAnchor),
                separator.bottomAnchor.constraint(equalTo: value.bottomAnchor),
            ])

        }

        let group = UIStackView(arrangedSubviews: views)
        group.axis = .vertical
        group.alignment = .fill
        group.spacing = 0
        group.layer.cornerRadius = 10
        group.clipsToBounds = true
        return group
    }
}
