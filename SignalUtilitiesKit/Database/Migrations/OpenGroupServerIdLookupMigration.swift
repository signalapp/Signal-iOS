// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import YapDatabase
import SessionMessagingKit

@objc(SNOpenGroupServerIdLookupMigration)
public class OpenGroupServerIdLookupMigration: OWSDatabaseMigration {
    @objc
    class func migrationId() -> String {
        return "003"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        self.doMigrationAsync(completion: completion)
    }

    private func doMigrationAsync(completion: @escaping OWSDatabaseMigrationCompletion) {
        var lookups: [OpenGroupServerIdLookup] = []
        
        // Note: These will be done in the YDB to GRDB migration but have added it here to be safe
        NSKeyedUnarchiver.setClass(
            SMKLegacy._Thread.self,
            forClassName: "TSThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._ContactThread.self,
            forClassName: "TSContactThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._GroupThread.self,
            forClassName: "TSGroupThread"
        )
        NSKeyedUnarchiver.setClass(
            SMKLegacy._GroupModel.self,
            forClassName: "TSGroupModel"
        )
        // TODO: Add, SMKLegacy._OpenGroup, SMKLegacy._TSMessage (and related)
        
        Storage.write(with: { transaction in
            transaction.enumerateKeysAndObjects(inCollection: SMKLegacy.threadCollection) { _, object, _ in
                guard let thread = object as? SMKLegacy._GroupThread else { return }
                guard let openGroup: OpenGroupV2 = Storage.shared.getV2OpenGroup(for: thread.uniqueId) else { return }
                guard let interactionsByThread: YapDatabaseViewTransaction = transaction.ext(SMKLegacy.messageDatabaseViewExtensionName) as? YapDatabaseViewTransaction else {
                    return
                }
                
                interactionsByThread.enumerateKeysAndObjects(inGroup: thread.uniqueId) { _, _, object, _, _ in
                    guard let tsMessage: TSMessage = object as? TSMessage else { return }
                    guard let tsMessageId: String = tsMessage.uniqueId else { return }
                    
                    lookups.append(
                        OpenGroupServerIdLookup(
                            server: openGroup.server,
                            room: openGroup.room,
                            serverId: tsMessage.openGroupServerMessageID,
                            tsMessageId: tsMessageId
                        )
                    )
                }
            }
            
            lookups.forEach { lookup in
                Storage.shared.addOpenGroupServerIdLookup(lookup, using: transaction)
            }
            self.save(with: transaction) // Intentionally capture self
        }, completion: {
            completion(true, false)
        })
    }
}
