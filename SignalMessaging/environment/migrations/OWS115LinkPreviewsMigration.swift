//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS115LinkPreviewsMigration: OWSDatabaseMigration {

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    class func migrationId() -> String {
        return "115"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")
        BenchAsync(title: "Link Previews Migration") { (benchCompletion) in
            self.doMigrationAsync(completion: {
                benchCompletion()
                completion()
            })
        }
    }

    private func doMigrationAsync(completion : @escaping OWSDatabaseMigrationCompletion) {
        DispatchQueue.main.async {
            // Link Previews should be disabled by default for legacy users.
            SSKPreferences.setAreLinkPreviewsEnabled(value: false)

            DispatchQueue.global().async {
                self.dbReadWriteConnection().readWrite { transaction in
                    self.save(with: transaction)
                }

                completion()
            }
        }
    }
}
