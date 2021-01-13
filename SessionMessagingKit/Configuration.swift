import SessionProtocolKit

@objc
public final class SNMessagingKitConfiguration : NSObject {
    public let storage: SessionMessagingKitStorageProtocol
    public let openGroupManager: OpenGroupManagerProtocol

    @objc public static var shared: SNMessagingKitConfiguration!

    fileprivate init(storage: SessionMessagingKitStorageProtocol, openGroupManager: OpenGroupManagerProtocol) {
        self.storage = storage
        self.openGroupManager = openGroupManager
    }
}

public enum SNMessagingKit { // Just to make the external API nice

    public static func configure(storage: SessionMessagingKitStorageProtocol, openGroupManager: OpenGroupManagerProtocol) {
        SNMessagingKitConfiguration.shared = SNMessagingKitConfiguration(storage: storage, openGroupManager: openGroupManager)
    }
}
