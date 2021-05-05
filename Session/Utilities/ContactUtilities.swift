
enum ContactUtilities {

    static func getAllContacts() -> [String] {
        // Collect all contacts
        var result: [String] = []
        Storage.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSContactThread, thread.shouldBeVisible else { return }
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
