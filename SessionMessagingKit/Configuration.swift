import Foundation
import SessionUtilitiesKit

@objc
public final class SNMessagingKitConfiguration : NSObject {
    public let storage: SessionMessagingKitStorageProtocol

    @objc public static var shared: SNMessagingKitConfiguration!

    fileprivate init(storage: SessionMessagingKitStorageProtocol) {
        self.storage = storage
    }
}

public enum SNMessagingKit { // Just to make the external API nice
    public static func migrations() -> TargetMigrations {
        return TargetMigrations(
            identifier: .messagingKit,
            migrations: [
                [
                    _001_InitialSetupMigration.self
                ],
                [
                    _002_YDBToGRDBMigration.self
                ]
            ]
        )
    }
    
    public static func configure(storage: SessionMessagingKitStorageProtocol) {
        SNMessagingKitConfiguration.shared = SNMessagingKitConfiguration(storage: storage)
    }
}
