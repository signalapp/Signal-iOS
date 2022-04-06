
@objc
public final class SNUtilitiesKitConfiguration : NSObject {
    @objc public let owsPrimaryStorage: OWSPrimaryStorageProtocol
    public let maxFileSize: UInt

    @objc public static var shared: SNUtilitiesKitConfiguration!

    fileprivate init(owsPrimaryStorage: OWSPrimaryStorageProtocol, maxFileSize: UInt) {
        self.owsPrimaryStorage = owsPrimaryStorage
        self.maxFileSize = maxFileSize
    }
}

public enum SNUtilitiesKit { // Just to make the external API nice
    public static func migrations() -> TargetMigrations {
        return TargetMigrations(
            identifier: .utilitiesKit,
            migrations: [
                [
                    // Intentionally including the '_002_YDBToGRDBMigration' in the first migration
                    // set to ensure the 'Identity' data is migrated before any other migrations are
                    // run (some need access to the users publicKey)
                    _001_InitialSetupMigration.self,
                    _002_YDBToGRDBMigration.self
                ]
            ]
        )
    }

    public static func configure(owsPrimaryStorage: OWSPrimaryStorageProtocol, maxFileSize: UInt) {
        SNUtilitiesKitConfiguration.shared = SNUtilitiesKitConfiguration(owsPrimaryStorage: owsPrimaryStorage, maxFileSize: maxFileSize)
    }
}
