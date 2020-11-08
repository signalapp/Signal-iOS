import SessionProtocolKit

public struct Configuration {
    public let storage: SessionMessagingKitStorageProtocol
    public let sessionRestorationImplementation: SessionRestorationProtocol
    public let certificateValidator: SMKCertificateValidator
    public let pnServerURL: String
    public let pnServerPublicKey: String

    internal static var shared: Configuration!
}

public enum SessionMessagingKit { // Just to make the external API nice

    public static func configure(with configuration: Configuration) {
        Configuration.shared = configuration
    }
}
