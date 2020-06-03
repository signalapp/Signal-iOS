//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS116UpdatePrekeys: YDBDatabaseMigration {

    // MARK: - Dependencies

    var preKeyStore: SSKPreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        return "116"
    }

    override public func runUp(with transaction: YapDatabaseReadWriteTransaction) {
        Bench(title: "\(self.logTag)") {
            let keyStore = self.preKeyStore.keyStore
            do {
                var keys: [String] = keyStore.allKeys(transaction: transaction.asAnyRead)
                try Batching.loop(batchSize: Batching.kDefaultBatchSize,
                                  loopBlock: { stop in
                                    guard let key = keys.popLast() else {
                                        stop.pointee = true
                                        return
                                    }
                                    guard let record = keyStore.getObject(forKey: key, transaction: transaction.asAnyRead) as? PreKeyRecord else {
                                        owsFailDebug("Missing record.")
                                        return
                                    }
                                    guard record.createdAt == nil else {
                                        owsFailDebug("Unexpected createdAt.")
                                        return
                                    }
                                    record.setCreatedAtToNow()
                                    keyStore.setObject(record, key: key, transaction: transaction.asAnyWrite)
                })
            } catch {
                owsFail("Migration failed.")
            }
        }
    }
}
