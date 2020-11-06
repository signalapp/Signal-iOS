
public enum ClosedGroupRatchetCollectionType {
    case old, current
}

public protocol SessionProtocolKitStorageProtocol {

    func with(_ work: (Any) -> Void)

    func getClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, from collection: ClosedGroupRatchetCollectionType) -> ClosedGroupRatchet?
    func setClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, ratchet: ClosedGroupRatchet, in collection: ClosedGroupRatchetCollectionType, using transaction: Any)
}
