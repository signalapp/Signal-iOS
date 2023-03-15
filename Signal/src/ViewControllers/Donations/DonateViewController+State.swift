//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

extension DonateViewController {
    /// State for the donate screen.
    ///
    /// There's only one currency picker in the UI but we store the selected
    /// currency twice. This is because supported currency codes may differ
    /// between one-time and monthly donations. For example, EUR may be
    /// supported for monthly donations but not one-time ones. If EUR is
    /// selected in monthly mode and you switch, we need to change the selected
    /// currency.
    struct State: Equatable {

        // MARK: Typealiases

        typealias PaymentMethodsConfiguration = SubscriptionManagerImpl.DonationConfiguration.PaymentMethodsConfiguration
        typealias OneTimeConfiguration = SubscriptionManagerImpl.DonationConfiguration.BoostConfiguration
        typealias MonthlyConfiguration = SubscriptionManagerImpl.DonationConfiguration.SubscriptionConfiguration

        // MARK: - One-time state

        struct OneTimeState: Equatable {
            enum SelectedAmount: Equatable {
                case nothingSelected(currencyCode: Currency.Code)
                case selectedPreset(amount: FiatMoney)
                case choseCustomAmount(amount: FiatMoney)
            }

            enum OneTimePaymentRequest: Equatable {
                case noAmountSelected
                case amountIsTooSmall(minimumAmount: FiatMoney)
                case canContinue(amount: FiatMoney, supportedPaymentMethods: Set<DonationPaymentMethod>)
            }

            public let selectedAmount: SelectedAmount
            public let profileBadge: ProfileBadge

            fileprivate let presets: [Currency.Code: DonationUtilities.Preset]
            fileprivate let minimumAmounts: [Currency.Code: FiatMoney]
            fileprivate let paymentMethodConfiguration: PaymentMethodsConfiguration
            fileprivate let localNumber: String?

            public var amount: FiatMoney? {
                switch selectedAmount {
                case .nothingSelected:
                    return nil
                case let .selectedPreset(amount: amount), let .choseCustomAmount(amount):
                    return amount
                }
            }

            public var selectedCurrencyCode: Currency.Code {
                switch selectedAmount {
                case let .nothingSelected(currencyCode):
                    return currencyCode
                case let .selectedPreset(amount: amount), let .choseCustomAmount(amount):
                    return amount.currencyCode
                }
            }

            public var selectedPreset: DonationUtilities.Preset? {
                presets[selectedCurrencyCode]
            }

            /// The set of supported currency codes. Excludes currencies for
            /// which there are no supported payment methods.
            fileprivate var supportedCurrencyCodes: Set<Currency.Code> {
                Set(presets.keys).supported(
                    forDonationMode: .oneTime,
                    withConfig: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }

            public var paymentRequest: OneTimePaymentRequest {
                guard let amount = amount else {
                    return .noAmountSelected
                }

                let minimumAmount: FiatMoney
                if let minimum = minimumAmounts[amount.currencyCode] {
                    minimumAmount = minimum
                } else {
                    // Since this is just a sanity check, don't prevent donation here.
                    // It is likely to fail on its own while processing the payment.
                    Logger.warn("[Donations] Unexpectedly missing minimum boost amount for currency \(amount.currencyCode)!")
                    minimumAmount = .init(currencyCode: amount.currencyCode, value: 0)
                }

                if DonationUtilities.isBoostAmountTooSmall(amount, minimumAmount: minimumAmount) {
                    return .amountIsTooSmall(minimumAmount: minimumAmount)
                }

                return .canContinue(
                    amount: amount,
                    supportedPaymentMethods: supportedPaymentMethods(forCurrencyCode: amount.currencyCode)
                )
            }

            fileprivate func selectCurrencyCode(_ newValue: Currency.Code) -> OneTimeState {
                guard presets.keys.contains(newValue) else {
                    Logger.warn("[Donations] \(newValue) is not a supported one-time currency code. This may indicate a bug")
                    return self
                }
                return OneTimeState(
                    selectedAmount: .nothingSelected(currencyCode: newValue),
                    profileBadge: profileBadge,
                    presets: presets,
                    minimumAmounts: minimumAmounts,
                    paymentMethodConfiguration: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }

            fileprivate func selectOneTimeAmount(_ newValue: SelectedAmount) -> OneTimeState {
                let currencyCodeToCheck: Currency.Code
                switch newValue {
                case let .nothingSelected(currencyCode):
                    currencyCodeToCheck = currencyCode
                case let .selectedPreset(amount):
                    guard
                        let preset = presets[amount.currencyCode],
                        preset.amounts.contains(amount)
                    else {
                        owsFail("[Donations] Selected a one-time preset amount but preset amount was not found")
                    }
                    currencyCodeToCheck = amount.currencyCode
                case let .choseCustomAmount(amount):
                    currencyCodeToCheck = amount.currencyCode
                }

                guard presets.keys.contains(currencyCodeToCheck) else {
                    owsFail("[Donations] Selected a non-supported currency")
                }

                return OneTimeState(
                    selectedAmount: newValue,
                    profileBadge: profileBadge,
                    presets: presets,
                    minimumAmounts: minimumAmounts,
                    paymentMethodConfiguration: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }

            private func supportedPaymentMethods(
                forCurrencyCode currencyCode: Currency.Code
            ) -> Set<DonationPaymentMethod> {
                DonationUtilities.supportedDonationPaymentMethods(
                    forDonationMode: .oneTime,
                    usingCurrency: currencyCode,
                    withConfiguration: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }
        }

        // MARK: - Monthly state

        struct MonthlyState: Equatable {
            struct MonthlyPaymentRequest: Equatable {
                public let amount: FiatMoney
                public let profileBadge: ProfileBadge
                public let supportedPaymentMethods: Set<DonationPaymentMethod>
            }

            public let subscriptionLevels: [SubscriptionLevel]
            public let selectedCurrencyCode: Currency.Code
            public let selectedSubscriptionLevel: SubscriptionLevel?
            public let currentSubscription: Subscription?
            public let subscriberID: Data?
            public let lastReceiptRedemptionFailure: SubscriptionRedemptionFailureReason
            public let previousMonthlySubscriptionPaymentMethod: DonationPaymentMethod?

            fileprivate let paymentMethodConfiguration: PaymentMethodsConfiguration
            fileprivate let localNumber: String?

            /// Get the currency codes supported by all subscription levels.
            ///
            /// Subscription levels usually come from the server, which means a server
            /// bug could have *some*, but not all, levels support a currency. For
            /// example, only one of them could support EUR. This would be a bug, but we
            /// protect against this by requiring the currency to be supported by *all*
            /// levels, not just one.
            fileprivate static func supportedCurrencyCodes(subscriptionLevels: [SubscriptionLevel]) -> Set<Currency.Code> {
                guard let firstSubscriptionLevel = subscriptionLevels.first else { return [] }
                var result = Set<Currency.Code>(firstSubscriptionLevel.amounts.keys)
                for subscriptionLevel in subscriptionLevels {
                    result.formIntersection(subscriptionLevel.amounts.keys)
                }
                return result
            }

            fileprivate var supportedCurrencyCodes: Set<Currency.Code> {
                Self.supportedCurrencyCodes(subscriptionLevels: subscriptionLevels).supported(
                    forDonationMode: .monthly,
                    withConfig: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }

            fileprivate var selectedProfileBadge: ProfileBadge? {
                selectedSubscriptionLevel?.badge
            }

            public var currentSubscriptionLevel: SubscriptionLevel? {
                if let currentSubscription {
                    return DonationViewsUtil.subscriptionLevelForSubscription(
                        subscriptionLevels: subscriptionLevels,
                        subscription: currentSubscription
                    )
                } else {
                    return nil
                }
            }

            public var paymentRequest: MonthlyPaymentRequest? {
                guard
                    let selectedSubscriptionLevel = selectedSubscriptionLevel,
                    let amount = selectedSubscriptionLevel.amounts[selectedCurrencyCode]
                else {
                    return nil
                }

                return .init(
                    amount: amount,
                    profileBadge: selectedSubscriptionLevel.badge,
                    supportedPaymentMethods: supportedPaymentMethods(forCurrencyCode: selectedCurrencyCode)
                )
            }

            fileprivate func selectCurrencyCode(_ newValue: Currency.Code) -> MonthlyState {
                let isCurrencySupported = subscriptionLevels.allSatisfy { subscriptionLevel in
                    subscriptionLevel.amounts.keys.contains(newValue)
                }
                guard isCurrencySupported else {
                    Logger.warn("[Donations] \(newValue) is not a supported monthly currency code. This may indicate a bug")
                    return self
                }
                return MonthlyState(
                    subscriptionLevels: subscriptionLevels,
                    selectedCurrencyCode: newValue,
                    selectedSubscriptionLevel: selectedSubscriptionLevel,
                    currentSubscription: currentSubscription,
                    subscriberID: subscriberID,
                    lastReceiptRedemptionFailure: lastReceiptRedemptionFailure,
                    previousMonthlySubscriptionPaymentMethod: previousMonthlySubscriptionPaymentMethod,
                    paymentMethodConfiguration: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }

            fileprivate func selectSubscriptionLevel(_ newValue: SubscriptionLevel) -> MonthlyState {
                owsAssert(subscriptionLevels.contains(newValue), "Subscription level not found")
                return MonthlyState(
                    subscriptionLevels: subscriptionLevels,
                    selectedCurrencyCode: selectedCurrencyCode,
                    selectedSubscriptionLevel: newValue,
                    currentSubscription: currentSubscription,
                    subscriberID: subscriberID,
                    lastReceiptRedemptionFailure: lastReceiptRedemptionFailure,
                    previousMonthlySubscriptionPaymentMethod: previousMonthlySubscriptionPaymentMethod,
                    paymentMethodConfiguration: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }

            private func supportedPaymentMethods(
                forCurrencyCode currencyCode: Currency.Code
            ) -> Set<DonationPaymentMethod> {
                DonationUtilities.supportedDonationPaymentMethods(
                    forDonationMode: .monthly,
                    usingCurrency: currencyCode,
                    withConfiguration: paymentMethodConfiguration,
                    localNumber: localNumber
                )
            }
        }

        // MARK: - Load state

        enum LoadState: Equatable {
            case initializing
            case loading
            case loadFailed
            case loaded(oneTime: OneTimeState, monthly: MonthlyState)

            var debugDescription: String {
                switch self {
                case .initializing: return "initializing"
                case .loading: return "loading"
                case .loadFailed: return "loadFailed"
                case .loaded: return "loaded"
                }
            }
        }

        private var loadedState: (OneTimeState, MonthlyState)? {
            switch loadState {
            case let .loaded(oneTime, monthly): return (oneTime, monthly)
            default: return nil
            }
        }

        private var loadedStateOrDie: (OneTimeState, MonthlyState) {
            guard let result = loadedState else {
                owsFail("[Donations] Expected the state to be loaded")
            }
            return result
        }

        // MARK: - Initialization

        public let donateMode: DonateMode
        public let loadState: LoadState

        public init(donateMode: DonateMode) {
            self.donateMode = donateMode
            self.loadState = .initializing
        }

        private init(donateMode: DonateMode, loadState: LoadState) {
            self.donateMode = donateMode
            self.loadState = loadState
        }

        // MARK: - Getters

        public var oneTime: OneTimeState? {
            switch loadState {
            case let .loaded(oneTime, _): return oneTime
            default: return nil
            }
        }

        public var monthly: MonthlyState? {
            switch loadState {
            case let .loaded(_, monthly): return monthly
            default: return nil
            }
        }

        public var selectedCurrencyCode: Currency.Code? {
            switch donateMode {
            case .oneTime: return oneTime?.selectedCurrencyCode
            case .monthly: return monthly?.selectedCurrencyCode
            }
        }

        /// Get the supported currency codes for the loaded donation mode. All
        /// supported currencies should have at least one allowed payment
        /// method.
        ///
        /// If not loaded, returns an empty set.
        public var supportedCurrencyCodes: Set<Currency.Code> {
            switch loadState {
            case .initializing, .loading, .loadFailed:
                return []
            case let .loaded(oneTime, monthly):
                switch donateMode {
                case .oneTime: return oneTime.supportedCurrencyCodes
                case .monthly: return monthly.supportedCurrencyCodes
                }
            }
        }

        public var selectedProfileBadge: ProfileBadge? {
            switch donateMode {
            case .oneTime: return oneTime?.profileBadge
            case .monthly: return monthly?.selectedProfileBadge
            }
        }

        /// Get the donation mode, but return `nil` if it's not loaded.
        public var loadedDonateMode: DonateMode? {
            switch loadState {
            case .initializing, .loading, .loadFailed:
                return nil
            case .loaded:
                return donateMode
            }
        }

        public var debugDescription: String {
            "\(donateMode.debugDescription), \(loadState.debugDescription)"
        }

        // MARK: - Setters

        public func loading() -> State {
            State(donateMode: donateMode, loadState: .loading)
        }

        public func loadFailed() -> State {
            State(donateMode: donateMode, loadState: .loadFailed)
        }

        public func loaded(
            oneTimeConfig: OneTimeConfiguration,
            monthlyConfig: MonthlyConfiguration,
            paymentMethodsConfig: PaymentMethodsConfiguration,
            currentMonthlySubscription: Subscription?,
            subscriberID: Data?,
            lastReceiptRedemptionFailure: SubscriptionRedemptionFailureReason,
            previousMonthlySubscriptionCurrencyCode: Currency.Code?,
            previousMonthlySubscriptionPaymentMethod: DonationPaymentMethod?,
            locale: Locale,
            localNumber: String?
        ) -> State {
            let localeCurrency = locale.currencyCode?.uppercased()

            let oneTime: OneTimeState? = { () -> OneTimeState? in
                let oneTimeSupportedCurrencies = Set(oneTimeConfig.presetAmounts.keys)
                    .supported(
                        forDonationMode: .oneTime,
                        withConfig: paymentMethodsConfig,
                        localNumber: localNumber
                    )

                guard
                    let oneTimeDefaultCurrency = DonationUtilities.chooseDefaultCurrency(
                        preferred: [localeCurrency, "USD", oneTimeSupportedCurrencies.first],
                        supported: oneTimeSupportedCurrencies
                    )
                else {
                    // This indicates a bug, either in the iOS app or the server.
                    owsFailDebug("[Donations] Successfully loaded one-time donations, but a preferred currency could not be found")
                    return nil
                }

                return OneTimeState(
                    selectedAmount: OneTimeState.SelectedAmount.nothingSelected(currencyCode: oneTimeDefaultCurrency),
                    profileBadge: oneTimeConfig.badge,
                    presets: oneTimeConfig.presetAmounts,
                    minimumAmounts: oneTimeConfig.minimumAmounts,
                    paymentMethodConfiguration: paymentMethodsConfig,
                    localNumber: localNumber
                )
            }()

            let monthly: MonthlyState? = {
                let supportedMonthlyCurrencies = MonthlyState.supportedCurrencyCodes(
                    subscriptionLevels: monthlyConfig.levels
                ).supported(
                    forDonationMode: .monthly,
                    withConfig: paymentMethodsConfig,
                    localNumber: localNumber
                )

                guard
                    let monthlyDefaultCurrency = DonationUtilities.chooseDefaultCurrency(
                        preferred: [
                            previousMonthlySubscriptionCurrencyCode,
                            currentMonthlySubscription?.amount.currencyCode,
                            localeCurrency,
                            "USD",
                            supportedMonthlyCurrencies.first
                        ],
                        supported: supportedMonthlyCurrencies
                    )
                else {
                    // This indicates a bug, either in the iOS app or the server.
                    owsFailDebug("[Donations] Successfully loaded monthly donations, but a preferred currency could not be found")
                    return nil
                }

                let selectedMonthlySubscriptionLevel: SubscriptionLevel?
                if let current = currentMonthlySubscription {
                    selectedMonthlySubscriptionLevel = (
                        monthlyConfig.levels.first(where: { current.level == $0.level }) ??
                        monthlyConfig.levels.first
                    )
                } else {
                    selectedMonthlySubscriptionLevel = monthlyConfig.levels.first
                }

                return MonthlyState(
                    subscriptionLevels: monthlyConfig.levels,
                    selectedCurrencyCode: monthlyDefaultCurrency,
                    selectedSubscriptionLevel: selectedMonthlySubscriptionLevel,
                    currentSubscription: currentMonthlySubscription,
                    subscriberID: subscriberID,
                    lastReceiptRedemptionFailure: lastReceiptRedemptionFailure,
                    previousMonthlySubscriptionPaymentMethod: previousMonthlySubscriptionPaymentMethod,
                    paymentMethodConfiguration: paymentMethodsConfig,
                    localNumber: localNumber
                )
            }()

            guard let oneTime, let monthly else {
                return State(donateMode: donateMode, loadState: .loadFailed)
            }

            return State(
                donateMode: donateMode,
                loadState: .loaded(oneTime: oneTime, monthly: monthly)
            )
        }

        /// Change the donation mode.
        public func selectDonateMode(_ newValue: DonateMode) -> State {
            State(donateMode: newValue, loadState: loadState)
        }

        /// Attempt to change the selected currency.
        ///
        /// Most of the time, this will change the currency code for one-time
        /// and monthly states. However, it's possible for the server to support
        /// different currencies for different modes. For example, EUR might be
        /// supported for one-time donations but not monthly ones. Therefore,
        /// this method will only change to a supported currency.
        ///
        /// If the state is not loaded, there will be a fatal error.
        public func selectCurrencyCode(_ newValue: Currency.Code) -> State {
            let (oneTime, monthly) = loadedStateOrDie
            return State(
                donateMode: donateMode,
                loadState: .loaded(
                    oneTime: oneTime.selectCurrencyCode(newValue),
                    monthly: monthly.selectCurrencyCode(newValue)
                )
            )
        }

        /// Change the selected one-time amount.
        ///
        /// The following conditions must be met:
        ///
        /// - The state must be loaded
        /// - The currency code must be supported
        /// - If selecting a preset amount, the amount must be listed
        ///
        /// If any of these conditions are not met, there will be a fatal error.
        public func selectOneTimeAmount(_ newSelectedAmount: OneTimeState.SelectedAmount) -> State {
            let (oneTime, monthly) = loadedStateOrDie
            return State(
                donateMode: donateMode,
                loadState: .loaded(
                    oneTime: oneTime.selectOneTimeAmount(newSelectedAmount),
                    monthly: monthly
                )
            )
        }

        /// Change the selected subscription level.
        ///
        /// The following conditions must be met:
        ///
        /// - The state must be loaded
        /// - The selected level must be in the list
        ///
        /// If any of these conditions are not met, there will be a fatal error.
        public func selectSubscriptionLevel(_ newSubscriptionLevel: SubscriptionLevel) -> State {
            let (oneTime, monthly) = loadedStateOrDie
            return State(
                donateMode: donateMode,
                loadState: .loaded(
                    oneTime: oneTime,
                    monthly: monthly.selectSubscriptionLevel(newSubscriptionLevel)
                )
            )
        }
    }
}

private extension Set where Element == Currency.Code {
    func supported(
        forDonationMode donationMode: DonationMode,
        withConfig paymentMethodConfig: DonateViewController.State.PaymentMethodsConfiguration,
        localNumber: String?
    ) -> Self {
        filter { currencyCode in
            !DonationUtilities.supportedDonationPaymentMethods(
                forDonationMode: donationMode,
                usingCurrency: currencyCode,
                withConfiguration: paymentMethodConfig,
                localNumber: localNumber
            ).isEmpty
        }
    }
}
