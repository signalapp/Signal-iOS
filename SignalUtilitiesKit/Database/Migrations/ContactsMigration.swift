// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionMessagingKit

@objc(SNContactsMigration)
public class ContactsMigration : OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "001"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }
    
    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        var contacts: [SMKLegacy._Contact] = []
        TSContactThread.enumerateCollectionObjects { object, _ in
            guard let thread = object as? TSContactThread else { return }
            let sessionID = thread.contactSessionID()
            var contact: SMKLegacy._Contact?
            
            Storage.read { transaction in
                contact = transaction.object(forKey: sessionID, inCollection: SMKLegacy.contactCollection) as? SMKLegacy._Contact
            }
            
            if let contact: SMKLegacy._Contact = contact {
                contact.isTrusted = true
                contacts.append(contact)
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
