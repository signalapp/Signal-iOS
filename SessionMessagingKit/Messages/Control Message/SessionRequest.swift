import SessionProtocolKit
import SessionUtilitiesKit

@objc(SNSessionRequest)
public final class SessionRequest : ControlMessage {
    public var preKeyBundle: PreKeyBundle?

    // MARK: Initialization
    public override init() { super.init() }

    internal init(preKeyBundle: PreKeyBundle) {
        super.init()
        self.preKeyBundle = preKeyBundle
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return preKeyBundle != nil
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let preKeyBundle = coder.decodeObject(forKey: "preKeyBundle") as! PreKeyBundle? { self.preKeyBundle = preKeyBundle }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(preKeyBundle, forKey: "preKeyBundle")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> SessionRequest? {
        guard proto.nullMessage != nil, let preKeyBundleProto = proto.prekeyBundleMessage else { return nil }
        var registrationID: UInt32 = 0
        Configuration.shared.storage.with { transaction in
            registrationID = Configuration.shared.storage.getOrGenerateRegistrationID(using: transaction)
        }
        guard let preKeyBundle = PreKeyBundle(registrationId: Int32(registrationID),
                                        deviceId: 1,
                                        preKeyId: Int32(preKeyBundleProto.prekeyID),
                                        preKeyPublic: preKeyBundleProto.prekey,
                                        signedPreKeyPublic: preKeyBundleProto.signedKey,
                                        signedPreKeyId: Int32(preKeyBundleProto.signedKeyID),
                                        signedPreKeySignature: preKeyBundleProto.signature,
                                        identityKey: preKeyBundleProto.identityKey) else { return nil }
        return SessionRequest(preKeyBundle: preKeyBundle)
    }

    public override func toProto() -> SNProtoContent? {
        guard let preKeyBundle = preKeyBundle else {
            SNLog("Couldn't construct session request proto from: \(self).")
            return nil
        }
        let nullMessageProto = SNProtoNullMessage.builder()
        let paddingSize = UInt.random(in: 0..<512) // random(in:) uses the system's default random generator, which is cryptographically secure
        let padding = Data.getSecureRandomData(ofSize: paddingSize)!
        nullMessageProto.setPadding(padding)
        let preKeyBundleProto = SNProtoPrekeyBundleMessage.builder()
        preKeyBundleProto.setIdentityKey(preKeyBundle.identityKey)
        preKeyBundleProto.setDeviceID(UInt32(preKeyBundle.deviceId))
        preKeyBundleProto.setPrekeyID(UInt32(preKeyBundle.preKeyId))
        preKeyBundleProto.setPrekey(preKeyBundle.preKeyPublic)
        preKeyBundleProto.setSignedKeyID(UInt32(preKeyBundle.signedPreKeyId))
        preKeyBundleProto.setSignedKey(preKeyBundle.signedPreKeyPublic)
        preKeyBundleProto.setSignature(preKeyBundle.signedPreKeySignature)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setNullMessage(try nullMessageProto.build())
            contentProto.setPrekeyBundleMessage(try preKeyBundleProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct session request proto from: \(self).")
            return nil
        }
    }
}
