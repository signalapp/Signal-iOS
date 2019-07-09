//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS112TypingIndicatorsMigration: YDBDatabaseMigration {

    // MARK: - Dependencies

    private var typingIndicators: TypingIndicators {
        return SSKEnvironment.shared.typingIndicators
    }

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        return "112"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")
        BenchAsync(title: "Typing Indicators Migration") { (benchCompletion) in
            self.doMigrationAsync(completion: {
                benchCompletion()
                completion()
            })
        }
    }

    private func doMigrationAsync(completion : @escaping OWSDatabaseMigrationCompletion) {
        DispatchQueue.main.async {
            // Typing indicators should be disabled by default for
            // legacy users.
            self.typingIndicators.setTypingIndicatorsEnabled(value: false)

            DispatchQueue.global().async {
                self.markAsCompleteWithSneakyTransaction()

                completion()
            }
        }
    }
}
