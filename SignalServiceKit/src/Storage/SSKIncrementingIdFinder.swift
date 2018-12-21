//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKIncrementingIdFinder: NSObject {

    @objc
    public static let collectionName = "IncrementingIdCollection"

    @objc
    public class func previousId(key: String, transaction: YapDatabaseReadTransaction) -> UInt64 {
        let previousId: UInt64 = transaction.object(forKey: key, inCollection: collectionName) as? UInt64 ?? 0
        return previousId
    }

    @objc
    public class func nextId(key: String, transaction: YapDatabaseReadWriteTransaction) -> UInt64 {
        let previousId: UInt64 = transaction.object(forKey: key, inCollection: collectionName) as? UInt64 ?? 0
        let nextId: UInt64 = previousId + 1

        transaction.setObject(nextId, forKey: key, inCollection: collectionName)
        return nextId
    }
}
