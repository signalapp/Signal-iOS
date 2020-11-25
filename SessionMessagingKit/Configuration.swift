import SessionProtocolKit

public struct Configuration {
    public let storage: SessionMessagingKitStorageProtocol
    public let signalStorage: SessionStore & PreKeyStore & SignedPreKeyStore
    public let identityKeyStore: IdentityKeyStore
    public let sessionRestorationImplementation: SessionRestorationProtocol
    public let certificateValidator: SMKCertificateValidator

    internal static var shared: Configuration!
}

public enum SNMessagingKit { // Just to make the external API nice

    public static func configure(
        storage: SessionMessagingKitStorageProtocol,
        signalStorage: SessionStore & PreKeyStore & SignedPreKeyStore,
        identityKeyStore: IdentityKeyStore,
        sessionRestorationImplementation: SessionRestorationProtocol,
        certificateValidator: SMKCertificateValidator
    ) {
        Configuration.shared = Configuration(
            storage: storage,
            signalStorage: signalStorage,
            identityKeyStore: identityKeyStore,
            sessionRestorationImplementation: sessionRestorationImplementation,
            certificateValidator: certificateValidator
        )
    }
}
