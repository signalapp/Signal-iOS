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
        var contacts: [SessionMessagingKit.Legacy.Contact] = []
        TSContactThread.enumerateCollectionObjects { object, _ in
            guard let thread = object as? TSContactThread else { return }
            let sessionID = thread.contactSessionID()
            var contact: SessionMessagingKit.Legacy.Contact?
            
            Storage.read { transaction in
                contact = transaction.object(forKey: sessionID, inCollection: Legacy.contactCollection) as? SessionMessagingKit.Legacy.Contact
            }
            
            if let contact: SessionMessagingKit.Legacy.Contact = contact {
                contact.isTrusted = true
                contacts.append(contact)
            }
        }
        Storage.write(with: { transaction in
            contacts.forEach { contact in
                transaction.setObject(contact, forKey: contact.sessionID, inCollection: Legacy.contactCollection)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion(true, false)
        })
    }
}
