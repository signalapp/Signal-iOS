
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
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        transaction.setObject(contact, forKey: contact.sessionID, inCollection: Storage.contactCollection)
        transaction.addCompletionQueue(DispatchQueue.main) {
            let notificationCenter = NotificationCenter.default
            notificationCenter.post(name: .contactUpdated, object: contact.sessionID)
            if contact.sessionID == getUserHexEncodedPublicKey() {
                notificationCenter.post(name: Notification.Name(kNSNotificationName_LocalProfileDidChange), object: nil)
            } else {
                notificationCenter.post(name: Notification.Name(kNSNotificationName_OtherUsersProfileDidChange), object: nil)
            }
        }
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
