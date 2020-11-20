
public protocol MessageReceiverDelegate {

    func isBlocked(_ publicKey: String) -> Bool
    func updateProfile(for publicKey: String, from profile: VisibleMessage.Profile, using transaction: Any)
    func showTypingIndicatorIfNeeded(for senderPublicKey: String)
    func hideTypingIndicatorIfNeeded(for senderPublicKey: String)
    func cancelTypingIndicatorsIfNeeded(for senderPublicKey: String)
    func notifyUserIfNeeded(for message: Any, threadID: String)
    func markMessagesAsRead(_ timestamps: [UInt64], from senderPublicKey: String, at timestamp: UInt64)
    func setExpirationTimer(to duration: UInt32, for senderPublicKey: String, groupPublicKey: String?, using transaction: Any)
    func disableExpirationTimer(for senderPublicKey: String, groupPublicKey: String?, using transaction: Any)
    func handleNewGroup(_ message: ClosedGroupUpdate, using transaction: Any)
    func handleGroupUpdate(_ message: ClosedGroupUpdate, using transaction: Any)
    func handleSenderKeyRequest(_ message: ClosedGroupUpdate, using transaction: Any)
    func handleSenderKey(_ message: ClosedGroupUpdate, using transaction: Any)
}
