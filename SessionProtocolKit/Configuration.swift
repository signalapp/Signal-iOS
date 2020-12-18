
public struct SNProtocolKitConfiguration {
    public let storage: SessionProtocolKitStorageProtocol
    public let sharedSenderKeysDelegate: SharedSenderKeysDelegate

    internal static var shared: SNProtocolKitConfiguration!
}

public enum SNProtocolKit { // Just to make the external API nice

    public static func configure(storage: SessionProtocolKitStorageProtocol, sharedSenderKeysDelegate: SharedSenderKeysDelegate) {
        SNProtocolKitConfiguration.shared = SNProtocolKitConfiguration(storage: storage, sharedSenderKeysDelegate: sharedSenderKeysDelegate)
    }
}
