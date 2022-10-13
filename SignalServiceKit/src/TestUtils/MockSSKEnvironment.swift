//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
