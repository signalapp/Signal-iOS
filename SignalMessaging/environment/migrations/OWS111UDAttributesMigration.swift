//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS111UDAttributesMigration: OWSDatabaseMigration {

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
        BenchAsync(title: "UD Attributes Migration") { completeBenchmark in
            self.doMigration {
                completeBenchmark()
                completion()
            }
        }
    }

    private func doMigration(completion: @escaping OWSDatabaseMigrationCompletion) {
        tsAccountManager.updateAccountAttributes()

        self.dbReadWriteConnection().readWrite { transaction in
            self.save(with: transaction)
        }
    }
}
