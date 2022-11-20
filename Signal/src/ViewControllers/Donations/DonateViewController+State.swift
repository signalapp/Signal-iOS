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
        // MARK: - One-time state

        struct OneTimeState: Equatable {
            enum SelectedAmount: Equatable {
                case nothingSelected(currencyCode: Currency.Code)
                case selectedPreset(amount: FiatMoney)
                case choseCustomAmount(amount: FiatMoney)
            }

            enum OneTimePaymentRequest: Equatable {
                case noAmountSelected
                case amountIsTooSmall
                case amountIsTooLarge
                case canContinue(amount: FiatMoney)
            }

            fileprivate let presets: [Currency.Code: DonationUtilities.Preset]
            public let selectedAmount: SelectedAmount
            public let profileBadge: ProfileBadge?

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

            fileprivate var supportedCurrencyCodes: Set<Currency.Code> {
                Set(presets.keys)
            }

            public var paymentRequest: OneTimePaymentRequest {
                guard let amount = amount else {
                    return .noAmountSelected
                }
                if Stripe.isAmountTooSmall(amount) {
                    return .amountIsTooSmall
                }
                if Stripe.isAmountTooLarge(amount) {
                    return .amountIsTooLarge
                }
                return .canContinue(amount: amount)
            }

            fileprivate func selectCurrencyCode(_ newValue: Currency.Code) -> OneTimeState {
                guard presets.keys.contains(newValue) else {
                    Logger.warn("[Donations] \(newValue) is not a supported one-time currency code. This may indicate a bug")
                    return self
                }
                return OneTimeState(
                    presets: presets,
                    selectedAmount: .nothingSelected(currencyCode: newValue),
                    profileBadge: profileBadge
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
                    presets: presets,
                    selectedAmount: newValue,
                    profileBadge: profileBadge
                )
            }
        }

        // MARK: - Monthly state

        struct MonthlyState: Equatable {
            struct MonthlyPaymentRequest: Equatable {
                public let amount: FiatMoney
                public let profileBadge: ProfileBadge
            }

            public let subscriptionLevels: [SubscriptionLevel]
            public let selectedCurrencyCode: Currency.Code
            public let selectedSubscriptionLevel: SubscriptionLevel?
            public let currentSubscription: Subscription?
            public let subscriberID: Data?
            public let lastReceiptRedemptionFailure: SubscriptionRedemptionFailureReason

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
                Self.supportedCurrencyCodes(subscriptionLevels: subscriptionLevels)
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
                    profileBadge: selectedSubscriptionLevel.badge
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
                    lastReceiptRedemptionFailure: lastReceiptRedemptionFailure
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
                    lastReceiptRedemptionFailure: lastReceiptRedemptionFailure
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

        public let donationMode: DonationMode
        public let loadState: LoadState

        public init(donationMode: DonationMode) {
            self.donationMode = donationMode
            self.loadState = .initializing
        }

        private init(donationMode: DonationMode, loadState: LoadState) {
            self.donationMode = donationMode
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
            switch donationMode {
            case .oneTime: return oneTime?.selectedCurrencyCode
            case .monthly: return monthly?.selectedCurrencyCode
            }
        }

        /// Get the supported currency codes for the loaded donation mode.
        ///
        /// If not loaded, returns an empty set.
        public var supportedCurrencyCodes: Set<Currency.Code> {
            switch loadState {
            case .initializing, .loading, .loadFailed:
                return []
            case let .loaded(oneTime, monthly):
                switch donationMode {
                case .oneTime: return oneTime.supportedCurrencyCodes
                case .monthly: return monthly.supportedCurrencyCodes
                }
            }
        }

        public var selectedProfileBadge: ProfileBadge? {
            switch donationMode {
            case .oneTime: return oneTime?.profileBadge
            case .monthly: return monthly?.selectedProfileBadge
            }
        }

        /// Get the donation mode, but return `nil` if it's not loaded.
        public var loadedDonationMode: DonationMode? {
            switch loadState {
            case .initializing, .loading, .loadFailed:
                return nil
            case .loaded:
                return donationMode
            }
        }

        public var debugDescription: String {
            "\(donationMode.debugDescription), \(loadState.debugDescription)"
        }

        // MARK: - Setters

        public func loading() -> State {
            State(donationMode: donationMode, loadState: .loading)
        }

        public func loadFailed() -> State {
            State(donationMode: donationMode, loadState: .loadFailed)
        }

        public func loaded(
            oneTimePresets: [Currency.Code: DonationUtilities.Preset],
            oneTimeBadge: ProfileBadge?,
            monthlySubscriptionLevels: [SubscriptionLevel],
            currentMonthlySubscription: Subscription?,
            subscriberID: Data?,
            lastReceiptRedemptionFailure: SubscriptionRedemptionFailureReason,
            previousMonthlySubscriptionCurrencyCode: Currency.Code?,
            locale: Locale
        ) -> State {
            let localeCurrency = locale.currencyCode?.uppercased()

            let oneTimeDefaultCurrency = DonationUtilities.chooseDefaultCurrency(
                preferred: [localeCurrency, "USD", oneTimePresets.keys.first],
                supported: oneTimePresets.keys
            )
            guard let oneTimeDefaultCurrency = oneTimeDefaultCurrency else {
                // This indicates a bug, either in the iOS app or the server.
                owsFailDebug("[Donations] Successfully loaded one-time donations, but a preferred currency could not be found")
                return State(donationMode: donationMode, loadState: .loadFailed)
            }
            let oneTime = OneTimeState(
                presets: oneTimePresets,
                selectedAmount: .nothingSelected(currencyCode: oneTimeDefaultCurrency),
                profileBadge: oneTimeBadge
            )

            let supportedMonthlyCurrencies = MonthlyState.supportedCurrencyCodes(
                subscriptionLevels: monthlySubscriptionLevels
            )
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
            guard let monthlyDefaultCurrency = monthlyDefaultCurrency else {
                // This indicates a bug, either in the iOS app or the server.
                owsFailDebug("[Donations] Successfully loaded monthly donations, but a preferred currency could not be found")
                return State(donationMode: donationMode, loadState: .loadFailed)
            }
            let selectedMonthlySubscriptionLevel: SubscriptionLevel?
            if let current = currentMonthlySubscription {
                selectedMonthlySubscriptionLevel = (
                    monthlySubscriptionLevels.first(where: { current.level == $0.level }) ??
                    monthlySubscriptionLevels.first
                )
            } else {
                selectedMonthlySubscriptionLevel = monthlySubscriptionLevels.first
            }
            let monthly = MonthlyState(
                subscriptionLevels: monthlySubscriptionLevels,
                selectedCurrencyCode: monthlyDefaultCurrency,
                selectedSubscriptionLevel: selectedMonthlySubscriptionLevel,
                currentSubscription: currentMonthlySubscription,
                subscriberID: subscriberID,
                lastReceiptRedemptionFailure: lastReceiptRedemptionFailure
            )

            return State(
                donationMode: donationMode,
                loadState: .loaded(oneTime: oneTime, monthly: monthly)
            )
        }

        /// Change the donation mode.
        public func selectDonationMode(_ newValue: DonationMode) -> State {
            State(donationMode: newValue, loadState: loadState)
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
                donationMode: donationMode,
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
                donationMode: donationMode,
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
                donationMode: donationMode,
                loadState: .loaded(
                    oneTime: oneTime,
                    monthly: monthly.selectSubscriptionLevel(newSubscriptionLevel)
                )
            )
        }
    }
}
