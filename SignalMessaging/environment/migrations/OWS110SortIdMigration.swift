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
                    Logger.debug("thread: \(interaction.uniqueThreadId), timestampForSorting:\(interaction.timestampForSorting()), sortId: \(interaction.sortId)")
                }
            }
        }

        completion()
    }

}
