import SessionProtocolKit

extension Storage {
    
    private static let contactCollection = "LokiContactCollection"

    public func getContact(with sessionID: String) -> Contact? {
        var result: Contact?
        Storage.read { transaction in
            result = transaction.object(forKey: sessionID, inCollection: Storage.contactCollection) as? Contact
        }
        return result
    }
    
    public func setContact(_ contact: Contact, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(contact, forKey: contact.sessionID, inCollection: Storage.contactCollection)
    }
}
