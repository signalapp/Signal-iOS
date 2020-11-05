import SessionProtocolKit

@objc(SNControlMessage)
public class ControlMessage : Message {

    public enum Kind {
        case readReceipt
        case sessionRequest(preKeyBundle: PreKeyBundle)
        case typingIndicator
        case closedGroupUpdate
        case expirationUpdate
    }
}
