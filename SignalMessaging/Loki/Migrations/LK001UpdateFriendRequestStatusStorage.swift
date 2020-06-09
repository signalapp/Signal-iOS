import Foundation
import SessionServiceKit

@objc
public class LK001UpdateFriendRequestStatusStorage : OWSDatabaseMigration {

    // MARK: -

    // Increment a similar constant for each migration.
    // 100-114 are reserved for Signal migrations
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
                var threads: [TSContactThread] = []
                TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                    guard let thread = object as? TSContactThread else { return }
                    threads.append(thread)
                }
                threads.forEach { thread in
                    guard let friendRequestStatus = LKFriendRequestStatus(rawValue: thread.friendRequestStatus) else { return }
                    OWSPrimaryStorage.shared().setFriendRequestStatus(friendRequestStatus, for: thread.contactIdentifier(), transaction: transaction)
                }
                self.save(with: transaction)
            }
            completion()
        }
    }
}
