// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import YapDatabase
import SessionMessagingKit

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
        
        // Note: These will be done in the YDB to GRDB migration but have added it here to be safe
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Contact.self,
            forClassName: "SNContact"
        )
        
        let dbConnection: YapDatabaseConnection = primaryStorage.newDatabaseConnection()
        
        let blockedSessionIds: Set<String> = Set(dbConnection.object(
            forKey: kOWSBlockingManager_BlockedPhoneNumbersKey,
            inCollection: kOWSBlockingManager_BlockListCollection
        ) as? [String] ?? [])

        Storage.write(
            with: { transaction in
                var result: Set<SMKLegacy._Contact> = []
                
                transaction.enumerateRows(inCollection: SMKLegacy.contactCollection) { _, object, _, _ in
                    guard let contact = object as? SMKLegacy._Contact else { return }
                    result.insert(contact)
                }
                
                result
                    .filter { contact -> Bool in blockedSessionIds.contains(contact.sessionID) }
                    .forEach { contact in
                        contact.isBlocked = true
                        transaction.setObject(contact, forKey: contact.sessionID, inCollection: SMKLegacy.contactCollection)
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
