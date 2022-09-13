// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This migration adds the new types needed for Emoji Reacts
enum _008_EmojiReacts: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "EmojiReacts"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        try db.create(table: Reaction.self) { t in
            t.column(.interactionId, .numeric)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(Interaction.self, onDelete: .cascade)     // Delete if Interaction deleted
            t.column(.serverHash, .text)
            t.column(.timestampMs, .text)
                .notNull()
            t.column(.authorId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.emoji, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.count, .integer)
                .notNull()
                .defaults(to: 0)
            t.column(.sortId, .integer)
                .notNull()
                .defaults(to: 0)
            
            /// A specific author should only be able to have a single instance of each emoji on a particular interaction
            t.uniqueKey([.interactionId, .emoji, .authorId])
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
