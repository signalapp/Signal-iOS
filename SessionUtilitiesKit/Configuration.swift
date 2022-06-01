// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@objc
public final class SNUtilitiesKitConfiguration : NSObject {
    public let maxFileSize: UInt

    @objc public static var shared: SNUtilitiesKitConfiguration!

    fileprivate init(maxFileSize: UInt) {
        self.maxFileSize = maxFileSize
    }
}

public enum SNUtilitiesKit { // Just to make the external API nice
    public static func migrations() -> TargetMigrations {
        return TargetMigrations(
            identifier: .utilitiesKit,
            migrations: [
                [
                    // Intentionally including the '_003_YDBToGRDBMigration' in the first migration
                    // set to ensure the 'Identity' data is migrated before any other migrations are
                    // run (some need access to the users publicKey)
                    _001_InitialSetupMigration.self,
                    _002_SetupStandardJobs.self,
                    _003_YDBToGRDBMigration.self
                ]
            ]
        )
    }

    public static func configure(maxFileSize: UInt) {
        SNUtilitiesKitConfiguration.shared = SNUtilitiesKitConfiguration(maxFileSize: maxFileSize)
    }
}
