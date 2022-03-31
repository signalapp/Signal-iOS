// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@objc(SNSOGSV4Migration)
public class SOGSV4Migration: OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "005"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        // These collections became redundant in SOGS V4
        let lastMessageServerIDCollection: String = "SNLastMessageServerIDCollection"
        let lastDeletionServerIDCollection: String = "SNLastDeletionServerIDCollection"
        let authTokenCollection: String = "SNAuthTokenCollection"
        
        Storage.write(with: { transaction in
            transaction.removeAllObjects(inCollection: lastMessageServerIDCollection)
            transaction.removeAllObjects(inCollection: lastDeletionServerIDCollection)
            transaction.removeAllObjects(inCollection: authTokenCollection)
            
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion(true, false)
        })
    }
}
