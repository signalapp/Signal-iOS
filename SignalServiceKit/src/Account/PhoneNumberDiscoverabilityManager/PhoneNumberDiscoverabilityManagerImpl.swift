//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class PhoneNumberDiscoverabilityManagerImpl: PhoneNumberDiscoverabilityManager {

    public typealias TSAccountManager = SignalServiceKit.TSAccountManagerProtocol & PhoneNumberDiscoverabilitySetter

    private let accountAttributesUpdater: AccountAttributesUpdater
    private let schedulers: Schedulers
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager

    public init(
        accountAttributesUpdater: AccountAttributesUpdater,
        schedulers: Schedulers,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountAttributesUpdater = accountAttributesUpdater
        self.schedulers = schedulers
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
    }

    public func hasDefinedIsDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        return tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber(tx: tx)
    }

    public func isDiscoverableByPhoneNumber(tx: DBReadTransaction) -> Bool {
        return tsAccountManager.isDiscoverableByPhoneNumber(tx: tx)
    }

    public func setIsDiscoverableByPhoneNumber(
        _ isDiscoverable: Bool,
        updateStorageService: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) {
        guard FeatureFlags.phoneNumberDiscoverability else {
            return
        }

        tsAccountManager.setIsDiscoverableByPhoneNumber(isDiscoverable, tx: tx)

        accountAttributesUpdater.scheduleAccountAttributesUpdate(authedAccount: authedAccount, tx: tx)

        if updateStorageService {
            tx.addAsyncCompletion(on: schedulers.global()) {
                self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }
}
