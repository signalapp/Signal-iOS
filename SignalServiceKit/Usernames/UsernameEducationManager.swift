//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol UsernameEducationManager {
    func shouldShowUsernameEducation(tx: DBReadTransaction) -> Bool
    func setShouldShowUsernameEducation(_ shouldShow: Bool, tx: DBWriteTransaction)

    func shouldShowUsernameLinkTooltip(tx: DBReadTransaction) -> Bool
    func setShouldShowUsernameLinkTooltip(_ shouldShow: Bool, tx: DBWriteTransaction)
}

struct UsernameEducationManagerImpl: UsernameEducationManager {
    private enum Constants {
        static let collectionName: String = "UsernameEducation"
        static let shouldShowUsernameEducationKey: String = "shouldShow"
        static let shouldShowUsernameLinkTooltipKey: String = "shouldShowTooltip"
    }

    private let keyValueStore: KeyValueStore

    init(keyValueStoreFactory: KeyValueStoreFactory) {
        keyValueStore = keyValueStoreFactory.keyValueStore(collection: Constants.collectionName)
    }

    func shouldShowUsernameEducation(tx: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(
            Constants.shouldShowUsernameEducationKey,
            defaultValue: true,
            transaction: tx
        )
    }

    func setShouldShowUsernameEducation(_ shouldShow: Bool, tx: DBWriteTransaction) {
        keyValueStore.setBool(
            shouldShow,
            key: Constants.shouldShowUsernameEducationKey,
            transaction: tx
        )
    }

    func shouldShowUsernameLinkTooltip(tx: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(
            Constants.shouldShowUsernameLinkTooltipKey,
            defaultValue: true,
            transaction: tx
        )
    }

    func setShouldShowUsernameLinkTooltip(_ shouldShow: Bool, tx: DBWriteTransaction) {
        keyValueStore.setBool(
            shouldShow,
            key: Constants.shouldShowUsernameLinkTooltipKey,
            transaction: tx
        )
    }
}
