//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS112TypingIndicatorsMigration: OWSDatabaseMigration {

    // MARK: - Dependencies

    private var typingIndicators: TypingIndicators {
        return SSKEnvironment.shared.typingIndicators
    }

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    class func migrationId() -> String {
        return "112"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")
        Bench(title: "Typing Indicators Migration") {
            self.doMigration()
        }
        completion()
    }

    private func doMigration() {
        // Typing indicators should be disabled by default for
        // legacy users.
        typingIndicators.setTypingIndicatorsEnabled(value: false)

        self.dbReadWriteConnection().readWrite { transaction in
            self.save(with: transaction)
        }
    }
}
