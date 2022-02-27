@objc(SNMessageRequestsMigration)
public class MessageRequestsMigration : OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "002"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        var contacts: Set<Contact> = Set()
        var threads: [TSThread] = []

        TSThread.enumerateCollectionObjects { object, _ in
            guard let thread: TSThread = object as? TSThread else { return }
            
            if let contactThread: TSContactThread = thread as? TSContactThread {
                let sessionId: String = contactThread.contactSessionID()
                
                if let contact: Contact = Storage.shared.getContact(with: sessionId) {
                    contact.isApproved = true
                    contact.didApproveMe = true
                    contacts.insert(contact)
                }
            }
            else if let groupThread: TSGroupThread = thread as? TSGroupThread, groupThread.isClosedGroup {
                let groupAdmins: [String] = groupThread.groupModel.groupAdminIds
                
                groupAdmins.forEach { sessionId in
                    if let contact: Contact = Storage.shared.getContact(with: sessionId) {
                        contact.isApproved = true
                        contact.didApproveMe = true
                        contacts.insert(contact)
                    }
                }
            }
            
            threads.append(thread)
        }
        
        Storage.write(with: { transaction in
            contacts.forEach { contact in
                Storage.shared.setContact(contact, using: transaction)
            }
            threads.forEach { thread in
                thread.save(with: transaction)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion()
        })
    }
}
