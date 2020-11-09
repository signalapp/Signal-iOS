import SessionProtocolKit

public protocol SessionMessagingKitStorageProtocol : SessionStore, PreKeyStore, SignedPreKeyStore, IdentityKeyStore {

    func with(_ work: (Any) -> Void)
    func withAsync(_ work: (Any) -> Void, completion: () -> Void)

    func getUserPublicKey() -> String?
    func getUserKeyPair() -> ECKeyPair?
    func getUserDisplayName() -> String?
    func getOrGenerateRegistrationID(using transaction: Any) -> UInt32
    func isClosedGroup(_ publicKey: String) -> Bool
    func getClosedGroupPrivateKey(for publicKey: String) -> String?
    func persist(_ job: Job, using transaction: Any)
    func markJobAsSucceeded(_ job: Job, using transaction: Any)
    func markJobAsFailed(_ job: Job, using transaction: Any)
    func getSenderCertificate(for publicKey: String) -> SMKSenderCertificate
    func getAuthToken(for server: String) -> String?
    func setAuthToken(for server: String, to newValue: String, using transaction: Any)
    func removeAuthToken(for server: String, using transaction: Any)
    func getOpenGroupPublicKey(for server: String) -> String?
    func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any)
    func getLastMessageServerID(for group: UInt64, on server: String) -> UInt?
    func setLastMessageServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any)
    func removeLastMessageServerID(for group: UInt64, on server: String, using transaction: Any)
    func getLastDeletionServerID(for group: UInt64, on server: String) -> UInt64?
    func setLastDeletionServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any)
    func removeLastDeletionServerID(for group: UInt64, on server: String, using transaction: Any)
    func setUserCount(to newValue: Int, forOpenGroupWithID: String, using transaction: Any)
    func getIDForMessage(withServerID serverID: UInt) -> UInt?
    func setOpenGroupDisplayName(to displayName: String, for publicKey: String, on channel: UInt64, server: String, using transaction: Any)
    func setLastProfilePictureUploadDate(_ date: Date) // Stored in user defaults so no transaction is needed
}
