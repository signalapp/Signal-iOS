import SessionProtocolKit
import SessionUtilitiesKit

@objc(SNNullMessage)
public final class NullMessage : ControlMessage {

    // MARK: Initialization
    public override init() { super.init() }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> NullMessage? {
        guard proto.nullMessage != nil else { return nil }
        return NullMessage()
    }

    public override func toProto() -> SNProtoContent? {
        let nullMessageProto = SNProtoNullMessage.builder()
        let paddingSize = UInt.random(in: 0..<512) // random(in:) uses the system's default random generator, which is cryptographically secure
        let padding = Data.getSecureRandomData(ofSize: paddingSize)!
        nullMessageProto.setPadding(padding)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setNullMessage(try nullMessageProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct null message proto from: \(self).")
            return nil
        }
    }
}
