//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
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

                self.databaseStorage.write { transaction in
                    do {
                        // We need to dedupe the recipients *before* migrating to
                        // GRDB since GRDB enforces uniqueness constraints on SignalRecipients.
                        try dedupeSignalRecipients(transaction: transaction)
                    } catch {
                        // we don't bother failing hard here.
                        // If for some reason duplicates remain, then the YDBToGRDBMigration will
                        // fail hard anyway. And conversely, if it doesn't fail then there were
                        // no duplicate SignalRecipients.
                        owsFailDebug("error: \(error)")
                    }
                }

                self.storageCoordinator.migrationYDBToGRDBWillBegin()
                assert(self.storageCoordinator.state == .duringYDBToGRDBMigration)

                Bench(title: "\(self.logTag)") {
                    do {
                        try YDBToGRDBMigration().run()
                    } catch {
                        owsFail("error: \(error)")
                    }
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
