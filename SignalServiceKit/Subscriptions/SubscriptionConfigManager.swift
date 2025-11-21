//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class SubscriptionConfigManager {
    private struct SubscriptionConfig {
        let donation: DonationSubscriptionConfiguration
        let backup: BackupSubscriptionConfiguration
    }

    private enum StoreKeys {
        static let lastFetchedResponseBody = "lastFetchedResponseBody"
        static let lastFetchDate = "lastFetchDate"
    }

    private let dateProvider: DateProvider
    private let db: DB
    private let kvStore: NewKeyValueStore
    private let networkManager: NetworkManager

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        networkManager: NetworkManager,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = NewKeyValueStore(collection: "SubscriptionConfiguration")
        self.networkManager = networkManager
    }

    public func refresh() async throws {
        _ = try await _refresh()
    }

    private func _refresh() async throws -> SubscriptionConfig {
        var request = TSRequest(
            url: URL(string: "v1/subscription/configuration")!,
            method: "GET",
            parameters: nil,
        )
        request.auth = .anonymous

        let response: HTTPResponse = try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: { try await networkManager.asyncRequest(request) },
        )

        guard let responseBodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing response body!")
        }

        let donationConfig: DonationSubscriptionConfiguration = try .from(responseBodyData: responseBodyData)
        let backupConfig: BackupSubscriptionConfiguration = try .from(responseBodyData: responseBodyData)

        await db.awaitableWrite { tx in
            kvStore.writeValue(dateProvider(), forKey: StoreKeys.lastFetchDate, tx: tx)
            kvStore.writeValue(responseBodyData, forKey: StoreKeys.lastFetchedResponseBody, tx: tx)
        }

        return SubscriptionConfig(
            donation: donationConfig,
            backup: backupConfig,
        )
    }

    // MARK: Donations

    /// Returns a `DonationSubscriptionConfiguration` either fetched live from
    /// the service or cached on disk from a recent fetch.
    public func donationConfiguration() async throws -> DonationSubscriptionConfiguration {
        if
            let cachedResponseBody = db.read(block: { _cachedResponseBody(tx: $0) }),
            let donationConfig: DonationSubscriptionConfiguration = try? .from(responseBodyData: cachedResponseBody)
        {
            return donationConfig
        }

        return try await _refresh().donation
    }

    // MARK: Backups

    /// Returns a `BackupSubscriptionConfiguration` either fetched live from
    /// the service or cached on disk from a recent fetch.
    public func backupConfiguration() async throws -> BackupSubscriptionConfiguration {
        if
            let cachedResponseBody = db.read(block: { _cachedResponseBody(tx: $0) }),
            let backupConfig: BackupSubscriptionConfiguration = try? .from(responseBodyData: cachedResponseBody)
        {
            return backupConfig
        }

        return try await _refresh().backup
    }

    /// Returns a recently-fetched-and-cached `BackupSubscriptionConfiguration`
    /// if available, and default values otherwise.
    ///
    /// Useful for callers who need a synchronous, non-optional value. Callers
    /// may also call ``backupConfiguration()`` once out of the critical
    /// synchronous region, preferring that returned value if different.
    public func backupConfigurationOrDefault(tx: DBReadTransaction) -> BackupSubscriptionConfiguration {
        // It's always better to fall back on our last-fetched value than the
        // defaults, so check the cache ignoring TTL.
        if
            let cachedResponseBody = _cachedResponseBody(ttl: nil, tx: tx),
            let backupConfig: BackupSubscriptionConfiguration = try? .from(responseBodyData: cachedResponseBody)
        {
            return backupConfig
        }

        return BackupSubscriptionConfiguration(
            storageAllowanceBytes: 100_000_000_000,
            freeTierMediaDays: 45,
        )
    }

    /// The cached result of a previous configuration fetch.
    /// - Parameter ttl
    /// An optional "max age" of the cached value, after which it is ignored.
    private func _cachedResponseBody(
        ttl: TimeInterval? = .week,
        tx: DBReadTransaction,
    ) -> Data? {
        if
            let ttl,
            let lastFetchDate = kvStore.fetchValue(Date.self, forKey: StoreKeys.lastFetchDate, tx: tx),
            dateProvider().timeIntervalSince(lastFetchDate) > ttl
        {
            return nil
        }

        return kvStore.fetchValue(Data.self, forKey: StoreKeys.lastFetchedResponseBody, tx: tx)
    }
}

// MARK: -

/// Represents Backup subscription configuration fetched from the service.
public struct BackupSubscriptionConfiguration: Equatable {
    public let storageAllowanceBytes: UInt64
    public let freeTierMediaDays: UInt64

    public init(storageAllowanceBytes: UInt64, freeTierMediaDays: UInt64) {
        self.storageAllowanceBytes = storageAllowanceBytes
        self.freeTierMediaDays = freeTierMediaDays
    }

    static func from(responseBodyData: Data) throws -> BackupSubscriptionConfiguration {
        struct TopLevelObject: Decodable {
            struct BackupObject: Decodable {
                struct BackupLevelObject: Decodable {
                    let storageAllowanceBytes: Int64
                }

                let freeTierMediaDays: Int64
                let levels: [String: BackupLevelObject]
            }

            let backup: BackupObject
        }

        let topLevelObject = try JSONDecoder().decode(TopLevelObject.self, from: responseBodyData)
        let backupObject = topLevelObject.backup

        guard let backupLevelObject = backupObject.levels["201"] else {
            throw OWSAssertionError("Missing Backup config for level 201!")
        }

        guard let storageAllowanceBytes = UInt64(exactly: backupLevelObject.storageAllowanceBytes) else {
            throw OWSAssertionError("storageAllowanceBytes was not a valid UInt64!")
        }

        guard let freeTierMediaDays = UInt64(exactly: backupObject.freeTierMediaDays) else {
            throw OWSAssertionError("freeTierMediaDays was not a valid UInt64!")
        }

        return BackupSubscriptionConfiguration(
            storageAllowanceBytes: storageAllowanceBytes,
            freeTierMediaDays: freeTierMediaDays,
        )
    }
}

// MARK: -

/// Represents donation configuration information fetched from the service,
/// such as preset donation levels and badge information.
public struct DonationSubscriptionConfiguration {
    public struct BoostConfiguration {
        public let level: UInt
        public let badge: ProfileBadge
        public let presetAmounts: [Currency.Code: DonationUtilities.Preset]
        public let minimumAmountsByCurrency: [Currency.Code: FiatMoney]

        /// The maximum donation amount allowed for SEPA debit transfers.
        public let maximumAmountViaSepa: FiatMoney
    }

    public struct GiftConfiguration {
        public let level: UInt
        public let badge: ProfileBadge
        public let presetAmount: [Currency.Code: FiatMoney]
    }

    public struct SubscriptionConfiguration {
        public let levels: [DonationSubscriptionLevel]
    }

    public struct PaymentMethodsConfiguration: Equatable {
        public let supportedPaymentMethodsByCurrency: [Currency.Code: Set<DonationPaymentMethod>]
    }

    public let boost: BoostConfiguration
    public let gift: GiftConfiguration
    public let subscription: SubscriptionConfiguration
    public let paymentMethods: PaymentMethodsConfiguration

    private init(
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

    // MARK: -

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

    static func from(responseBodyData: Data) throws -> Self {
        guard
            let responseBodyDict = try? JSONSerialization
                .jsonObject(with: responseBodyData) as? [String: Any]
        else {
            throw OWSAssertionError("Failed to get dictionary from body data!")
        }

        return try .from(responseBodyDict: responseBodyDict)
    }

    /// Parse a service configuration from a response body.
    static func from(responseBodyDict: [String: Any]) throws -> Self {
        let parser = ParamParser(responseBodyDict)

        let levels: BadgedLevels = try parseLevels(fromParser: parser)
        let presetsByCurrency: PresetsByCurrency = try parsePresets(fromParser: parser, forLevels: levels)
        let sepaBoostMaximum = try parseSepaBoostMaximum(fromParser: parser)

        let boostConfig: BoostConfiguration = {
            let minimumAmountsByCurrency: [Currency.Code: FiatMoney] = presetsByCurrency.mapValues { $0.boost.minimum }
            let presetAmounts: [Currency.Code: DonationUtilities.Preset] = presetsByCurrency.reduce(
                into: [:], { partialResult, kv in
                    let (code, presets) = kv
                    partialResult[code] = DonationUtilities.Preset(
                        currencyCode: code,
                        amounts: presets.boost.presets
                    )
                }
            )

            return BoostConfiguration(
                level: levels.boost.value,
                badge: levels.boost.badge,
                presetAmounts: presetAmounts,
                minimumAmountsByCurrency: minimumAmountsByCurrency,
                maximumAmountViaSepa: sepaBoostMaximum
            )
        }()

        let giftConfig: GiftConfiguration = {
            let presetAmounts: [Currency.Code: FiatMoney] = presetsByCurrency.mapValues {
                $0.gift.preset
            }

            return GiftConfiguration(
                level: levels.gift.value,
                badge: levels.gift.badge,
                presetAmount: presetAmounts
            )
        }()

        let subscriptionConfig: SubscriptionConfiguration = try {
            /// Query for the preset donation amounts for the given badged
            /// level. Throws if amounts are missing for this level.
            func makeSubscriptionLevel(fromBadgedLevel level: BadgedLevel) throws -> DonationSubscriptionLevel {
                let presetsByCurrencyForLevel: [Currency.Code: FiatMoney] = try presetsByCurrency.mapValues { presets in
                    guard let amountForLevel = presets.subscription.presetsByLevel[level.value] else {
                        throw ParseError.missingAmountForLevel(level.value)
                    }

                    return amountForLevel
                }

                return DonationSubscriptionLevel(
                    level: level.value,
                    badge: level.badge,
                    amounts: presetsByCurrencyForLevel
                )
            }

            let subscriptionLevels: [DonationSubscriptionLevel] = try levels.subscription
                .map(makeSubscriptionLevel)
                .sorted()

            return SubscriptionConfiguration(levels: subscriptionLevels)
        }()

        let paymentMethodsConfig: PaymentMethodsConfiguration = {
            let supportedPaymentMethodsByCurrency: [Currency.Code: Set<DonationPaymentMethod>] = presetsByCurrency
                .mapValues { presets in
                    presets.supportedPaymentMethods
                }

            return PaymentMethodsConfiguration(supportedPaymentMethodsByCurrency: supportedPaymentMethodsByCurrency)
        }()

        return Self(
            boost: boostConfig,
            gift: giftConfig,
            subscription: subscriptionConfig,
            paymentMethods: paymentMethodsConfig
        )
    }

    // MARK: - Parse levels

    private struct BadgedLevel {
        let value: UInt
        let badge: ProfileBadge
    }

    private struct BadgedLevels {
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
    private static func parseLevels(fromParser parser: ParamParser) throws -> BadgedLevels {
        let levelsJson: [String: [String: Any]] = try parser.required(key: "levels")
        var badgesByLevel: [UInt: BadgedLevel] = try levelsJson.reduce(into: [:]) { partialResult, kv in
            let (levelString, json) = kv

            guard let level = UInt(levelString) else {
                throw ParseError.invalidBadgeLevel(levelString: levelString)
            }

            let levelParser = ParamParser(json)

            partialResult[level] = BadgedLevel(
                value: level,
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

    // MARK: - SEPA maximum boost

    private static func parseSepaBoostMaximum(
        fromParser parser: ParamParser
    ) throws -> FiatMoney {
        let sepaMaxEurosInt: Int = try parser.required(key: "sepaMaximumEuros")
        return FiatMoney(currencyCode: "EUR", value: Decimal(sepaMaxEurosInt))
    }

    // MARK: - Parse presets

    private struct BoostPresets {
        let minimum: FiatMoney
        let presets: [FiatMoney]
    }

    private struct GiftPreset {
        let preset: FiatMoney
    }

    private struct SubscriptionPresets {
        let presetsByLevel: [UInt: FiatMoney]
    }

    private struct Presets {
        let boost: BoostPresets
        let gift: GiftPreset
        let subscription: SubscriptionPresets
        let supportedPaymentMethods: Set<DonationPaymentMethod>
    }

    private typealias PresetsByCurrency = [Currency.Code: Presets]

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
    private static func parsePresets(
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
        let parser = ParamParser(json)

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
            case "SEPA_DEBIT":
                result.formUnion([.sepa])
            case "IDEAL":
                result.formUnion([.ideal])
            default:
                Logger.warn("Unrecognized payment string: \(methodString)")
            }
        }

        return result
    }
}
