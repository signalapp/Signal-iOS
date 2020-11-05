
@objc(SNControlMessage)
public class ControlMessage : Message {

    public enum Kind {
        case sessionRequest(preKeyBundle: PreKeyBundle)
    }

    public override class func fromProto(_ proto: SNProtoContent) -> ControlMessage? {
        if let preKeyBundle = proto.prekeyBundleMessage {

        }
    }
}
