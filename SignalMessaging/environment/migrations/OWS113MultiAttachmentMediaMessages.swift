//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWS113MultiAttachmentMediaMessages: YDBDatabaseMigration {

    // MARK: - Dependencies

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        // NOTE: that we use .1 since there was a bug in the logic to
        //       set albumMessageId.
        return "113.1"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")
        BenchAsync(title: "\(self.logTag)") { (benchCompletion) in
            self.doMigrationAsync(completion: {
                benchCompletion()
                completion()
            })
        }
    }

    private func doMigrationAsync(completion : @escaping OWSDatabaseMigrationCompletion) {
        DispatchQueue.global().async {
            var legacyAttachments: [(attachmentId: String, messageId: String)] = []

            self.ydbReadWriteConnection.read { transaction in
                TSMessage.ydb_enumerateCollectionObjects(with: transaction) { object, _ in
                    autoreleasepool {
                        guard let message: TSMessage = object as? TSMessage else {
                            Logger.debug("ignoring message with type: \(object)")
                            return
                        }

                        let messageId = message.uniqueId
                        for attachmentId in message.attachmentIds {
                            legacyAttachments.append((attachmentId: attachmentId as! String, messageId: messageId))
                        }
                    }
                }
            }
            self.ydbReadWriteConnection.readWrite { transaction in
                for (attachmentId, messageId) in legacyAttachments {
                    autoreleasepool {
                        // NOTE: Use legacy fetch.
                        guard let attachment = TSAttachment.ydb_fetch(uniqueId: attachmentId, transaction: transaction) else {
                            Logger.warn("missing attachment for messageId: \(messageId)")
                            return
                        }

                        attachment.migrateAlbumMessageId(messageId)
                        // NOTE: Use legacy save.
                        attachment.ydb_save(with: transaction)
                    }
                }
                self.markAsComplete(with: transaction.asAnyWrite)
            }

            completion()
        }
    }
}
