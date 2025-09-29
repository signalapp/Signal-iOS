//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

final public class PhoneNumberDiscoverabilityManagerImpl: PhoneNumberDiscoverabilityManager {

    public typealias TSAccountManager = SignalServiceKit.TSAccountManager & PhoneNumberDiscoverabilitySetter

    private let accountAttributesUpdater: AccountAttributesUpdater
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager

    public init(
        accountAttributesUpdater: AccountAttributesUpdater,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountAttributesUpdater = accountAttributesUpdater
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
    }

    public func phoneNumberDiscoverability(tx: DBReadTransaction) -> PhoneNumberDiscoverability? {
        return tsAccountManager.phoneNumberDiscoverability(tx: tx)
    }

    public func setPhoneNumberDiscoverability(
        _ phoneNumberDiscoverability: PhoneNumberDiscoverability,
        updateAccountAttributes: Bool,
        updateStorageService: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) {
        tsAccountManager.setPhoneNumberDiscoverability(phoneNumberDiscoverability, tx: tx)

        if updateAccountAttributes {
            accountAttributesUpdater.scheduleAccountAttributesUpdate(authedAccount: authedAccount, tx: tx)
        }

        if updateStorageService {
            tx.addSyncCompletion {
                self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }
}
