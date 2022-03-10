// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

@objc(SNUnreadMentionMigration)
public class UnreadMentionMigration : OWSDatabaseMigration {
    
    @objc
    class func migrationId() -> String {
        return "003" // leave "002" for message request migration
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }
    
    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        var threads: [TSThread] = []
        Storage.read { transaction in
            TSThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSThread, let threadID = thread.uniqueId else { return }
                let unreadMessages = transaction.ext(TSUnreadDatabaseViewExtensionName) as! YapDatabaseViewTransaction
                unreadMessages.enumerateKeysAndObjects(inGroup: threadID) { collection, key, object, index, stop in
                    guard let unreadMessage = object as? TSIncomingMessage else { return }
                    if unreadMessage.wasRead { return }
                    if unreadMessage.isUserMentioned {
                        thread.hasUnreadMentionMessage = true
                        stop.pointee = true
                    }
                }
                threads.append(thread)
            }
        }
        Storage.write(with: { transaction in
            threads.forEach { thread in
                thread.save(with: transaction)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion()
        })
    }
}
