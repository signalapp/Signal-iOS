
enum ContactUtilities {
    private static func approvedContact(in threadObject: Any, using transaction: Any) -> Contact? {
        guard let thread: TSContactThread = threadObject as? TSContactThread else { return nil }
        guard thread.shouldBeVisible else { return nil }
        guard let contact: Contact = Storage.shared.getContact(with: thread.contactSessionID(), using: transaction) else {
            return nil
        }
        guard contact.didApproveMe else { return nil }
        
        return contact
    }

    static func getAllContacts() -> [String] {
        // Collect all contacts
        var result: [Contact] = []
        Storage.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let contact: Contact = approvedContact(in: object, using: transaction) else { return }
                
                result.append(contact)
            }
        }
        func getDisplayName(for publicKey: String) -> String {
            return Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
        }
        
        // Remove the current user
        if let index = result.firstIndex(where: { $0.sessionID == getUserHexEncodedPublicKey() }) {
            result.remove(at: index)
        }
        
        // Sort alphabetically
        return result
            .sorted(by: { lhs, rhs in
                (lhs.displayName(for: .regular) ?? lhs.sessionID) < (rhs.displayName(for: .regular) ?? rhs.sessionID)
            })
            .map { $0.sessionID }
    }
    
    static func enumerateApprovedContactThreads(with block: @escaping (TSContactThread, Contact, UnsafeMutablePointer<ObjCBool>) -> ()) {
        Storage.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, stop in
                guard let contactThread: TSContactThread = object as? TSContactThread else { return }
                guard let contact: Contact = approvedContact(in: object, using: transaction) else { return }
                
                block(contactThread, contact, stop)
            }
        }
    }
}
