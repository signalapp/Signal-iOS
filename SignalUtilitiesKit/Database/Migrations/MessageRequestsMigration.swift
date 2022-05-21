// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import YapDatabase
import SessionMessagingKit

@objc(SNMessageRequestsMigration)
public class MessageRequestsMigration: OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "002"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        let userPublicKey: String = getUserHexEncodedPublicKey()
        var contacts: Set<SMKLegacy._Contact> = Set()
        var threads: [SMKLegacy._Thread] = []
        
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
            SMKLegacy._GroupThread.self,
            forClassName: "TSGroupThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._GroupModel.self,
            forClassName: "TSGroupModel"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Contact.self,
            forClassName: "SNContact"
        )

        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.threadCollection) { _, object, _ in
                guard let thread: SMKLegacy._Thread = object as? SMKLegacy._Thread else { return }
            
                if thread is SMKLegacy._ContactThread {
                    let sessionId: String = SMKLegacy._ContactThread.contactSessionId(fromThreadId: thread.uniqueId)
                    
                    if let contact: SMKLegacy._Contact = transaction.object(forKey: sessionId, inCollection: SMKLegacy.contactCollection) as? SMKLegacy._Contact {
                        contact.isApproved = true
                        contact.didApproveMe = true
                        contacts.insert(contact)
                    }
                }
                else if let groupThread: SMKLegacy._GroupThread = thread as? SMKLegacy._GroupThread, groupThread.isClosedGroup {
                    let groupAdmins: [String] = groupThread.groupModel.groupAdminIds
                    
                    groupAdmins.forEach { sessionId in
                        if let contact: SMKLegacy._Contact = transaction.object(forKey: sessionId, inCollection: SMKLegacy.contactCollection) as? SMKLegacy._Contact {
                            contact.isApproved = true
                            contact.didApproveMe = true
                            contacts.insert(contact)
                        }
                    }
                }
                
                threads.append(thread)
            }
            
            if let user = transaction.object(forKey: userPublicKey, inCollection: SMKLegacy.contactCollection) as? SMKLegacy._Contact {
                user.isApproved = true
                user.didApproveMe = true
                contacts.insert(user)
            }
        }
        
        Storage.write(with: { transaction in
            contacts.forEach { contact in
                transaction.setObject(contact, forKey: contact.sessionID, inCollection: SMKLegacy.contactCollection)
            }
            threads.forEach { thread in
                transaction.setObject(thread, forKey: thread.uniqueId, inCollection: SMKLegacy.threadCollection)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion(true, true)
        })
    }
}
