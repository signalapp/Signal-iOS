//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol PaymentsCurrencies: AnyObject {

    // Expressed as a ratio:
    //
    // price of fiat currency / price of payment currency (MobileCoin)
    typealias CurrencyConversionRate = Double

    var currentCurrencyCode: Currency.Code { get }

    func setCurrentCurrencyCode(_ currencyCode: Currency.Code, transaction: SDSAnyWriteTransaction)

    func updateConversationRatesIfStale()

    func warmCaches()
}

// MARK: -

public protocol PaymentsCurrenciesSwift: PaymentsCurrencies {

    var preferredCurrencyInfos: [Currency.Info] { get }

    var supportedCurrencyInfos: [Currency.Info] { get }

    var supportedCurrencyInfosWithCurrencyConversions: [Currency.Info] { get }

    func conversionInfo(forCurrencyCode currencyCode: Currency.Code) -> CurrencyConversionInfo?
}

// MARK: -

public struct CurrencyConversionInfo {
    public let currencyCode: Currency.Code
    public let name: String
    // Don't use this field; use convertToFiatCurrency() instead.
    private let conversionRate: PaymentsCurrencies.CurrencyConversionRate
    // How fresh is this conversion info?
    public let conversionDate: Date

    public init(currencyCode: Currency.Code,
                name: String,
                conversionRate: PaymentsCurrencies.CurrencyConversionRate,
                conversionDate: Date) {
        self.currencyCode = currencyCode
        self.name = name
        self.conversionRate = conversionRate
        self.conversionDate = conversionDate
    }

    public func convertToFiatCurrency(paymentAmount: TSPaymentAmount) -> Double? {
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Unknown currency: \(paymentAmount.currency).")
            return nil
        }
        let mob = PaymentsConstants.convertPicoMobToMob(paymentAmount.picoMob)
        return conversionRate * mob
    }

    public func convertFromFiatCurrencyToMOB(_ value: Double) -> TSPaymentAmount {
        guard value >= 0 else {
            owsFailDebug("Invalid amount: \(value).")
            return TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
        }
        let mob = value / conversionRate
        let picoMob = PaymentsConstants.convertMobToPicoMob(mob)
        return TSPaymentAmount(currency: .mobileCoin, picoMob: picoMob)
    }

    public var asCurrencyInfo: Currency.Info {
        Currency.Info(code: currencyCode, name: name)
    }

    public static func areEqual(_ left: CurrencyConversionInfo?,
                                _ right: CurrencyConversionInfo?) -> Bool {
        return (left?.currencyCode == right?.currencyCode &&
                    left?.conversionRate == right?.conversionRate)
    }
}

// MARK: -

public class MockPaymentsCurrencies: NSObject, PaymentsCurrenciesSwift, PaymentsCurrencies {

    public let currentCurrencyCode: Currency.Code = PaymentsConstants.currencyCodeGBP

    public func setCurrentCurrencyCode(_ currencyCode: Currency.Code, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func warmCaches() {}

    public let preferredCurrencyInfos: [Currency.Info] = []

    public let supportedCurrencyInfos: [Currency.Info] = []

    public let supportedCurrencyInfosWithCurrencyConversions: [Currency.Info] = []

    public func updateConversationRatesIfStale() {}

    public func conversionInfo(forCurrencyCode currencyCode: Currency.Code) -> CurrencyConversionInfo? {
        return nil
    }
}
