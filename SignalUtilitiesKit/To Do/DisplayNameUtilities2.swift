
@objc(LKDisplayNameUtilities2)
public final class DisplayNameUtilities2 : NSObject {

    private override init() { }

    @objc(getDisplayNameForPublicKey:threadID:transaction:)
    public static func getDisplayName(for publicKey: String, inThreadWithID threadID: String, using transaction: YapDatabaseReadWriteTransaction) -> String {
        // Case 1: The public key belongs to the user themselves
        if publicKey == getUserHexEncodedPublicKey() { return SSKEnvironment.shared.profileManager.localProfileName() ?? publicKey }
        // Case 2: The given thread is an open group
        if let openGroup = Storage.shared.getOpenGroup(for: threadID) {
            var displayName: String? = nil
            Storage.read { transaction in
                displayName = transaction.object(forKey: publicKey, inCollection: openGroup.id) as! String?
            }
            if let displayName = displayName { return displayName }
        }
        // Case 3: The given thread is a closed group or a one-to-one conversation
        // FIXME: The line below opens a write transaction under certain circumstances. We should move away from this and towards passing
        // a write transaction into this function.
        return SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: publicKey) ?? publicKey
    }
}
