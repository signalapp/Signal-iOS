import SessionProtocolKit

public protocol SessionMessagingKitStorageProtocol {

    func with(_ work: (Any) -> Void)

    func getUserPublicKey() -> String?
    func getOrGenerateRegistrationID(using transaction: Any) -> UInt32
    func isClosedGroup(_ publicKey: String) -> Bool
    func getClosedGroupPrivateKey(for publicKey: String) -> String?
    func persist(_ job: Job, using transaction: Any)
}
