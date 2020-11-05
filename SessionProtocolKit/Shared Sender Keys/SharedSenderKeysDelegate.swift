
public protocol SharedSenderKeysDelegate {

    func requestSenderKey(for groupPublicKey: String, senderPublicKey: String, using transaction: Any)
}
