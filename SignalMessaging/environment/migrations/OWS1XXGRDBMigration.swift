//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalServiceKit

extension StorageCoordinatorState: CustomStringConvertible {
    public var description: String {
        return NSStringFromStorageCoordinatorState(self)
    }
}

@objc
public class OWS1XXGRDBMigration: YDBDatabaseMigration {

    // Increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        return "1XX"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")

        DispatchQueue.global().async {
            if self.storageCoordinator.state != .beforeYDBToGRDBMigration {
                owsFail("unexpected storage coordinator state: \(self.storageCoordinator.state)")
            } else {
                self.storageCoordinator.migrationYDBToGRDBWillBegin()
                assert(self.storageCoordinator.state == .duringYDBToGRDBMigration)

                Bench(title: "\(self.logTag)") {
                    try! YDBToGRDBMigration().run()
                }

                self.storageCoordinator.migrationYDBToGRDBDidComplete()
                assert(self.storageCoordinator.state == .GRDB)
            }

            self.databaseStorage.write { transaction in
                switch transaction.writeTransaction {
                case .grdbWrite:
                    self.markAsComplete(with: transaction)
                case .yapWrite:
                    owsFail("wrong transaction type")
                }
            }

            completion()
        }
    }

    public override var shouldBeSaved: Bool {
        if SDSDatabaseStorage.shouldUseDisposableGrdb {
            // Do nothing so as to re-run every launch.
            // Useful while actively developing the migration.
            return false
        } else {
            return true
        }
    }
}
