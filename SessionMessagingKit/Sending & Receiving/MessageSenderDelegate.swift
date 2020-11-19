
public protocol MessageSenderDelegate {

    func handleSuccessfulMessageSend(_ message: Message, using transaction: Any)
}
