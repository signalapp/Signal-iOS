//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum _SubscriptionReceiptCredentialResultStore_Mode: CaseIterable {
    /// Refers to a one-time boost.
    case oneTimeBoost
    /// Refers to a recurring subscription that was started for the first time.
    case recurringSubscriptionInitiation
    /// Refers to a recurring subscription that automatically renewed.
    case recurringSubscriptionRenewal
}

public protocol SubscriptionReceiptCredentialResultStore {
    typealias Mode = _SubscriptionReceiptCredentialResultStore_Mode

    // MARK: Error persistence

    func getRequestError(
        errorMode: Mode,
        tx: DBReadTransaction
    ) -> SubscriptionReceiptCredentialRequestError?

    func setRequestError(
        error: SubscriptionReceiptCredentialRequestError,
        errorMode: Mode,
        tx: DBWriteTransaction
    )

    func clearRequestError(
        errorMode: Mode,
        tx: DBWriteTransaction
    )

    // MARK: Success persistence

    func getRedemptionSuccess(
        successMode: Mode,
        tx: DBReadTransaction
    ) -> SubscriptionReceiptCredentialRedemptionSuccess?

    func setRedemptionSuccess(
        success: SubscriptionReceiptCredentialRedemptionSuccess,
        successMode: Mode,
        tx: DBWriteTransaction
    )

    func clearRedemptionSuccess(
        successMode: Mode,
        tx: DBWriteTransaction
    )

    // MARK: Presentation

    func hasPresentedError(errorMode: Mode, tx: DBReadTransaction) -> Bool
    func setHasPresentedError(errorMode: Mode, tx: DBWriteTransaction)

    func hasPresentedSuccess(successMode: Mode, tx: DBReadTransaction) -> Bool
    func setHasPresentedSuccess(successMode: Mode, tx: DBWriteTransaction)
}

public extension SubscriptionReceiptCredentialResultStore {
    func getRequestErrorForAnyRecurringSubscription(
        tx: DBReadTransaction
    ) -> SubscriptionReceiptCredentialRequestError? {
        if let initiationError = getRequestError(
            errorMode: .recurringSubscriptionInitiation, tx: tx
        ) {
            return initiationError
        } else if let renewalError = getRequestError(
            errorMode: .recurringSubscriptionRenewal, tx: tx
        ) {
            return renewalError
        }

        return nil
    }

    func getRedemptionSuccessForAnyRecurringSubscription(
        tx: DBReadTransaction
    ) -> SubscriptionReceiptCredentialRedemptionSuccess? {
        if let initiationSuccess = getRedemptionSuccess(
            successMode: .recurringSubscriptionInitiation, tx: tx
        ) {
            return initiationSuccess
        } else if let renewalSuccess = getRedemptionSuccess(
            successMode: .recurringSubscriptionRenewal, tx: tx
        ) {
            return renewalSuccess
        }

        return nil
    }

    func clearRequestErrorForAnyRecurringSubscription(tx: DBWriteTransaction) {
        clearRequestError(errorMode: .recurringSubscriptionInitiation, tx: tx)
        clearRequestError(errorMode: .recurringSubscriptionRenewal, tx: tx)
    }

    func clearRedemptionSuccessForAnyRecurringSubscription(tx: DBWriteTransaction) {
        clearRedemptionSuccess(successMode: .recurringSubscriptionInitiation, tx: tx)
        clearRedemptionSuccess(successMode: .recurringSubscriptionRenewal, tx: tx)
    }
}

final class SubscriptionReceiptCredentialResultStoreImpl: SubscriptionReceiptCredentialResultStore {
    /// Uses values taken from ``SubscriptionManagerImpl``, to preserve
    /// compatibility with legacy data stored there.
    ///
    /// Specifically, recurring subscriptions have historically stored error
    /// codes. One-time boosts never stored an error code, and neither stored
    /// any information beyond the error code.
    private enum LegacyErrorConstants {
        static let collection = "SubscriptionKeyValueStore"
        static let recurringSubscriptionKey = "lastSubscriptionReceiptRequestFailedKey"
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

    private let legacyErrorKVStore: KeyValueStore

    private let errorKVStore: KeyValueStore
    private let successKVStore: KeyValueStore

    private let errorPresentationKVStore: KeyValueStore
    private let successPresentationKVStore: KeyValueStore

    init(kvStoreFactory: KeyValueStoreFactory) {
        legacyErrorKVStore = kvStoreFactory.keyValueStore(collection: LegacyErrorConstants.collection)

        errorKVStore = kvStoreFactory.keyValueStore(collection: StoreConstants.errorCollection)
        successKVStore = kvStoreFactory.keyValueStore(collection: StoreConstants.successCollection)

        errorPresentationKVStore = kvStoreFactory.keyValueStore(collection: StoreConstants.errorPresentationCollection)
        successPresentationKVStore = kvStoreFactory.keyValueStore(collection: StoreConstants.successPresentationCollection)
    }

    private func key(mode: Mode) -> String {
        switch mode {
        case .oneTimeBoost: return StoreConstants.oneTimeBoostKey
        case .recurringSubscriptionInitiation: return StoreConstants.recurringSubscriptionInitiationKey
        case .recurringSubscriptionRenewal: return StoreConstants.recurringSubscriptionRenewalKey
        }
    }

    // MARK: - Error persistence

    func getRequestError(
        errorMode: Mode,
        tx: DBReadTransaction
    ) -> SubscriptionReceiptCredentialRequestError? {
        if let error: SubscriptionReceiptCredentialRequestError = try? errorKVStore.getCodableValue(
            forKey: key(mode: errorMode),
            transaction: tx
        ) {
            return error
        } else if
            let legacyErrorCodeInt = legacyErrorKVStore.getInt(
                LegacyErrorConstants.recurringSubscriptionKey, transaction: tx
            ),
            let legacyErrorCode = SubscriptionReceiptCredentialRequestError.ErrorCode(
                rawValue: legacyErrorCodeInt
            )
        {
            // See note above – we might have just the error code int, and if so
            // we'll do our best without the rest of the state.

            return SubscriptionReceiptCredentialRequestError(
                legacyErrorCode: legacyErrorCode
            )
        }

        return nil
    }

    func setRequestError(
        error: SubscriptionReceiptCredentialRequestError,
        errorMode: Mode,
        tx: DBWriteTransaction
    ) {
        switch errorMode {
        case .oneTimeBoost: break
        case .recurringSubscriptionInitiation, .recurringSubscriptionRenewal:
            legacyErrorKVStore.removeValue(
                forKey: LegacyErrorConstants.recurringSubscriptionKey,
                transaction: tx
            )
        }

        let modeKey = key(mode: errorMode)
        try? errorKVStore.setCodable(error, key: modeKey, transaction: tx)

        // Setting a new error means we haven't presented it, either.
        errorPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    func clearRequestError(errorMode: Mode, tx: DBWriteTransaction) {
        switch errorMode {
        case .oneTimeBoost: break
        case .recurringSubscriptionInitiation, .recurringSubscriptionRenewal:
            legacyErrorKVStore.removeValue(
                forKey: LegacyErrorConstants.recurringSubscriptionKey,
                transaction: tx
            )
        }

        let modeKey = key(mode: errorMode)
        errorKVStore.removeValue(forKey: modeKey, transaction: tx)

        // Clearing the error means we haven't presented it, either.
        errorPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    // MARK: - Success persistence

    func getRedemptionSuccess(
        successMode: Mode,
        tx: DBReadTransaction
    ) -> SubscriptionReceiptCredentialRedemptionSuccess? {
        return try? successKVStore.getCodableValue(
            forKey: key(mode: successMode),
            transaction: tx
        )
    }

    func setRedemptionSuccess(
        success: SubscriptionReceiptCredentialRedemptionSuccess,
        successMode: Mode,
        tx: DBWriteTransaction
    ) {
        let modeKey = key(mode: successMode)
        try? successKVStore.setCodable(
            success,
            key: modeKey,
            transaction: tx
        )

        // Setting a new success means we haven't presented it, either.
        successPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    func clearRedemptionSuccess(
        successMode: Mode,
        tx: DBWriteTransaction
    ) {
        let modeKey = key(mode: successMode)
        successKVStore.removeValue(
            forKey: modeKey,
            transaction: tx
        )

        // Clearing the success means we haven't presented it, either.
        successPresentationKVStore.removeValue(forKey: modeKey, transaction: tx)
    }

    // MARK: - Presentation

    func hasPresentedError(errorMode: Mode, tx: DBReadTransaction) -> Bool {
        return errorPresentationKVStore.getBool(
            key(mode: errorMode),
            defaultValue: false,
            transaction: tx
        )
    }

    func setHasPresentedError(errorMode: Mode, tx: DBWriteTransaction) {
        errorPresentationKVStore.setBool(
            true,
            key: key(mode: errorMode),
            transaction: tx
        )
    }

    func hasPresentedSuccess(successMode: Mode, tx: DBReadTransaction) -> Bool {
        return successPresentationKVStore.getBool(
            key(mode: successMode),
            defaultValue: false,
            transaction: tx
        )
    }

    func setHasPresentedSuccess(successMode: Mode, tx: DBWriteTransaction) {
        successPresentationKVStore.setBool(
            true,
            key: key(mode: successMode),
            transaction: tx
        )
    }
}
