// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This migration fixes a bug where certain message variants could incorrectly be counted as unread messages
enum _005_FixDeletedMessageReadState: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "FixDeletedMessageReadState"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        _ = try Interaction
            .filter(
                Interaction.Columns.variant == Interaction.Variant.standardIncomingDeleted ||
                Interaction.Columns.variant == Interaction.Variant.standardOutgoing ||
                Interaction.Columns.variant == Interaction.Variant.infoDisappearingMessagesUpdate
            )
            .updateAll(db, Interaction.Columns.wasRead.set(to: true))
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
