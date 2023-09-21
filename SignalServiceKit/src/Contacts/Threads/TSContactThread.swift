//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSContactThread {

    @objc
    public static func getOrCreateLocalThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        guard let localAddress = tsAccountManager.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    @objc
    public static func getOrCreateLocalThreadWithSneakyTransaction() -> TSThread? {
        assert(!Thread.isMainThread)

        let thread: TSContactThread? = databaseStorage.read { tx in
            guard let localAddress = self.tsAccountManager.localAddress(with: tx) else {
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
