import SessionProtocolKit

@objc(SNControlMessage)
public class ControlMessage : Message {

    public enum Kind {
        case sessionRequest(preKeyBundle: PreKeyBundle)
    }
}
