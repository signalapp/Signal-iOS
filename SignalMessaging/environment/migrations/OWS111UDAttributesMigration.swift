//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS111UDAttributesMigration: YDBDatabaseMigration {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: -

    // increment a similar constant for each migration.
    @objc
    class func migrationId() -> String {
        // NOTE: Changes were made to the service after this migration was initially
        // merged, so we need to re-migrate any developer devices.  
        return "111.1"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")
        Bench(title: "UD Attributes Migration") {
            self.doMigration()
        }
        completion()
    }

    private func doMigration() {
        tsAccountManager.updateAccountAttributes().retainUntilComplete()

        self.ydbReadWriteConnection.readWrite { transaction in
            self.markAsComplete(with: transaction.asAnyWrite)
        }
    }
}
