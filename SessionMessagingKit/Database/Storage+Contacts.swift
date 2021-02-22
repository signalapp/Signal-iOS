
extension Storage {
    
    private static let contactCollection = "LokiContactCollection"

    @objc(getContactWithSessionID:)
    public func getContact(with sessionID: String) -> Contact? {
        var result: Contact?
        Storage.read { transaction in
            result = transaction.object(forKey: sessionID, inCollection: Storage.contactCollection) as? Contact
        }
        return result
    }
    
    @objc(setContact:usingTransaction:)
    public func setContact(_ contact: Contact, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(contact, forKey: contact.sessionID, inCollection: Storage.contactCollection)
    }
    
    public func getAllContacts() -> Set<Contact> {
        var result: Set<Contact> = []
        Storage.read { transaction in
            transaction.enumerateRows(inCollection: Storage.contactCollection) { _, object, _, _ in
                guard let contact = object as? Contact else { return }
                result.insert(contact)
            }
        }
        return result
    }
}
