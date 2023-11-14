//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum _SubscriptionReceiptCredentialResultStore_Mode {
    case oneTimeBoost
    case recurringSubscription
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

    // MARK: Error presentation

    func hasPresentedError(errorMode: Mode, tx: DBReadTransaction) -> Bool

    func setHasPresentedError(errorMode: Mode, tx: DBWriteTransaction)

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
        static let errorPresentationCollection = "SubRecCredReqErrorPresStore"
        static let successCollection = "SubRecCredReqSuccessStore"

        static let oneTimeBoostKey = "oneTimeBoost"
        static let recurringSubscriptionKey = "recurringSubscription"
    }

    private let legacyErrorKVStore: KeyValueStore
    private let errorKVStore: KeyValueStore
    private let errorPresentationKVStore: KeyValueStore
    private let successKVStore: KeyValueStore

    init(kvStoreFactory: KeyValueStoreFactory) {
        legacyErrorKVStore = kvStoreFactory.keyValueStore(collection: LegacyErrorConstants.collection)
        errorKVStore = kvStoreFactory.keyValueStore(collection: StoreConstants.errorCollection)
        errorPresentationKVStore = kvStoreFactory.keyValueStore(collection: StoreConstants.errorPresentationCollection)
        successKVStore = kvStoreFactory.keyValueStore(collection: StoreConstants.successCollection)
    }

    private func key(mode: Mode) -> String {
        switch mode {
        case .oneTimeBoost: return StoreConstants.oneTimeBoostKey
        case .recurringSubscription: return StoreConstants.recurringSubscriptionKey
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
        case .recurringSubscription:
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
        case .recurringSubscription:
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

    // MARK: - Error presentation

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
        try? successKVStore.setCodable(
            success,
            key: key(mode: successMode),
            transaction: tx
        )
    }

    func clearRedemptionSuccess(
        successMode: Mode,
        tx: DBWriteTransaction
    ) {
        successKVStore.removeValue(
            forKey: key(mode: successMode),
            transaction: tx
        )
    }
}
