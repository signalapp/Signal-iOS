//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class TSAccountManagerImpl: TSAccountManagerProtocol {

    private let dateProvider: DateProvider
    private let db: DB
    private let schedulers: Schedulers

    private let accountStateKvStore: KeyValueStore

    public init(
        dateProvider: @escaping DateProvider,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.accountStateKvStore = keyValueStoreFactory.keyValueStore(
            collection: "TSStorageUserAccountCollection"
        )
        self.schedulers = schedulers
    }

    public func warmCaches() {
        // TODO
    }

    public var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? {
        return nil // TODO
    }

    public func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return nil // TODO
    }
}
