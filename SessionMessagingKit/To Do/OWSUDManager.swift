
@objc
public enum UnidentifiedAccessMode: Int {
    case unknown
    case enabled
    case disabled
    case unrestricted
}

@objc
public class OWSUDAccess: NSObject {
    @objc
    public let udAccessKey: SMKUDAccessKey

    @objc
    public let udAccessMode: UnidentifiedAccessMode

    @objc
    public let isRandomKey: Bool

    @objc
    public required init(udAccessKey: SMKUDAccessKey,
                         udAccessMode: UnidentifiedAccessMode,
                         isRandomKey: Bool) {
        self.udAccessKey = udAccessKey
        self.udAccessMode = udAccessMode
        self.isRandomKey = isRandomKey
    }
}

@objc public protocol OWSUDManager: class {

    @objc func setup()

    @objc func trustRoot() -> ECPublicKey

    @objc func isUDVerboseLoggingEnabled() -> Bool

    // MARK: - Recipient State

    @objc
    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, recipientId: String)

    @objc
    func unidentifiedAccessMode(forRecipientId recipientId: String) -> UnidentifiedAccessMode

    @objc
    func udAccessKey(forRecipientId recipientId: String) -> SMKUDAccessKey?

    @objc
    func udAccess(forRecipientId recipientId: String,
                  requireSyncAccess: Bool) -> OWSUDAccess?

    // MARK: Sender Certificate

    // We use completion handlers instead of a promise so that message sending
    // logic can access the strongly typed certificate data.
    @objc
    func ensureSenderCertificate(success:@escaping (SMKSenderCertificate) -> Void,
                                 failure:@escaping (Error) -> Void)

    // MARK: Unrestricted Access

    @objc
    func shouldAllowUnrestrictedAccessLocal() -> Bool
    @objc
    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool)

    @objc
    func getSenderCertificate() -> SMKSenderCertificate?
}
