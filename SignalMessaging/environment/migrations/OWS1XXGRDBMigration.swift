//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalServiceKit

@objc
public class OWS1XXGRDBMigration: YDBDatabaseMigration {

    // MARK: - Dependencies

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        return "1XX"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")

        DispatchQueue.global().async {
            if self.storageCoordinator.state != .beforeYDBToGRDBMigration {
                owsFail("unexpected storage coordinator state.")
            } else {
                self.storageCoordinator.migrationYDBToGRDBWillBegin()
                assert(self.storageCoordinator.state == .duringYDBToGRDBMigration)

                Bench(title: "\(self.logTag)") {
                    try! YDBToGRDBMigration().run()
                }

                self.storageCoordinator.migrationYDBToGRDBDidComplete()
                assert(self.storageCoordinator.state == .GRDB)
            }
            completion()
        }
    }

    public override var shouldBeSaved: Bool {
        if FeatureFlags.storageMode == .grdbThrowaway {
            // Do nothing so as to re-run every launch.
            // Useful while actively developing the migration.
            return false
        } else {
            return true
        }
    }
}
