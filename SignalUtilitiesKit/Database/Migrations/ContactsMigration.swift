
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
        var contacts: [Contact] = []
        TSContactThread.enumerateCollectionObjects { object, _ in
            guard let thread = object as? TSContactThread else { return }
            let sessionID = thread.contactSessionID()
            if let contact = Storage.shared.getContact(with: sessionID) {
                contact.isTrusted = true
                contacts.append(contact)
            }
        }
        Storage.write(with: { transaction in
            contacts.forEach { contact in
                Storage.shared.setContact(contact, using: transaction)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion(true, false)
        })
    }
}
