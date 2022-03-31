// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@objc(SNBlockingManagerRemovalMigration)
public class BlockingManagerRemovalMigration: OWSDatabaseMigration {
    @objc
    class func migrationId() -> String {
        return "004"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        // These are the legacy keys that were used to persist the "block list" state
        let kOWSBlockingManager_BlockListCollection: String = "kOWSBlockingManager_BlockedPhoneNumbersCollection"
        let kOWSBlockingManager_BlockedPhoneNumbersKey: String = "kOWSBlockingManager_BlockedPhoneNumbersKey"
        
        let dbConnection: YapDatabaseConnection = primaryStorage.newDatabaseConnection()
        
        let blockedSessionIds: Set<String> = Set(dbConnection.object(
            forKey: kOWSBlockingManager_BlockedPhoneNumbersKey,
            inCollection: kOWSBlockingManager_BlockListCollection
        ) as? [String] ?? [])

        Storage.write(
            with: { transaction in
                Storage.shared.getAllContacts(with: transaction)
                    .filter { contact -> Bool in blockedSessionIds.contains(contact.sessionID) }
                    .forEach { contact in
                        contact.isBlocked = true
                        Storage.shared.setContact(contact, using: transaction)
                    }
                
                // Now that the values have been migrated we can clear out the old collection
                transaction.removeAllObjects(inCollection: kOWSBlockingManager_BlockListCollection)
                
                self.save(with: transaction) // Intentionally capture self
            },
            completion: {
                completion(true, true)
            }
        )
    }
}
