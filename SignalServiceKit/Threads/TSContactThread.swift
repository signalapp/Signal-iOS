//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension TSContactThread {

    @objc
    public convenience init(contactAddress: SignalServiceAddress) {
        let normalizedAddress = NormalizedDatabaseRecordAddress(address: contactAddress)
        owsAssertDebug(normalizedAddress != nil)
        self.init(
            contactUUID: normalizedAddress?.serviceId?.serviceIdUppercaseString,
            contactPhoneNumber: normalizedAddress?.phoneNumber,
        )
    }

    @objc
    public static func getOrCreateLocalThread(transaction: DBWriteTransaction) -> TSContactThread? {
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    @objc
    public static func getOrCreateLocalThreadWithSneakyTransaction() -> TSContactThread? {
        assert(!Thread.isMainThread)

        let thread: TSContactThread? = SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
                owsFailDebug("Missing localAddress.")
                return nil
            }
            return TSContactThread.getWithContactAddress(localAddress, transaction: tx)
        }
        if let thread {
            return thread
        }

        return SSKEnvironment.shared.databaseStorageRef.write { transaction in
            return getOrCreateLocalThread(transaction: transaction)
        }
    }

    @objc
    public static func getOrCreateThread(
        withContactAddress contactAddress: SignalServiceAddress,
        transaction: DBWriteTransaction,
    ) -> TSContactThread {
        owsAssertDebug(contactAddress.isValid)

        let existingThread = ContactThreadFinder().contactThread(for: contactAddress, tx: transaction)
        if let existingThread {
            return existingThread
        }

        let insertedThread = TSContactThread(contactAddress: contactAddress)
        insertedThread.anyInsert(transaction: transaction)
        return insertedThread
    }

    public static func getOrCreateThread(contactAddress: SignalServiceAddress) -> TSContactThread {
        owsAssertDebug(contactAddress.isValid)
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        let existingThread = databaseStorage.read { tx in
            return ContactThreadFinder().contactThread(for: contactAddress, tx: tx)
        }
        if let existingThread {
            return existingThread
        }

        return databaseStorage.write { tx in
            return self.getOrCreateThread(withContactAddress: contactAddress, transaction: tx)
        }
    }

    // Unlike getOrCreateThreadWithContactAddress, this will _NOT_ create a thread if one does not already exist.
    @objc
    public static func getWithContactAddress(
        _ contactAddress: SignalServiceAddress,
        transaction: DBReadTransaction,
    ) -> TSContactThread? {
        return ContactThreadFinder().contactThread(for: contactAddress, tx: transaction)
    }
}
