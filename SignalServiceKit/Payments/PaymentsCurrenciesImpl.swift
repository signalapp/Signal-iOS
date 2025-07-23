//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class PaymentsCurrenciesImpl: PaymentsCurrenciesSwift, PaymentsCurrencies {

    private let appReadiness: AppReadiness
    private var refreshEvent: RefreshEvent?

    @MainActor
    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness

        // TODO: Tune.
        let refreshCheckInterval: TimeInterval = .minute * 15
        refreshEvent = RefreshEvent(appReadiness: appReadiness, refreshInterval: refreshCheckInterval) { [weak self] in
            self?.updateConversionRates()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateConversionRates),
            name: PaymentsConstants.arePaymentsEnabledDidChange,
            object: nil
        )
    }

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.currentCurrencyCode = Self.loadCurrentCurrencyCode(transaction: transaction)
        }
    }

    // MARK: -

    private static let unfairLock = UnfairLock()

    static let defaultCurrencyCode = PaymentsConstants.currencyCodeGBP

    private static let keyValueStore = KeyValueStore(collection: "PaymentsCurrencies")

    private static let currentCurrencyCodeKey = "currentCurrencyCodeKey"

    // This property should only be accessed with unfairLock.
    private var _currentCurrencyCode: Currency.Code = PaymentsCurrenciesImpl.defaultCurrencyCode

    public private(set) var currentCurrencyCode: Currency.Code {
        get {
            Self.unfairLock.withLock {
                _currentCurrencyCode
            }
        }
        set {
            Self.unfairLock.withLock {
                _currentCurrencyCode = newValue
            }
        }
    }

    private static func loadCurrentCurrencyCode(transaction: DBReadTransaction) -> Currency.Code {
        if let currencyCode = Self.keyValueStore.getString(Self.currentCurrencyCodeKey,
                                                           transaction: transaction) {
            return currencyCode
        }
        if let localeCurrencyCode = Locale.current.currencyCode,
           localeCurrencyCode.count == 3 {
            return localeCurrencyCode
        }
        if Platform.isSimulator {
            Logger.warn("Missing currency code: \(Locale.current.currencyCode ?? "unknown").")
        } else {
            owsFailDebug("Missing currency code.")
        }
        return Self.defaultCurrencyCode
    }

    public func setCurrentCurrencyCode(_ currencyCode: Currency.Code, transaction: DBWriteTransaction) {
        self.currentCurrencyCode = currencyCode

        Self.keyValueStore.setString(currencyCode, key: Self.currentCurrencyCodeKey, transaction: transaction)
    }

    // Expressed as a ratio:
    //
    // price of fiat currency / price of payment currency (MobileCoin)
    public typealias CurrencyConversionRate = PaymentsCurrencies.CurrencyConversionRate
    public typealias ConversionRateMap = [Currency.Code: CurrencyConversionRate]

    public struct ConversionRates {
        let conversionRateMap: ConversionRateMap
        // We track two dates: service freshness date and local refresh date.
        let serviceDate: Date

        var isStale: Bool {
            guard !DebugFlags.paymentsIgnoreCurrencyConversions.get() else {
                // Treat all conversion info as stale/unavailable.
                return true
            }
            // We can't use abs(); if the service and client's clocks don't
            // agree we don't want to treat future values as stale.
            //
            // PAYMENTS TODO: Tune.
            return -serviceDate.timeIntervalSinceNow > .hour
        }
    }

    // This property should only be accessed with unfairLock.
    private var _conversionRates: ConversionRates?
    private var conversionRates: ConversionRates? {
        Self.unfairLock.withLock {
            guard let conversionRates = self._conversionRates else {
                return nil
            }
            guard !conversionRates.isStale else {
                Logger.warn("Conversion rates are stale.")
                return nil
            }
            return conversionRates
        }
    }

    private func setConversionRates(_ newConversionRates: ConversionRates) {
        guard !newConversionRates.isStale else {
            owsFailDebug("New conversionRates are stale.")
            return
        }
        Self.unfairLock.withLock {
            if let oldConversionRates = self._conversionRates {
                guard newConversionRates.serviceDate >= oldConversionRates.serviceDate else {
                    owsFailDebug("New conversionRates are older than current conversionRates.")
                    return
                }
            }
            self._conversionRates = newConversionRates
            NotificationCenter.default.postOnMainThread(name: Self.paymentConversionRatesDidChange, object: nil)
        }
    }

    private let isUpdateInFlight = AtomicBool(false, lock: .sharedGlobal)

    @objc
    @MainActor
    public func updateConversionRates() {
        guard
            appReadiness.isAppReady,
            CurrentAppContext().isMainAppAndActiveIsolated,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        else {
            return
        }
        guard SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled else {
            return
        }
        if let conversionRates = self.conversionRates, !conversionRates.isStale {
            // No need to update.
            return
        }
        let isUpdateInFlight = self.isUpdateInFlight
        guard isUpdateInFlight.tryToSetFlag() else {
            // Update already in flight.
            return
        }
        Task {
            defer { isUpdateInFlight.set(false) }
            do {
                try await self._updateConversionRates()
            } catch {
                owsFailDebugUnlessNetworkFailure(error)
            }
        }
    }

    private func _updateConversionRates() async throws {
        let request = OWSRequestFactory.currencyConversionRequest()
        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)

        guard let json = response.responseBodyJson else {
            throw OWSAssertionError("Missing or invalid JSON")
        }
        guard let parser = ParamParser(responseObject: json) else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let timestamp: UInt64 = try parser.required(key: "timestamp")
        let serviceDate = Date(millisecondsSince1970: timestamp)
        let currencyObjects: [Any] = try parser.required(key: "currencies")
        var conversionRateMap = ConversionRateMap()
        for currencyObject in currencyObjects {
            guard let currencyParser = ParamParser(responseObject: currencyObject) else {
                throw OWSAssertionError("Invalid currencyObject.")
            }
            let base: String = try currencyParser.required(key: "base")
            guard base == PaymentsConstants.mobileCoinCurrencyIdentifier else {
                continue
            }
            let conversionObjects: [String: NSNumber] = try currencyParser.required(key: "conversions")
            for (currencyCode, nsExchangeRate) in conversionObjects {
                guard currencyCode.count == 3 else {
                    Logger.warn("Ignoring invalid currencyCode: \(currencyCode)")
                    continue
                }
                let exchangeRate = nsExchangeRate.doubleValue
                guard exchangeRate > 0 else {
                    Logger.warn("Ignoring invalid exchangeRate: \(exchangeRate), currencyCode: \(currencyCode)")
                    continue
                }
                conversionRateMap[currencyCode] = exchangeRate
            }
        }
        self.setConversionRates(ConversionRates(conversionRateMap: conversionRateMap, serviceDate: serviceDate))
        Logger.info("Success.")
    }

    public static let paymentConversionRatesDidChange = NSNotification.Name("paymentConversionRatesDidChange")

    public var supportedConversionInfos: [CurrencyConversionInfo] {
        conversionInfos(for: supportedCurrencyInfos)
    }

    private func conversionInfos(for currencyInfos: [Currency.Info]) -> [CurrencyConversionInfo] {

        guard let conversionRates = conversionRates else {
            return []
        }

        var infos = [CurrencyConversionInfo]()
        for currencyInfo in currencyInfos {
            guard let info = conversionInfo(forCurrencyCode: currencyInfo.code,
                                            conversionRates: conversionRates) else {
                continue
            }
            infos.append(info)
        }
        infos.sort { (left, right) in
            left.name < right.name
        }
        return infos
    }

    public func conversionInfo(forCurrencyCode currencyCode: Currency.Code) -> CurrencyConversionInfo? {
        conversionInfo(forCurrencyCode: currencyCode,
                       conversionRates: self.conversionRates)
    }

    private func conversionInfo(forCurrencyCode currencyCode: Currency.Code,
                                conversionRates: ConversionRates?) -> CurrencyConversionInfo? {

        guard let conversionRates = conversionRates else {
            return nil
        }
        guard let conversionRate = conversionRates.conversionRateMap[currencyCode] else {
            return nil
        }
        guard conversionRate > 0 else {
            owsFailDebug("Invalid conversionRate: \(conversionRate)")
            return nil
        }
        guard let name = Currency.name(for: currencyCode) else {
            owsFailDebug("Missing name for currencyCode: \(currencyCode)")
            return nil
        }
        return CurrencyConversionInfo(currencyCode: currencyCode,
                                      name: name,
                                      conversionRate: conversionRate,
                                      conversionDate: conversionRates.serviceDate)
    }

    private static let preferredCurrencyCodes: [Currency.Code] = [
        "EUR",
        "GBP",
        "JPY",
        "CNY",
        "AUD",
        "CAD"
    ]

    private static let supportedCurrencyCodesList: [Currency.Code] = [
        "ADP",
        "AED",
        "AFA",
        "AFN",
        "ALK",
        "ALL",
        "AMD",
        "ANG",
        "AOA",
        "AOK",
        "AON",
        "AOR",
        "ARA",
        "ARL",
        "ARM",
        "ARP",
        "ARS",
        "ATS",
        "AUD",
        "AWG",
        "AZM",
        "AZN",
        "BAD",
        "BAM",
        "BAN",
        "BBD",
        "BDT",
        "BEC",
        "BEF",
        "BEL",
        "BGL",
        "BGM",
        "BGN",
        "BGO",
        "BHD",
        "BIF",
        "BMD",
        "BND",
        "BOB",
        "BOL",
        "BOP",
        "BOV",
        "BRB",
        "BRC",
        "BRE",
        "BRL",
        "BRN",
        "BRR",
        "BRZ",
        "BSD",
        "BTN",
        "BUK",
        "BWP",
        "BYB",
        "BYN",
        "BYR",
        "BZD",
        "CAD",
        "CDF",
        "CHE",
        "CHF",
        "CHW",
        "CLE",
        "CLF",
        "CLP",
        "CNH",
        "CNX",
        "CNY",
        "COP",
        "COU",
        "CRC",
        "CSD",
        "CSK",
        "CVE",
        "CYP",
        "CZK",
        "DDM",
        "DEM",
        "DJF",
        "DKK",
        "DOP",
        "DZD",
        "ECS",
        "ECV",
        "EEK",
        "EGP",
        "EQE",
        "ERN",
        "ESA",
        "ESB",
        "ESP",
        "ETB",
        "EUR",
        "FIM",
        "FJD",
        "FKP",
        "FRF",
        "GBP",
        "GEK",
        "GEL",
        "GHC",
        "GHS",
        "GIP",
        "GMD",
        "GNF",
        "GNS",
        "GQE",
        "GRD",
        "GTQ",
        "GWE",
        "GWP",
        "GYD",
        "HKD",
        "HNL",
        "HRD",
        "HRK",
        "HTG",
        "HUF",
        "IDR",
        "IEP",
        "ILP",
        "ILR",
        "ILS",
        "INR",
        "IQD",
        "ISJ",
        "ISK",
        "ITL",
        "JMD",
        "JOD",
        "JPY",
        "KES",
        "KGS",
        "KHR",
        "KMF",
        "KRH",
        "KRO",
        "KRW",
        "KWD",
        "KYD",
        "KZT",
        "LAK",
        "LBP",
        "LKR",
        "LRD",
        "LSL",
        "LSM",
        "LTL",
        "LTT",
        "LUC",
        "LUF",
        "LUL",
        "LVL",
        "LVR",
        "LYD",
        "MAD",
        "MAF",
        "MCF",
        "MDC",
        "MDL",
        "MGA",
        "MGF",
        "MKD",
        "MKN",
        "MLF",
        "MMK",
        "MNT",
        "MOP",
        "MRO",
        "MRU",
        "MTL",
        "MTP",
        "MUR",
        "MVP",
        "MVR",
        "MWK",
        "MXN",
        "MXP",
        "MXV",
        "MYR",
        "MZE",
        "MZM",
        "MZN",
        "NAD",
        "NGN",
        "NIC",
        "NIO",
        "NLG",
        "NOK",
        "NPR",
        "NZD",
        "OMR",
        "PAB",
        "PEI",
        "PEN",
        "PES",
        "PGK",
        "PHP",
        "PKR",
        "PLN",
        "PLZ",
        "PTE",
        "PYG",
        "QAR",
        "RHD",
        "ROL",
        "RON",
        "RSD",
        "RUB",
        "RUR",
        "RWF",
        "SAR",
        "SBD",
        "SCR",
        "SDD",
        "SDG",
        "SDP",
        "SEK",
        "SGD",
        "SHP",
        "SIT",
        "SKK",
        "SLL",
        "SOS",
        "SRD",
        "SRG",
        "SSP",
        "STD",
        "STN",
        "SUR",
        "SVC",
        "SZL",
        "THB",
        "TJR",
        "TJS",
        "TMM",
        "TMT",
        "TND",
        "TOP",
        "TPE",
        "TRL",
        "TRY",
        "TTD",
        "TWD",
        "TZS",
        "UAH",
        "UAK",
        "UGS",
        "UGX",
        "USD",
        "USN",
        "USS",
        "UYI",
        "UYP",
        "UYU",
        "UZS",
        "VEB",
        "VEF",
        "VND",
        "VNN",
        "VUV",
        "WST",
        "XAF",
        "XAG",
        "XAU",
        "XBA",
        "XBB",
        "XBC",
        "XBD",
        "XCD",
        "XDR",
        "XEU",
        "XFO",
        "XFU",
        "XOF",
        "XPD",
        "XPF",
        "XPT",
        "XRE",
        "XSU",
        "XTS",
        "XUA",
        "XXX",
        "YDD",
        "YER",
        "YUD",
        "YUM",
        "YUN",
        "YUR",
        "ZAL",
        "ZAR",
        "ZMK",
        "ZMW",
        "ZRN",
        "ZRZ",
        "ZWD",
        "ZWL",
        "ZWR"
    ]

    static var supportedCurrencyCodes: Set<Currency.Code> {
        var result = Set<Currency.Code>()
        // Support the intersection of the currency code whitelist
        // and the currencies supported by iOS.
        result.formUnion(Locale.isoCurrencyCodes)
        result.formIntersection(supportedCurrencyCodesList)
        // Always include the preferred currency codes.
        result.formUnion(preferredCurrencyCodes)
        return result
    }

    public var preferredCurrencyInfos: [Currency.Info] {
        // Always include values for preferred currencies.
        Currency.infos(for: Self.preferredCurrencyCodes, ignoreMissingNames: true, shouldSort: false)
    }

    public var supportedCurrencyInfos: [Currency.Info] {
        Currency.infos(for: Array(Self.supportedCurrencyCodes), ignoreMissingNames: false, shouldSort: true)
    }

    public var supportedCurrencyInfosWithCurrencyConversions: [Currency.Info] {
        supportedConversionInfos.map { $0.asCurrencyInfo }
    }
}
