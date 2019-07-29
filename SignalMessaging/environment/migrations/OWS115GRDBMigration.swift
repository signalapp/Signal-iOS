//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalServiceKit

@objc
public class OWS115GRDBMigration: YDBDatabaseMigration {

    // Increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        return "115"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")

        DispatchQueue.global().async {
            if FeatureFlags.useGRDB {
                Bench(title: "\(self.logTag)") {
                    try! YDBToGRDBMigration().run()
                }
            }
            completion()
        }
    }

    public override var shouldBeSaved: Bool {
        if FeatureFlags.grdbMigratesFreshDBEveryLaunch {
            // Do nothing so as to re-run every launch.
            // Useful while actively developing the migration.
            return false
        } else {
            return true
        }
    }
}
