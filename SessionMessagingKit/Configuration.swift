
public struct Configuration {
    public let storage: SessionMessagingKitStorageProtocol

    internal static var shared: Configuration!
}

public enum SessionMessagingKit { // Just to make the external API nice

    public static func configure(with configuration: Configuration) {
        Configuration.shared = configuration
    }
}
