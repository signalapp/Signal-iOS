
public protocol MessageSenderDelegate {

    func handleSuccessfulMessageSend(_ message: Message, using transaction: Any)
    func handleFailedMessageSend(_ message: Message, using transaction: Any)
}
