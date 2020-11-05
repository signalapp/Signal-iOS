
public enum ClosedGroupRatchetCollectionType {
    case old, current
}

public protocol SessionProtocolKitStorageProtocol {

    func with(_ work: (Any) -> Void)

    func getClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, from collection: ClosedGroupRatchetCollectionType) -> ClosedGroupRatchet?
    func setClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, ratchet: ClosedGroupRatchet, in collection: ClosedGroupRatchetCollectionType, using transaction: Any)
    func getAllClosedGroupRatchets(for groupPublicKey: String, from collection: ClosedGroupRatchetCollectionType) -> [(senderPublicKey: String, ratchet: ClosedGroupRatchet)]
    func getAllClosedGroupSenderKeys(for groupPublicKey: String, from collection: ClosedGroupRatchetCollectionType) -> Set<ClosedGroupSenderKey>
    func removeAllClosedGroupRatchets(for groupPublicKey: String, from collection: ClosedGroupRatchetCollectionType, using transaction: Any)
    func getUserClosedGroupPublicKeys() -> Set<String>
    func getClosedGroupPrivateKey(for publicKey: String) -> String?
}
