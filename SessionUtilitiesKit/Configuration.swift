// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

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
                ],
                [], // Other DB migrations
                [], // Legacy DB removal
                []
            ]
        )
    }

    public static func configure(maxFileSize: UInt) {
        SNUtilitiesKitConfiguration.maxFileSize = maxFileSize
    }
}

@objc public final class SNUtilitiesKitConfiguration: NSObject {
    @objc public static var maxFileSize: UInt = 0
}
