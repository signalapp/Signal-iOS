//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Stores the result of `ReceiptCredential`-related operations, for donations.
public struct DonationReceiptCredentialResultStore {
    public enum Mode: CaseIterable {
        /// Refers to a one-time boost.
        case oneTimeBoost
        /// Refers to a recurring subscription that was started for the first time.
        case recurringSubscriptionInitiation
        /// Refers to a recurring subscription that automatically renewed.
        case recurringSubscriptionRenewal
    }

    private enum StoreConstants {
        static let errorCollection = "SubRecCredReqErrorStore"
        static let successCollection = "SubRecCredReqSuccessStore"

        static let errorPresentationCollection = "SubRecCredReqErrorPresStore"
        static let successPresentationCollection = "SubRecCredReqSuccessPresStore"

        static let oneTimeBoostKey = "oneTimeBoost"
        static let recurringSubscriptionInitiationKey = "recurringSubscriptionInitiation"
        static let recurringSubscriptionRenewalKey = "recurringSubscriptionRenewal"
    }

    private let errorKVStore: KeyValueStore
    private let successKVStore: KeyValueStore

    private let errorPresentationKVStore: KeyValueStore
    private let successPresentationKVStore: KeyValueStore

    init() {
        errorKVStore = KeyValueStore(collection: StoreConstants.errorCollection)
        successKVStore = KeyValueStore(collection: StoreConstants.successCollection)

        errorPresentationKVStore = KeyValueStore(collection: StoreConstants.errorPresentationCollection)
        successPresentationKVStore = KeyValueStore(collection: StoreConstants.successPresentationCollection)
    }

    private func key(mode: Mode) -> String {
        switch mode {
        case .oneTimeBoost: return StoreConstants.oneTimeBoostKey
        case .recurringSubscriptionInitiation: return StoreConstants.recurringSubscriptionInitiationKey
        case .recurringSubscriptionRenewal: return StoreConstants.recurringSubscriptionRenewalKey
        }
    }

    // MARK: -

    public func getRequestErrorForAnyRecurringSubscription(
        tx: DBReadTransaction,
    ) -> DonationReceiptCredentialRequestError? {
        if
            let initiationError = getRequestError(
                errorMode: .recurringSubscriptionInitiation,
                tx: tx,
            )
        {
            return initiationError
        } else if
            let renewalError = getRequestError(
                errorMode: .recurringSubscriptionRenewal,
                tx: tx,
            )
        {
            return renewalError
        }

        return nil
    }

    public func getRequestError(
        errorMode: Mode,
        tx: DBReadTransaction,
    ) -> DonationReceiptCredentialRequestError? {
        return try? errorKVStore.getCodableValue(
            forKey: key(mode: errorMode),
            transaction: tx,
        )
    }

    // MARK: -

    public func setRequestError(
        error: DonationReceiptCredentialRequestError,
        errorMode: Mode,
        tx: DBWriteTransaction,
    ) {
        let modeKey = key(mode: errorMode)
        try? errorKVStore.setCodable(error, key: modeKey, transaction: tx)

        // Setting a new error means we haven't presented it, either.
        errorPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    public func clearRequestErrorForAnyRecurringSubscription(tx: DBWriteTransaction) {
        clearRequestError(errorMode: .recurringSubscriptionInitiation, tx: tx)
        clearRequestError(errorMode: .recurringSubscriptionRenewal, tx: tx)
    }

    public func clearRequestError(errorMode: Mode, tx: DBWriteTransaction) {
        let modeKey = key(mode: errorMode)
        errorKVStore.removeValue(forKey: modeKey, transaction: tx)

        // Clearing the error means we haven't presented it, either.
        errorPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    // MARK: -

    public func getRedemptionSuccessForAnyRecurringSubscription(
        tx: DBReadTransaction,
    ) -> DonationReceiptCredentialRedemptionSuccess? {
        if
            let initiationSuccess = getRedemptionSuccess(
                successMode: .recurringSubscriptionInitiation,
                tx: tx,
            )
        {
            return initiationSuccess
        } else if
            let renewalSuccess = getRedemptionSuccess(
                successMode: .recurringSubscriptionRenewal,
                tx: tx,
            )
        {
            return renewalSuccess
        }

        return nil
    }

    public func getRedemptionSuccess(
        successMode: Mode,
        tx: DBReadTransaction,
    ) -> DonationReceiptCredentialRedemptionSuccess? {
        return try? successKVStore.getCodableValue(
            forKey: key(mode: successMode),
            transaction: tx,
        )
    }

    // MARK: -

    public func setRedemptionSuccess(
        success: DonationReceiptCredentialRedemptionSuccess,
        successMode: Mode,
        tx: DBWriteTransaction,
    ) {
        let modeKey = key(mode: successMode)
        try? successKVStore.setCodable(
            success,
            key: modeKey,
            transaction: tx,
        )

        // Setting a new success means we haven't presented it, either.
        successPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    public func clearRedemptionSuccessForAnyRecurringSubscription(tx: DBWriteTransaction) {
        clearRedemptionSuccess(successMode: .recurringSubscriptionInitiation, tx: tx)
        clearRedemptionSuccess(successMode: .recurringSubscriptionRenewal, tx: tx)
    }

    public func clearRedemptionSuccess(
        successMode: Mode,
        tx: DBWriteTransaction,
    ) {
        let modeKey = key(mode: successMode)
        successKVStore.removeValue(
            forKey: modeKey,
            transaction: tx,
        )

        // Clearing the success means we haven't presented it, either.
        successPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    // MARK: -

    public func hasPresentedError(errorMode: Mode, tx: DBReadTransaction) -> Bool {
        return errorPresentationKVStore.getBool(
            key(mode: errorMode),
            defaultValue: false,
            transaction: tx,
        )
    }

    public func setHasPresentedError(errorMode: Mode, tx: DBWriteTransaction) {
        errorPresentationKVStore.setBool(
            true,
            key: key(mode: errorMode),
            transaction: tx,
        )
    }

    public func hasPresentedSuccess(successMode: Mode, tx: DBReadTransaction) -> Bool {
        return successPresentationKVStore.getBool(
            key(mode: successMode),
            defaultValue: false,
            transaction: tx,
        )
    }

    public func setHasPresentedSuccess(successMode: Mode, tx: DBWriteTransaction) {
        successPresentationKVStore.setBool(
            true,
            key: key(mode: successMode),
            transaction: tx,
        )
    }
}
