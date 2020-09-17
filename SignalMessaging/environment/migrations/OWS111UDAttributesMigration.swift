//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import PromiseKit

@objc
public class OWS111UDAttributesMigration: YDBDatabaseMigration {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: -

    // increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
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
        firstly {
            tsAccountManager.updateAccountAttributes()
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }

        self.ydbReadWriteConnection.readWrite { transaction in
            self.markAsComplete(with: transaction.asAnyWrite)
        }
    }
}
