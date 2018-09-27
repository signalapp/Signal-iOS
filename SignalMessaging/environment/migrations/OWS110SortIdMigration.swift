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
        BenchAsync(title: "Sort Migration") { completeBenchmark in
            self.doMigration {
                completeBenchmark()
                completion()
            }
        }
    }

    private func doMigration(completion: @escaping OWSDatabaseMigrationCompletion) {
        // TODO batch this?
        self.dbReadWriteConnection().readWrite { transaction in

            var archivedThreads: [TSThread] = []

            // get archived threads before migration
            TSThread.enumerateCollectionObjects(with: transaction) { (object, _) in
                guard let thread = object as? TSThread else {
                    owsFailDebug("unexpected object: \(type(of: object))")
                    return
                }

                if thread.isArchivedByLegacyTimestampForSorting {
                    archivedThreads.append(thread)
                }
            }

            guard let legacySorting: YapDatabaseAutoViewTransaction = transaction.extension(TSMessageDatabaseViewExtensionName_Legacy) as? YapDatabaseAutoViewTransaction else {
                owsFailDebug("legacySorting was unexpectedly nil")
                return
            }

            let totalCount: UInt = legacySorting.numberOfItemsInAllGroups()
            var completedCount: UInt = 0
            legacySorting.enumerateGroups { group, _ in
                autoreleasepool {
                    legacySorting.enumerateKeysAndObjects(inGroup: group) { (_, _, object, _, _) in
                        autoreleasepool {
                            guard let interaction = object as? TSInteraction else {
                                owsFailDebug("unexpected object: \(type(of: object))")
                                return
                            }

                            interaction.saveNextSortId(transaction: transaction)

                            completedCount += 1

                            if completedCount % 100 == 0 {
                                // Legit usage of legacy sorting for migration to new sorting
                                Logger.info("thread: \(interaction.uniqueThreadId), timestampForLegacySorting:\(interaction.timestampForLegacySorting()), sortId: \(interaction.sortId) totalCount: \(totalCount), completedcount: \(completedCount)")
                            }
                        }
                    }
                }
            }

            Logger.info("re-archiving \(archivedThreads.count) threads which were previously archived")
            for archivedThread in archivedThreads {
                archivedThread.archiveThread(with: transaction)
            }

            self.save(with: transaction)
        }

        completion()
    }

}
