
public struct Configuration {
    public let storage: SessionProtocolKitStorageProtocol
    public let sharedSenderKeysDelegate: SharedSenderKeysDelegate

    internal static var shared: Configuration!
}

public enum SessionProtocolKit { // Just to make the external API nice

    public static func configure(with configuration: Configuration) {
        Configuration.shared = configuration
    }
}
