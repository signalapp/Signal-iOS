
enum ContactUtilities {

    static func getAllContacts() -> [String] {
        // Collect all contacts
        var result: [String] = []
        Storage.read { transaction in
            // FIXME: If a user deletes a contact thread they will no longer appear in this list (ie. won't be an option for closed group conversations)
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard
                    let thread: TSContactThread = object as? TSContactThread,
                    thread.shouldBeVisible,
                    Storage.shared.getContact(
                        with: thread.contactSessionID(),
                        using: transaction
                    )?.didApproveMe == true
                else {
                    return
                }
                
                result.append(thread.contactSessionID())
            }
        }
        func getDisplayName(for publicKey: String) -> String {
            return Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
        }
        
        // Remove the current user
        if let index = result.firstIndex(of: getUserHexEncodedPublicKey()) {
            result.remove(at: index)
        }
        
        // Sort alphabetically
        return result.sorted { getDisplayName(for: $0) < getDisplayName(for: $1) }
    }
}
