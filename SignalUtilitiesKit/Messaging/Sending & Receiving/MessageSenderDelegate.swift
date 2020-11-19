
public final class MessageSenderDelegate : SessionMessagingKit.MessageSenderDelegate, SharedSenderKeysDelegate {

    public static let shared = MessageSenderDelegate()
    
    public func handleSuccessfulMessageSend(_ message: Message, using transaction: Any) {
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else { return }
        tsMessage.update(withSentRecipient: message.recipient!, wasSentByUD: true, transaction: transaction as! YapDatabaseReadWriteTransaction)
    }
    
    public func requestSenderKey(for groupPublicKey: String, senderPublicKey: String, using transaction: Any) {
        print("[Loki] Requesting sender key for group public key: \(groupPublicKey), sender public key: \(senderPublicKey).")
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let thread = TSContactThread.getOrCreateThread(withContactId: senderPublicKey, transaction: transaction)
        thread.save(with: transaction)
        let closedGroupUpdateKind = ClosedGroupUpdate.Kind.senderKeyRequest(groupPublicKey: Data(hex: groupPublicKey))
        let closedGroupUpdate = ClosedGroupUpdate()
        closedGroupUpdate.kind = closedGroupUpdateKind
        MessageSender.send(closedGroupUpdate, in: thread, using: transaction)
    }
}
