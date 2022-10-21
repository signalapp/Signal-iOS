//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

public struct SendPaymentInfo {
    let recipient: SendPaymentRecipient
    let paymentAmount: TSPaymentAmount
    let estimatedFeeAmount: TSPaymentAmount
    let currencyConversion: CurrencyConversionInfo?
    // TODO: Add support for requests.
    let paymentRequestModel: TSPaymentRequestModel?
    let memoMessage: String?
    let isOutgoingTransfer: Bool
}

// MARK: -

// TODO: Add support for requests.
public struct SendRequestInfo {
    let recipientAddress: SignalServiceAddress
    let paymentAmount: TSPaymentAmount
    let estimatedFeeAmount: TSPaymentAmount
    let currencyConversion: CurrencyConversionInfo?
    let memoMessage: String?
}

// MARK: -

protocol SendPaymentHelperDelegate: AnyObject {
    func balanceDidChange()
    func currencyConversionDidChange()
}

// MARK: -

class SendPaymentHelper: Dependencies {

    private weak var delegate: SendPaymentHelperDelegate?

    private var _currentCurrencyConversion: CurrencyConversionInfo?
    public var currentCurrencyConversion: CurrencyConversionInfo? {
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

    required init(delegate: SendPaymentHelperDelegate) {
        self.delegate = delegate

        addObservers()

        updateCurrentCurrencyConversion()
        updateMaximumPaymentAmount()
    }

    private func addObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(currentPaymentBalanceDidChange),
            name: PaymentsImpl.currentPaymentBalanceDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(paymentConversionRatesDidChange),
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
            object: nil
        )
    }

    public func refreshObservedValues() {
        updateCurrentCurrencyConversion()

        Self.paymentsSwift.updateCurrentPaymentBalance()
        paymentsCurrencies.updateConversationRatesIfStale()
    }

    public static let minTopVSpacing: CGFloat = 16

    public static let vSpacingAboveBalance: CGFloat = 20

    public static func buildBottomButton(title: String,
                                         target: Any,
                                         selector: Selector) -> UIView {
        let button = OWSFlatButton.button(title: title,
                                          font: bottomButtonFont,
                                          titleColor: .white,
                                          backgroundColor: .ows_accentBlue,
                                          target: target,
                                          selector: selector)
        button.autoSetHeightUsingFont()
        return button
    }

    public static func buildBottomButtonStack(_ subviews: [UIView]) -> UIView {
        let buttonStack = UIStackView(arrangedSubviews: subviews)
        buttonStack.axis = .horizontal
        buttonStack.spacing = 20
        buttonStack.distribution = .fillEqually
        buttonStack.alignment = .center
        buttonStack.autoSetDimension(.height, toSize: bottomControlHeight)
        return buttonStack
    }

    public static let progressIndicatorSize: CGFloat = 48

    // To avoid layout jitter, all of the "bottom controls"
    // (buttons, progress indicator, error indicator) occupy
    // the same exact height.
    public static var bottomControlHeight: CGFloat {
        max(progressIndicatorSize,
            OWSFlatButton.heightForFont(bottomButtonFont))
    }

    public static var bottomButtonFont: UIFont {
        UIFont.ows_dynamicTypeBody.ows_semibold
    }

    public static func buildBottomLabel() -> UILabel {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody2Clamped
        label.textColor = Theme.secondaryTextAndIconColor
        label.textAlignment = .center
        return label
    }

    public func updateBalanceLabel(_ balanceLabel: UILabel) {

        guard let maximumPaymentAmount = self.maximumPaymentAmount else {
            // Use whitespace to ensure that the height of the label
            // is constant, avoiding layout jitter.
            balanceLabel.text = " "
            return
        }

        let format = NSLocalizedString("PAYMENTS_NEW_PAYMENT_BALANCE_FORMAT",
                                       comment: "Format for the 'balance' indicator. Embeds {{ the current payments balance }}.")
        balanceLabel.text = String(format: format,
                                   Self.formatMobileCoinAmount(maximumPaymentAmount))
    }

    private func updateMaximumPaymentAmount() {
        firstly {
            Self.paymentsSwift.maximumPaymentAmount()
        }.done(on: .main) { [weak self] maximumPaymentAmount in
            guard let self = self else { return }
            self.maximumPaymentAmount = maximumPaymentAmount
            self.delegate?.balanceDidChange()
        }.catch(on: .global()) { [weak self] error in
            if case PaymentsError.insufficientFunds = error {
                guard let self = self else { return }
                self.maximumPaymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
                self.delegate?.balanceDidChange()
            } else {
                owsFailDebugUnlessMCNetworkFailure(error)
            }
        }

        delegate?.balanceDidChange()
    }

    @objc
    private func currentPaymentBalanceDidChange() {
        delegate?.balanceDidChange()

        updateMaximumPaymentAmount()
    }

    @objc
    private func paymentConversionRatesDidChange() {
        updateCurrentCurrencyConversion()
    }

    private func updateCurrentCurrencyConversion() {
        let localCurrencyCode = paymentsCurrencies.currentCurrencyCode
        let currentCurrencyConversion = paymentsCurrenciesSwift.conversionInfo(forCurrencyCode: localCurrencyCode)
        guard !CurrencyConversionInfo.areEqual(currentCurrencyConversion,
                                               self.currentCurrencyConversion) else {
            // Did not change.
            return
        }
        self.currentCurrencyConversion = currentCurrencyConversion
        delegate?.currencyConversionDidChange()
    }

    public static func formatMobileCoinAmount(_ paymentAmount: TSPaymentAmount) -> String {
        owsAssertDebug(paymentAmount.isValidAmount(canBeEmpty: true))
        owsAssertDebug(paymentAmount.currency == .mobileCoin)
        owsAssertDebug(paymentAmount.picoMob >= 0)

        let formattedAmount = PaymentsFormat.format(paymentAmount: paymentAmount,
                                                    isShortForm: false)
        let format = NSLocalizedString("PAYMENTS_NEW_PAYMENT_CURRENCY_FORMAT",
                                       comment: "Format for currency amounts in the 'send payment' UI. Embeds {{ %1$@ the current payments balance, %2$@ the currency indicator }}.")
        return String(format: format,
                      formattedAmount,
                      PaymentsConstants.mobileCoinCurrencyIdentifier)
    }
}

// MARK: 

extension SendPaymentHelperDelegate {
    var minTopVSpacing: CGFloat { SendPaymentHelper.minTopVSpacing }

    var vSpacingAboveBalance: CGFloat { SendPaymentHelper.vSpacingAboveBalance }

    var bottomControlHeight: CGFloat { SendPaymentHelper.bottomControlHeight }

    func buildBottomButtonStack(_ subviews: [UIView]) -> UIView {
        SendPaymentHelper.buildBottomButtonStack(subviews)
    }

    func buildBottomButton(title: String, target: Any, selector: Selector) -> UIView {
        SendPaymentHelper.buildBottomButton(title: title, target: target, selector: selector)
    }

    func buildBottomLabel() -> UILabel {
        SendPaymentHelper.buildBottomLabel()
    }

    func formatMobileCoinAmount(_ paymentAmount: TSPaymentAmount) -> String {
        SendPaymentHelper.formatMobileCoinAmount(paymentAmount)
    }
}
