//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSAccountManager {

    // MARK: - Dependencies

    class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    class func getOrCreateLocalThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        guard let localAddress = self.localAddress else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    class func getOrCreateLocalThreadWithSneakyTransaction() -> TSThread? {
        var thread: TSThread?
        databaseStorage.write { transaction in
            thread = getOrCreateLocalThread(transaction: transaction)
        }
        return thread
    }
}
