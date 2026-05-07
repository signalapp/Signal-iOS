//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

struct SendPaymentInfo {
    let recipient: SendPaymentRecipient
    let paymentAmount: TSPaymentAmount
    let estimatedFeeAmount: TSPaymentAmount
    let currencyConversion: CurrencyConversionInfo?
    let memoMessage: String?
    let isOutgoingTransfer: Bool
}

// MARK: -

// TODO: Add support for requests.
struct SendRequestInfo {
    let recipientAddress: SignalServiceAddress
    let paymentAmount: TSPaymentAmount
    let estimatedFeeAmount: TSPaymentAmount
    let currencyConversion: CurrencyConversionInfo?
    let memoMessage: String?
}

// MARK: -

@MainActor
protocol SendPaymentHelperDelegate: AnyObject {
    func balanceDidChange()
    func currencyConversionDidChange()
}

// MARK: -

@MainActor
class SendPaymentHelper {

    private weak var delegate: SendPaymentHelperDelegate?

    private var _currentCurrencyConversion: CurrencyConversionInfo?
    var currentCurrencyConversion: CurrencyConversionInfo? {
        get {
            AssertIsOnMainThread()
            return _currentCurrencyConversion
        }
        set {
            AssertIsOnMainThread()
            _currentCurrencyConversion = newValue
        }
    }

    private var maximumPaymentAmount: TSPaymentAmount?

    init(delegate: SendPaymentHelperDelegate) {
        self.delegate = delegate

        addObservers()

        updateCurrentCurrencyConversion()
        updateMaximumPaymentAmount()
    }

    deinit {
        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    private var observations = [NotificationCenter.Observer]()

    private func addObservers() {
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsImpl.currentPaymentBalanceDidChange,
        ) { [weak self] _ in
            self?.currentPaymentBalanceDidChange()
        })
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
        ) { [weak self] _ in
            self?.paymentConversionRatesDidChange()
        })
    }

    func refreshObservedValues() {
        updateCurrentCurrencyConversion()

        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
        SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()
    }

    static let progressIndicatorSize: CGFloat = 48

    static func buildBottomLabel() -> UILabel {
        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        return label
    }

    func updateBalanceLabel(_ balanceLabel: UILabel) {
        guard let maximumPaymentAmount else {
            // Use whitespace to ensure that the height of the label
            // is constant, avoiding layout jitter.
            balanceLabel.text = " "
            return
        }

        let format = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_BALANCE_FORMAT",
            comment: "Format for the 'balance' indicator. Embeds {{ the current payments balance }}.",
        )
        balanceLabel.text = String.nonPluralLocalizedStringWithFormat(
            format,
            Self.formatMobileCoinAmount(maximumPaymentAmount),
        )
    }

    private func updateMaximumPaymentAmount() {
        Task { @MainActor [weak self] in
            do {
                let maximumPaymentAmount = try await SUIEnvironment.shared.paymentsSwiftRef.maximumPaymentAmount()
                self?.maximumPaymentAmount = maximumPaymentAmount
                self?.delegate?.balanceDidChange()
            } catch PaymentsError.insufficientFunds {
                self?.maximumPaymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
                self?.delegate?.balanceDidChange()
            } catch {
                owsFailDebugUnlessMCNetworkFailure(error)
            }
        }

        delegate?.balanceDidChange()
    }

    private func currentPaymentBalanceDidChange() {
        delegate?.balanceDidChange()

        updateMaximumPaymentAmount()
    }

    private func paymentConversionRatesDidChange() {
        updateCurrentCurrencyConversion()
    }

    private func updateCurrentCurrencyConversion() {
        let localCurrencyCode = SSKEnvironment.shared.paymentsCurrenciesRef.currentCurrencyCode
        let currentCurrencyConversion = SSKEnvironment.shared.paymentsCurrenciesRef.conversionInfo(forCurrencyCode: localCurrencyCode)
        guard
            !CurrencyConversionInfo.areEqual(
                currentCurrencyConversion,
                self.currentCurrencyConversion,
            )
        else {
            // Did not change.
            return
        }
        self.currentCurrencyConversion = currentCurrencyConversion
        delegate?.currencyConversionDidChange()
    }

    static func formatMobileCoinAmount(_ paymentAmount: TSPaymentAmount) -> String {
        owsAssertDebug(paymentAmount.isValidAmount(canBeEmpty: true))
        owsAssertDebug(paymentAmount.currency == .mobileCoin)
        owsAssertDebug(paymentAmount.picoMob >= 0)

        let formattedAmount = PaymentsFormat.format(
            paymentAmount: paymentAmount,
            isShortForm: false,
        )
        let format = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_CURRENCY_FORMAT",
            comment: "Format for currency amounts in the 'send payment' UI. Embeds {{ %1$@ the current payments balance, %2$@ the currency indicator }}.",
        )
        return String.nonPluralLocalizedStringWithFormat(
            format,
            formattedAmount,
            PaymentsConstants.mobileCoinCurrencyIdentifier,
        )
    }
}
