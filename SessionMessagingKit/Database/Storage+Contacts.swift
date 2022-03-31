
extension Storage {
    
    private static let contactCollection = "LokiContactCollection"

    @objc(getContactWithSessionID:)
    public func getContact(with sessionID: String) -> Contact? {
        var result: Contact?
        Storage.read { transaction in
            result = self.getContact(with: sessionID, using: transaction)
        }
        return result
    }
    
    @objc(getContactWithSessionID:using:)
    public func getContact(with sessionID: String, using transaction: Any) -> Contact? {
        var result: Contact?
        let transaction = transaction as! YapDatabaseReadTransaction
        result = transaction.object(forKey: sessionID, inCollection: Storage.contactCollection) as? Contact
        if let result = result, result.sessionID == getUserHexEncodedPublicKey() {
            result.isTrusted = true // Always trust ourselves
        }
        return result
    }
    
    @objc(setContact:usingTransaction:)
    public func setContact(_ contact: Contact, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let oldContact = getContact(with: contact.sessionID, using: transaction)
        if contact.sessionID == getUserHexEncodedPublicKey() {
            contact.isTrusted = true // Always trust ourselves
        }
        transaction.setObject(contact, forKey: contact.sessionID, inCollection: Storage.contactCollection)
        transaction.addCompletionQueue(DispatchQueue.main) {
            // Delete old profile picture if needed
            if let oldProfilePictureFileName = oldContact?.profilePictureFileName,
                oldProfilePictureFileName != contact.profilePictureFileName {
                let path = OWSUserProfile.profileAvatarFilepath(withFilename: oldProfilePictureFileName)
                DispatchQueue.global(qos: .default).async {
                    OWSFileSystem.deleteFileIfExists(path)
                }
            }
            // Post notification
            let notificationCenter = NotificationCenter.default
            notificationCenter.post(name: .contactUpdated, object: contact.sessionID)
            
            if contact.sessionID == getUserHexEncodedPublicKey() {
                notificationCenter.post(name: Notification.Name(kNSNotificationName_LocalProfileDidChange), object: nil)
            }
            else {
                let userInfo = [ kNSNotificationKey_ProfileRecipientId : contact.sessionID ]
                notificationCenter.post(name: Notification.Name(kNSNotificationName_OtherUsersProfileDidChange), object: nil, userInfo: userInfo)
            }
            
            if contact.isBlocked != oldContact?.isBlocked {
                notificationCenter.post(name: .contactBlockedStateChanged, object: contact.sessionID)
            }
        }
    }
    
    @objc public func getAllContacts() -> Set<Contact> {
        var result: Set<Contact> = []
        Storage.read { transaction in
            result = self.getAllContacts(with: transaction)
        }
        return result
    }
    
    @objc public func getAllContacts(with transaction: YapDatabaseReadTransaction) -> Set<Contact> {
        var result: Set<Contact> = []
        transaction.enumerateRows(inCollection: Storage.contactCollection) { _, object, _, _ in
            guard let contact = object as? Contact else { return }
            result.insert(contact)
        }
        return result
    }
}
