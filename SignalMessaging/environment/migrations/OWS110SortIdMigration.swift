//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

class OWS110SortIdMigration: OWSDatabaseMigration {
    // increment a similar constant for each migration.
    @objc
    class func migrationId() -> String {
        return "110"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")

        // TODO batch this?
        self.dbReadWriteConnection().readWrite { transaction in

            var archivedThreads: [TSThread] = []

            // get archived threads before migration
            TSThread.enumerateCollectionObjects({ (object, _) in
                guard let thread = object as? TSThread else {
                    owsFailDebug("unexpected object: \(type(of: object))")
                    return
                }

                if thread.isArchivedByLegacyTimestampForSorting {
                    archivedThreads.append(thread)
                }
            })

            guard let legacySorting: YapDatabaseAutoViewTransaction = transaction.extension(TSMessageDatabaseViewExtensionName_Legacy) as? YapDatabaseAutoViewTransaction else {
                owsFailDebug("legacySorting was unexpectedly nil")
                return
            }

            legacySorting.enumerateGroups { group, _ in
                legacySorting.enumerateKeysAndObjects(inGroup: group) { (_, _, object, _, _) in
                    guard let interaction = object as? TSInteraction else {
                        owsFailDebug("unexpected object: \(type(of: object))")
                        return
                    }

                    interaction.saveNextSortId(transaction: transaction)
                    // Legit usage of legacy sorting for migration to new sorting
                    Logger.debug("thread: \(interaction.uniqueThreadId), timestampForLegacySorting:\(interaction.timestampForLegacySorting()), sortId: \(interaction.sortId)")
                }
            }

            Logger.info("re-archiving \(archivedThreads.count) threads which were previously archived")
            for archivedThread in archivedThreads {
                // latestMessageSortId will have been modified by saving all
                // the interactions above, make sure we get the latest value.
                archivedThread.reload(with: transaction)
                archivedThread.archiveThread(with: transaction)
            }
        }

        completion()
    }

}
