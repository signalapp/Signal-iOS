// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import YapDatabase
import SessionMessagingKit

@objc(SNContactsMigration)
public class ContactsMigration: OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "001"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }
    
    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        var contacts: [SMKLegacy._Contact] = []
        
        // Note: These will be done in the YDB to GRDB migration but have added it here to be safe
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Thread.self,
            forClassName: "TSThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ContactThread.self,
            forClassName: "TSContactThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Contact.self,
            forClassName: "SNContact"
        )

        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.threadCollection) { _, object, _ in
                guard let thread = object as? SMKLegacy._ContactThread else { return }
                
                let sessionId: String = SMKLegacy._ContactThread.contactSessionId(fromThreadId: thread.uniqueId)
                let contact: SMKLegacy._Contact? = transaction.object(forKey: sessionId, inCollection: SMKLegacy.contactCollection) as? SMKLegacy._Contact
                
                contact?.isTrusted = true
                contacts = contacts.appending(contact)
            }
        }
        
        Storage.write(with: { transaction in
            contacts.forEach { contact in
                transaction.setObject(contact, forKey: contact.sessionID, inCollection: SMKLegacy.contactCollection)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion(true, false)
        })
    }
}
