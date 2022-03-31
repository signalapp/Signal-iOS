// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

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
        
        Storage.write(with: { transaction in
            TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread: TSGroupThread = object as? TSGroupThread else { return }
                guard let threadId: String = thread.uniqueId else { return }
                guard let openGroup: OpenGroupV2 = Storage.shared.getV2OpenGroup(for: threadId) else { return }
                
                thread.enumerateInteractions(with: transaction) { interaction, _ in
                    guard let tsMessage: TSMessage = interaction as? TSMessage else { return }
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
