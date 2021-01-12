
@objc(SNContactsMigration)
public class ContactsMigration : OWSDatabaseMigration {

    @objc
    class func migrationId() -> String {
        return "005"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }
    
    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        var contacts: Set<Contact> = []
        Storage.write(with: { transaction in
            // One-on-one chats
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSContactThread else { return }
                let sessionID = thread.contactIdentifier()
                let contact = Contact(sessionID: sessionID)
                var profileOrNil: OWSUserProfile? = nil
                if sessionID == getUserHexEncodedPublicKey() {
                    profileOrNil = OWSProfileManager.shared().getLocalUserProfile(with: transaction)
                } else if let profile = OWSUserProfile.fetch(uniqueId: sessionID, transaction: transaction) {
                    profileOrNil = profile
                }
                if let profile = profileOrNil {
                    contact.displayName = profile.profileName
                    contact.profilePictureURL = profile.avatarUrlPath
                    contact.profilePictureFileName = profile.avatarFileName
                    contact.profilePictureEncryptionKey = profile.profileKey
                }
                contact.threadID = thread.uniqueId
                contacts.insert(contact)
            }
            // Closed groups
            TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSGroupThread, thread.isClosedGroup else { return }
                let memberSessionIDs = thread.groupModel.groupMemberIds
                memberSessionIDs.forEach { memberSessionID in
                    guard !contacts.contains(where: { $0.sessionID == memberSessionID }) else { return }
                    let contact = Contact(sessionID: memberSessionID)
                    if let profile = OWSUserProfile.fetch(uniqueId: memberSessionID, transaction: transaction) {
                        contact.displayName = profile.profileName
                        contact.profilePictureURL = profile.avatarUrlPath
                        contact.profilePictureFileName = profile.avatarFileName
                        contact.profilePictureEncryptionKey = profile.profileKey
                    }
                    // At this point we know we don't have a one-on-one thread with this contact
                    contacts.insert(contact)
                }
            }
            // Save
            contacts.forEach { contact in
                Storage.shared.setContact(contact, using: transaction)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion()
        })
    }
}
