//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol UsernameEducationManager {
    func shouldShowUsernameEducation(transaction: DBReadTransaction) -> Bool
    func setShouldShowUsernameEducation(_ shouldShow: Bool, transaction: DBWriteTransaction)
}

struct UsernameEducationManagerImpl: UsernameEducationManager {
    private enum Constants {
        static let collectionName: String = "UsernameEducation"
        static let shouldShowUsernameEducationKey: String = "shouldShow"
    }

    private let keyValueStore: KeyValueStore

    init(keyValueStoreFactory: KeyValueStoreFactory) {
        keyValueStore = keyValueStoreFactory.keyValueStore(collection: Constants.collectionName)
    }

    func shouldShowUsernameEducation(transaction: DBReadTransaction) -> Bool {
        keyValueStore.getBool(
            Constants.shouldShowUsernameEducationKey,
            defaultValue: true,
            transaction: transaction
        )
    }

    func setShouldShowUsernameEducation(_ shouldShow: Bool, transaction: DBWriteTransaction) {
        keyValueStore.setBool(
            shouldShow,
            key: Constants.shouldShowUsernameEducationKey,
            transaction: transaction
        )
    }
}
