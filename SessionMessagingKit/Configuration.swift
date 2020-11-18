import SessionProtocolKit

public struct Configuration {
    public let storage: SessionMessagingKitStorageProtocol
    public let messageReceiverDelegate: MessageReceiverDelegate
    public let signalStorage: SessionStore & PreKeyStore & SignedPreKeyStore
    public let identityKeyStore: IdentityKeyStore
    public let sessionRestorationImplementation: SessionRestorationProtocol
    public let certificateValidator: SMKCertificateValidator
    public let openGroupAPIDelegate: OpenGroupAPIDelegate
    public let pnServerURL: String
    public let pnServerPublicKey: String

    internal static var shared: Configuration!
}

public enum SNMessagingKit { // Just to make the external API nice

    public static func configure(
        storage: SessionMessagingKitStorageProtocol,
        messageReceiverDelegate: MessageReceiverDelegate,
        signalStorage: SessionStore & PreKeyStore & SignedPreKeyStore,
        identityKeyStore: IdentityKeyStore,
        sessionRestorationImplementation: SessionRestorationProtocol,
        certificateValidator: SMKCertificateValidator,
        openGroupAPIDelegate: OpenGroupAPIDelegate,
        pnServerURL: String,
        pnServerPublicKey: String
    ) {
        Configuration.shared = Configuration(
            storage: storage,
            messageReceiverDelegate: messageReceiverDelegate,
            signalStorage: signalStorage,
            identityKeyStore: identityKeyStore,
            sessionRestorationImplementation: sessionRestorationImplementation,
            certificateValidator: certificateValidator,
            openGroupAPIDelegate: openGroupAPIDelegate,
            pnServerURL: pnServerURL,
            pnServerPublicKey: pnServerPublicKey
        )
    }
}
