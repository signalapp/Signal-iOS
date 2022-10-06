//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

#if TESTABLE_BUILD

extension MockSSKEnvironment {
    @objc
    func configureGrdb() {
        do {
            try GRDBSchemaMigrator.migrateDatabase(
                databaseStorage: databaseStorage,
                isMainDatabase: true,
                runDataMigrations: true
            )
        } catch {
            owsFail("\(error)")
        }
    }
}

#endif
