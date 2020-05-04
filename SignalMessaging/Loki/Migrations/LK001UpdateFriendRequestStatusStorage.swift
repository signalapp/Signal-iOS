//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
// 

import Foundation
import SignalServiceKit

@objc
public class LK001UpdateFriendRequestStatusStorage: OWSDatabaseMigration {

    // MARK: -

    // Increment a similar constant for each migration.
    // 100-114 are reserved for signal migrations
    @objc
    class func migrationId() -> String {
        return "001"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        DispatchQueue.global().async {
            self.dbReadWriteConnection().readWrite { transaction in
                guard let threads = TSThread.allObjectsInCollection() as? [TSThread] else {
                    owsFailDebug("Failed to convert objects to TSThread")
                    return
                }
                for thread in threads {
                    guard let thread = thread as? TSContactThread,
                        let friendRequestStatus = LKFriendRequestStatus(rawValue: thread.friendRequestStatus) else {
                            continue;
                    }
                    OWSPrimaryStorage.shared().setFriendRequestStatus(friendRequestStatus, for: thread.contactIdentifier(), transaction: transaction)
                }
            }

            completion()
        }
    }

}
