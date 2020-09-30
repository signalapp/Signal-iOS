
enum ContactUtilities {

    static func getAllContacts() -> [String] {
        var result: [String] = []
        Storage.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSContactThread, thread.shouldThreadBeVisible else { return }
                result.append(thread.contactIdentifier())
            }
        }
        func getDisplayName(for publicKey: String) -> String {
            return UserDisplayNameUtilities.getPrivateChatDisplayName(for: publicKey) ?? publicKey
        }
        return result.sorted { getDisplayName(for: $0) < getDisplayName(for: $1) }
    }
}
