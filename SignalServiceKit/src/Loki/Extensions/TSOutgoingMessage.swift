
@objc public extension TSOutgoingMessage {
    
    /// Loki: This is a message used to establish sessions
    @objc public static func createEmptyOutgoingMessage(inThread thread: TSThread) -> TSOutgoingMessage {
        return TSOutgoingMessage(in: thread, messageBody: "", attachmentId: nil)
    }
}
