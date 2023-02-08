//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension SubscriptionManager {
    /// Represents donation configuration information fetched from the service,
    /// such as preset donation levels and badge information.
    public struct DonationConfiguration {
        public struct BoostConfiguration {
            public let level: UInt
            public let badge: ProfileBadge
            public let minimumAmounts: [Currency.Code: FiatMoney]
            public let presetAmounts: [Currency.Code: DonationUtilities.Preset]
        }

        public struct GiftConfiguration {
            public let level: UInt
            public let badge: ProfileBadge
            public let presetAmount: [Currency.Code: FiatMoney]
        }

        public struct SubscriptionConfiguration {
            public let levels: [SubscriptionLevel]
        }

        public struct PaymentMethodsConfiguration: Equatable {
            private let supportedPaymentMethodsByCurrency: [Currency.Code: Set<DonationPaymentMethod>]

            init(supportedPaymentMethodsByCurrency: [Currency.Code: Set<DonationPaymentMethod>]) {
                self.supportedPaymentMethodsByCurrency = supportedPaymentMethodsByCurrency
            }

            public func supportedPaymentMethods(
                forCurrencyCode code: Currency.Code
            ) -> Set<DonationPaymentMethod> {
                supportedPaymentMethodsByCurrency[code] ?? []
            }
        }

        public let boost: BoostConfiguration
        public let gift: GiftConfiguration
        public let subscription: SubscriptionConfiguration
        public let paymentMethods: PaymentMethodsConfiguration

        fileprivate init(
            boost: BoostConfiguration,
            gift: GiftConfiguration,
            subscription: SubscriptionConfiguration,
            paymentMethods: PaymentMethodsConfiguration
        ) {
            self.boost = boost
            self.gift = gift
            self.subscription = subscription
            self.paymentMethods = paymentMethods
        }
    }

    /// Fetch donation configuration from the service.
    public static func fetchDonationConfiguration() -> Promise<DonationConfiguration> {
        let request = OWSRequestFactory.donationConfiguration()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.sharedUserInitiated) { response -> DonationConfiguration in
            try DonationConfiguration.from(configurationServiceResponse: response.responseBodyJson)
        }
    }
}

extension SubscriptionManager.DonationConfiguration {
    enum ParseError: Error, Equatable {
        /// Missing a preset amount for a donation level.
        case missingAmountForLevel(_ level: UInt)
        /// Invalid level for a badge.
        case invalidBadgeLevel(levelString: String)
        /// Missing the boost badge.
        case missingBoostBadge
        /// Missing the gift badge.
        case missingGiftBadge
        /// Invalid currency code.
        case invalidCurrencyCode(_ code: String)
        /// Invalid level for a one-time preset amount.
        case invalidOneTimeAmountLevel(levelString: String)
        /// Missing boost badge preset amounts.
        case missingBoostPresetAmounts
        /// Missing gift badge preset amount.
        case missingGiftPresetAmount
        /// Invalid level for a subscription preset amount.
        case invalidSubscriptionAmountLevel(levelString: String)
        /// Invalid payment method string.
        case invalidPaymentMethodString(string: String)
    }

    /// Parse a service configuration from a response body.
    static func from(configurationServiceResponse responseBody: Any?) throws -> Self {
        guard let parser = ParamParser(responseObject: responseBody) else {
            throw OWSAssertionError("Missing or invalid response!")
        }

        let levels: BadgedLevels = try parseLevels(fromParser: parser)
        let presetsByCurrency: PresetsByCurrency = try parsePresets(fromParser: parser, forLevels: levels)

        let boostConfig: BoostConfiguration = {
            let minimumAmounts: [Currency.Code: FiatMoney] = presetsByCurrency.mapValues { $0.boost.minimum }
            let presetAmounts: [Currency.Code: DonationUtilities.Preset] = presetsByCurrency.reduce(
                into: [:], { partialResult, kv in
                    let (code, presets) = kv
                    partialResult[code] = DonationUtilities.Preset(
                        currencyCode: code,
                        amounts: presets.boost.presets
                    )
                }
            )

            return .init(
                level: levels.boost.value,
                badge: levels.boost.badge,
                minimumAmounts: minimumAmounts,
                presetAmounts: presetAmounts
            )
        }()

        let giftConfig: GiftConfiguration = {
            let presetAmounts: [Currency.Code: FiatMoney] = presetsByCurrency.mapValues {
                $0.gift.preset
            }

            return .init(
                level: levels.gift.value,
                badge: levels.gift.badge,
                presetAmount: presetAmounts
            )
        }()

        let subscriptionConfig: SubscriptionConfiguration = try {
            /// Query for the preset donation amounts for the given badged
            /// level. Throws if amounts are missing for this level.
            func makeSubscriptionLevel(fromBadgedLevel level: BadgedLevel) throws -> SubscriptionLevel {
                let presetsByCurrencyForLevel: [Currency.Code: FiatMoney] = try presetsByCurrency.mapValues { presets in
                    guard let amountForLevel = presets.subscription.presetsByLevel[level.value] else {
                        throw ParseError.missingAmountForLevel(level.value)
                    }

                    return amountForLevel
                }

                return .init(
                    level: level.value,
                    name: level.name,
                    badge: level.badge,
                    amounts: presetsByCurrencyForLevel
                )
            }

            let subscriptionLevels: [SubscriptionLevel] = try levels.subscription
                .map(makeSubscriptionLevel)
                .sorted()

            return .init(levels: subscriptionLevels)
        }()

        let paymentMethodsConfig: PaymentMethodsConfiguration = {
            let supportedPaymentMethodsByCurrency: [Currency.Code: Set<DonationPaymentMethod>] = presetsByCurrency
                .mapValues { presets in
                    presets.supportedPaymentMethods
                }

            return .init(supportedPaymentMethodsByCurrency: supportedPaymentMethodsByCurrency)
        }()

        return .init(
            boost: boostConfig,
            gift: giftConfig,
            subscription: subscriptionConfig,
            paymentMethods: paymentMethodsConfig
        )
    }
}

// MARK: - Parse levels

private extension SubscriptionManager.DonationConfiguration {
    struct BadgedLevel {
        let value: UInt
        let name: String
        let badge: ProfileBadge
    }

    struct BadgedLevels {
        let boost: BadgedLevel
        let gift: BadgedLevel
        let subscription: [BadgedLevel]
    }

    /// Parse well-known donation levels from the given parser.
    ///
    /// The levels are returned by the service in the following format:
    ///
    /// ```json
    /// {
    ///     "levels": {
    ///         "<level (int as string)>": {
    ///             "name": "<name (string)",
    ///             "badge": <badge (json)>
    ///         },
    ///         ...
    ///     }
    /// }
    /// ```
    ///
    /// Boost and gift one-time donations have well-known levels and are
    /// expected. Any other levels are interpreted as subscription levels.
    static func parseLevels(fromParser parser: ParamParser) throws -> BadgedLevels {
        let levelsJson: [String: [String: Any]] = try parser.required(key: "levels")
        var badgesByLevel: [UInt: BadgedLevel] = try levelsJson.reduce(into: [:]) { partialResult, kv in
            let (levelString, json) = kv

            guard let level = UInt(levelString) else {
                throw ParseError.invalidBadgeLevel(levelString: levelString)
            }

            let levelParser = ParamParser(dictionary: json)

            partialResult[level] = BadgedLevel(
                value: level,
                name: try levelParser.required(key: "name"),
                badge: try ProfileBadge(jsonDictionary: try levelParser.required(key: "badge"))
            )
        }

        let boostLevel = OneTimeBadgeLevel.boostBadge.rawValue.asNSNumber.uintValue
        guard let boostBadge = badgesByLevel.removeValue(forKey: boostLevel) else {
            throw ParseError.missingBoostBadge
        }

        let giftLevel = OWSGiftBadge.Level.signalGift.rawLevel.asNSNumber.uintValue
        guard let giftBadge = badgesByLevel.removeValue(forKey: giftLevel) else {
            throw ParseError.missingGiftBadge
        }

        // Remaining levels are assumed to be subscriptions
        let subscriptionLevels = badgesByLevel

        return BadgedLevels(
            boost: boostBadge,
            gift: giftBadge,
            subscription: Array(subscriptionLevels.values)
        )
    }
}

// MARK: - Parse presets

private extension SubscriptionManager.DonationConfiguration {
    struct BoostPresets {
        let minimum: FiatMoney
        let presets: [FiatMoney]
    }

    struct GiftPreset {
        let preset: FiatMoney
    }

    struct SubscriptionPresets {
        let presetsByLevel: [UInt: FiatMoney]
    }

    struct Presets {
        let boost: BoostPresets
        let gift: GiftPreset
        let subscription: SubscriptionPresets
        let supportedPaymentMethods: Set<DonationPaymentMethod>
    }

    typealias PresetsByCurrency = [Currency.Code: Presets]

    /// Parse amounts, grouped by currency, from the given parser.
    ///
    /// The amounts are returned by the service in the following format:
    ///
    /// ```json
    /// {
    ///     "currencies": {
    ///         "<currency (string)>": <amounts (json)>,
    ///         ...
    ///     }
    /// }
    /// ```
    static func parsePresets(
        fromParser parser: ParamParser,
        forLevels levels: BadgedLevels
    ) throws -> PresetsByCurrency {
        let amountsByCurrency: [String: [String: Any]] = try parser.required(key: "currencies")

        return try amountsByCurrency.reduce(into: [:]) { partialResult, kv in
            let (currencyCode, json) = kv

            guard !currencyCode.isEmpty else {
                throw ParseError.invalidCurrencyCode(currencyCode)
            }

            partialResult[currencyCode.uppercased()] = try parsePresets(
                fromJson: json,
                forCurrency: currencyCode.uppercased(),
                withLevels: levels
            )
        }
    }

    private static func parsePresets(
        fromJson json: [String: Any],
        forCurrency code: Currency.Code,
        withLevels levels: BadgedLevels
    ) throws -> Presets {
        let parser = ParamParser(dictionary: json)

        let (boostPresets, giftPreset) = try parseOneTimePresets(
            fromParser: parser,
            forCurrency: code,
            withLevels: levels
        )

        let subscriptionPresets = try parseSubscriptionPresets(
            fromParser: parser,
            forCurrency: code
        )

        let supportedPaymentMethods = try parseSupportedPaymentMethods(
            fromParser: parser
        )

        return Presets(
            boost: boostPresets,
            gift: giftPreset,
            subscription: subscriptionPresets,
            supportedPaymentMethods: supportedPaymentMethods
        )
    }

    /// Parse one-time donation amounts from the given parser.
    ///
    /// The one-time amounts are returned by the service in the following
    /// format:
    ///
    /// ```json
    /// {
    ///     "minimum": <preset value (int)>,
    ///     "oneTime": {
    ///         "<level (int as string)>": [<preset value (int)>, ...],
    ///         ...
    ///     }
    /// }
    /// ```
    ///
    /// Boost and gift donations (at the time of writing, the two possible
    /// one-time donation types) each have a well-known level, which we
    /// query from the parsed JSON above to parse a boost and gift configuration.
    private static func parseOneTimePresets(
        fromParser parser: ParamParser,
        forCurrency code: Currency.Code,
        withLevels levels: BadgedLevels
    ) throws -> (BoostPresets, GiftPreset) {
        /// Create a ``FiatMoney`` from a parsed JSON integer value.
        func makeMoney(fromIntValue amount: Int) -> FiatMoney {
            FiatMoney(currencyCode: code, value: Decimal(amount))
        }

        let oneTimeAmountsFromService: [String: [Int]] = try parser.required(key: "oneTime")
        let oneTimeAmounts: [UInt: [FiatMoney]] = try oneTimeAmountsFromService
            .reduce(into: [:]) { partialResult, kv in
                let (levelString, amounts): (String, [Int]) = kv

                guard let level = UInt(levelString) else {
                    throw ParseError.invalidOneTimeAmountLevel(levelString: levelString)
                }

                partialResult[level] = amounts.map(makeMoney)
            }

        guard
            let boostPresetAmounts = oneTimeAmounts[levels.boost.value],
            !boostPresetAmounts.isEmpty
        else {
            throw ParseError.missingBoostPresetAmounts
        }

        guard
            let giftPresetAmounts = oneTimeAmounts[levels.gift.value],
            let giftPresetAmount = giftPresetAmounts.first
        else {
            throw ParseError.missingGiftPresetAmount
        }

        return (
            BoostPresets(
                minimum: makeMoney(fromIntValue: try parser.required(key: "minimum")),
                presets: boostPresetAmounts
            ),
            GiftPreset(
                preset: giftPresetAmount
            )
        )
    }

    /// Parse subscription donation levels and their associated amounts from the
    /// given parser.
    ///
    /// The subscription amounts are returned by the service in the following
    /// format:
    ///
    /// ```json
    /// {
    ///     "subscription": {
    ///         "<level (int as string)>": <preset value (int)>,
    ///         ...
    ///     }
    /// }
    /// ```
    ///
    /// Each subscription level is assigned a single preset value.
    private static func parseSubscriptionPresets(
        fromParser parser: ParamParser,
        forCurrency code: Currency.Code
    ) throws -> SubscriptionPresets {
        /// Create a ``FiatMoney`` from a parsed JSON integer value.
        func makeMoney(fromIntValue amount: Int) -> FiatMoney {
            FiatMoney(currencyCode: code, value: Decimal(amount))
        }

        let subscriptionAmountsFromService: [String: Int] = try parser.required(key: "subscription")
        let subscriptionAmounts: [UInt: FiatMoney] = try subscriptionAmountsFromService
            .reduce(into: [:]) { partialResult, kv in
                let (levelString, amount) = kv

                guard let level = UInt(levelString) else {
                    throw ParseError.invalidSubscriptionAmountLevel(levelString: levelString)
                }

                partialResult[level] = makeMoney(fromIntValue: amount)
            }

        return SubscriptionPresets(
            presetsByLevel: subscriptionAmounts
        )
    }

    /// Parse supported payment methods from the given parser.
    ///
    /// The payment methods are returned by the service in the following
    /// format:
    ///
    /// ```json
    /// {
    ///     "supportedPaymentMethods": [<payment method (string)>, ...]
    /// }
    /// ```
    ///
    /// Known payment methods include "CARD", which corresponds to Apple Pay
    /// and credit cards, and "PAYPAL", which corresponds to PayPal.
    private static func parseSupportedPaymentMethods(
        fromParser parser: ParamParser
    ) throws -> Set<DonationPaymentMethod> {
        let paymentMethodStrings: [String] = try parser.required(key: "supportedPaymentMethods")

        var result: Set<DonationPaymentMethod> = []

        for methodString in paymentMethodStrings {
            switch methodString {
            case "CARD":
                result.formUnion([.applePay, .creditOrDebitCard])
            case "PAYPAL":
                result.formUnion([.paypal])
            default:
                throw ParseError.invalidPaymentMethodString(string: methodString)
            }
        }

        return result
    }
}
