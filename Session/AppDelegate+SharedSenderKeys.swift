
extension AppDelegate : SharedSenderKeysDelegate {

    public func requestSenderKey(for groupPublicKey: String, senderPublicKey: String, using transaction: Any) {
        ClosedGroupsProtocol.requestSenderKey(for: groupPublicKey, senderPublicKey: senderPublicKey, using: transaction as! YapDatabaseReadWriteTransaction)
    }
}
