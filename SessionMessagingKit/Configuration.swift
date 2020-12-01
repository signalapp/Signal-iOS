import SessionProtocolKit

@objc(SNMessagingKitConfiguration)
public final class Configuration : NSObject {
    public let storage: SessionMessagingKitStorageProtocol
    @objc public let signalStorage: SessionStore & PreKeyStore & SignedPreKeyStore
    public let identityKeyStore: IdentityKeyStore
    public let sessionRestorationImplementation: SessionRestorationProtocol
    public let certificateValidator: SMKCertificateValidator

    @objc public static var shared: Configuration!

    fileprivate init(
        storage: SessionMessagingKitStorageProtocol,
        signalStorage: SessionStore & PreKeyStore & SignedPreKeyStore,
        identityKeyStore: IdentityKeyStore,
        sessionRestorationImplementation: SessionRestorationProtocol,
        certificateValidator: SMKCertificateValidator
    ) {
        self.storage = storage
        self.signalStorage = signalStorage
        self.identityKeyStore = identityKeyStore
        self.sessionRestorationImplementation = sessionRestorationImplementation
        self.certificateValidator = certificateValidator
    }
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
