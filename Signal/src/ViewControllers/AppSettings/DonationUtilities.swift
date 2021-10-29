//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit
import SignalCoreKit

public class DonationUtilities: NSObject {
    static var isApplePayAvailable: Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks)
    }

    static let supportedNetworks: [PKPaymentNetwork] = [
        .visa,
        .masterCard,
        .amex,
        .discover,
        .JCB,
        .interac
    ]
    
    public enum Symbol: Equatable {
        case before(String)
        case after(String)
        case currencyCode
    }
    
    public struct Presets {
        struct Preset {
            let symbol: Symbol
            let amounts: [UInt]
        }

        static let presets: [Currency.Code: Preset] = [
            "USD": Preset(symbol: .before("$"), amounts: [3, 5, 10, 20, 50, 100]),
            "AUD": Preset(symbol: .before("A$"), amounts: [5, 10, 15, 25, 65, 125]),
            "BRL": Preset(symbol: .before("R$"), amounts: [15, 25, 50, 100, 250, 525]),
            "GBP": Preset(symbol: .before("£"), amounts: [3, 5, 10, 15, 35, 70]),
            "CAD": Preset(symbol: .before("CA$"), amounts: [5, 10, 15, 25, 60, 125]),
            "CNY": Preset(symbol: .before("CN¥"), amounts: [20, 35, 65, 130, 320, 650]),
            "EUR": Preset(symbol: .before("€"), amounts: [3, 5, 10, 15, 40, 80]),
            "HKD": Preset(symbol: .before("HK$"), amounts: [25, 40, 80, 150, 400, 775]),
            "INR": Preset(symbol: .before("₹"), amounts: [100, 200, 300, 500, 1_000, 5_000]),
            "JPY": Preset(symbol: .before("¥"), amounts: [325, 550, 1_000, 2_200, 5_500, 11_000]),
            "KRW": Preset(symbol: .before("₩"), amounts: [3_500, 5_500, 11_000, 22_500, 55_500, 100_000]),
            "PLN": Preset(symbol: .after("zł"), amounts: [10, 20, 40, 75, 150, 375]),
            "SEK": Preset(symbol: .after("kr"), amounts: [25, 50, 75, 150, 400, 800]),
            "CHF": Preset(symbol: .currencyCode, amounts: [3, 5, 10, 20, 50, 100])
        ]

        static func symbol(for code: Currency.Code) -> Symbol {
            presets[code]?.symbol ?? .currencyCode
        }
    }
    
    static func formatCurrency(_ value: NSDecimalNumber, currencyCode: Currency.Code, includeSymbol: Bool = true) -> String {
        let isZeroDecimalCurrency = Stripe.zeroDecimalCurrencyCodes.contains(currencyCode)

        let decimalPlaces: Int
        if isZeroDecimalCurrency {
            decimalPlaces = 0
        } else if value.doubleValue == Double(value.intValue) {
            decimalPlaces = 0
        } else {
            decimalPlaces = 2
        }
        
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .decimal
        currencyFormatter.minimumFractionDigits = decimalPlaces
        currencyFormatter.maximumFractionDigits = decimalPlaces

        let valueString = currencyFormatter.string(from: value) ?? value.stringValue

        guard includeSymbol else { return valueString }

        switch Presets.symbol(for: currencyCode) {
        case .before(let symbol): return symbol + valueString
        case .after(let symbol): return valueString + symbol
        case .currencyCode: return currencyCode + " " + valueString
        }
    }
    
    //MARK: Common Stripe integrations
    static let publishableKey: String = FeatureFlags.isUsingProductionService
        ? "pk_live_6cmGZopuTsV8novGgJJW9JpC00vLIgtQ1D"
        : "pk_test_sngOd8FnXNkpce9nPXawKrJD00kIDngZkD"

    static let authorizationHeader = "Basic \(Data("\(publishableKey):".utf8).base64EncodedString())"
    
    static let urlSession = OWSURLSession(
        baseUrl: URL(string: "https://api.stripe.com/v1/")!,
        securityPolicy: OWSURLSession.defaultSecurityPolicy,
        configuration: URLSessionConfiguration.ephemeral
    )
    
    static func createToken(with payment: PKPayment) -> Promise<String> {
        firstly(on: .sharedUserInitiated) { () -> Promise<HTTPResponse> in
            return try postForm(endpoint: "tokens", parameters: parameters(for: payment))
        }.map(on: .sharedUserInitiated) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing responseBodyJson")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Failed to decode JSON response")
            }
            return try parser.required(key: "id")
        }
    }
    
    static func createPaymentMethod(with payment: PKPayment) -> Promise<String> {
        firstly(on: .sharedUserInitiated) { () -> Promise<String> in
            createToken(with: payment)
        }.then(on: .sharedUserInitiated) { tokenId -> Promise<HTTPResponse> in
            let parameters: [String: Any] = ["card": ["token": tokenId], "type": "card"]
            return try postForm(endpoint: "payment_methods", parameters: parameters)
        }.map(on: .sharedUserInitiated) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing responseBodyJson")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Failed to decode JSON response")
            }
            return try parser.required(key: "id")
        }
    }
    
    static func confirmSetupIntent(for paymentIntentID: String, clientSecret: String) throws -> Promise<HTTPResponse> {
        firstly (on: .sharedUserInitiated) { () -> Promise<HTTPResponse> in
            let parameters = [
                "payment_method": paymentIntentID,
                "client_secret": clientSecret
            ]

            let clientSecretTokens: [String]? = clientSecret.components(separatedBy: "_")
            guard let tokens = clientSecretTokens else {
                throw OWSAssertionError("Failed to decode clientsecret")
            }
            
            let clientID = tokens[0] + "_" + tokens[1]
            
            return try postForm(endpoint: "setup_intents/\(clientID)/confirm", parameters: parameters)
        }
    }
    
    static func parameters(for payment: PKPayment) -> [String: Any] {
        var parameters = [String: Any]()
        parameters["pk_token"] = String(data: payment.token.paymentData, encoding: .utf8)

        if let billingContact = payment.billingContact {
            parameters["card"] = self.parameters(for: billingContact)
        }

        parameters["pk_token_instrument_name"] = payment.token.paymentMethod.displayName?.nilIfEmpty
        parameters["pk_token_payment_network"] = payment.token.paymentMethod.network.map { $0.rawValue }

        if payment.token.transactionIdentifier == "Simulated Identifier" {
            owsAssertDebug(!FeatureFlags.isUsingProductionService, "Simulated ApplePay only works in staging")
            // Generate a fake transaction identifier
            parameters["pk_token_transaction_id"] = "ApplePayStubs~4242424242424242~0~USD~\(UUID().uuidString)"
        } else {
            parameters["pk_token_transaction_id"] =  payment.token.transactionIdentifier.nilIfEmpty
        }

        return parameters
    }
    
    static func parameters(for contact: PKContact) -> [String: Any] {
        var parameters = [String: Any]()

        if let name = contact.name {
            parameters["name"] = OWSFormat.formatNameComponents(name).nilIfEmpty
        }

        if let email = contact.emailAddress {
            parameters["email"] = email.nilIfEmpty
        }

        if let phoneNumber = contact.phoneNumber {
            parameters["phone"] = phoneNumber.stringValue.nilIfEmpty
        }

        if let address = contact.postalAddress {
            parameters["address_line1"] = address.street.nilIfEmpty
            parameters["address_city"] = address.city.nilIfEmpty
            parameters["address_state"] = address.state.nilIfEmpty
            parameters["address_zip"] = address.postalCode.nilIfEmpty
            parameters["address_country"] = address.isoCountryCode.uppercased()
        }

        return parameters
    }

    
    static func postForm(endpoint: String, parameters: [String: Any]) throws -> Promise<HTTPResponse> {
        guard let formData = AFQueryStringFromParameters(parameters).data(using: .utf8) else {
            throw OWSAssertionError("Failed to generate post body data")
        }

        return urlSession.dataTaskPromise(
            endpoint,
            method: .post,
            headers: ["Content-Type": "application/x-www-form-urlencoded", "Authorization": authorizationHeader],
            body: formData
        )
    }
    
    
}
