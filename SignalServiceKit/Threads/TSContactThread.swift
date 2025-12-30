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
}
