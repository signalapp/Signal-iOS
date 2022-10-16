// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

public enum SNSnodeKit { // Just to make the external API nice
    public static func migrations() -> TargetMigrations {
        return TargetMigrations(
            identifier: .snodeKit,
            migrations: [
                [
                    _001_InitialSetupMigration.self,
                    _002_SetupStandardJobs.self
                ],
                [
                    _003_YDBToGRDBMigration.self
                ],
                [
                    _004_FlagMessageHashAsDeletedOrInvalid.self
                ]
            ]
        )
    }

    public static func configure() {
        // Configure the job executors
        JobRunner.add(executor: GetSnodePoolJob.self, for: .getSnodePool)
    }
}
