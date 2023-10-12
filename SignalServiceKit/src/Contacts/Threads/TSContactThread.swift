//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension TSContactThread {

    @objc
    public static func getOrCreateLocalThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    @objc
    public static func getOrCreateLocalThreadWithSneakyTransaction() -> TSThread? {
        assert(!Thread.isMainThread)

        let thread: TSContactThread? = databaseStorage.read { tx in
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aciAddress else {
                owsFailDebug("Missing localAddress.")
                return nil
            }
            return TSContactThread.getWithContactAddress(localAddress, transaction: tx)
        }
        if let thread {
            return thread
        }

        return databaseStorage.write { transaction in
            return getOrCreateLocalThread(transaction: transaction)
        }
    }
}

extension TSContactThread {
    var contactServiceId: ServiceId? {
        contactUUID.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
    }
}
