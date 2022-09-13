// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This migration fixes an issue where hidden mods/admins weren't getting recognised as mods/admins, it reset's the `info_updates`
/// for open groups so they will fully re-fetch their mod/admin lists
enum _006_FixHiddenModAdminSupport: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "FixHiddenModAdminSupport"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        try db.alter(table: GroupMember.self) { t in
            t.add(.isHidden, .boolean)
                .notNull()
                .defaults(to: false)
        }
        
        // When modifying OpenGroup behaviours we should always look to reset the `infoUpdates`
        // value for all OpenGroups to ensure they all have the correct state for newly
        // added/changed fields
        _ = try OpenGroup
            .updateAll(db, OpenGroup.Columns.infoUpdates.set(to: 0))
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}

// MARK: - Pre-Migration Types

extension _006_FixHiddenModAdminSupport {
    internal struct PreMigrationGroupMember: Codable, PersistableRecord, TableRecord, ColumnExpressible {
        public static var databaseTableName: String { "groupMember" }
        
        public typealias Columns = CodingKeys
        public enum CodingKeys: String, CodingKey, ColumnExpression {
            case groupId
            case profileId
            case role
        }
        
        public enum Role: Int, Codable, DatabaseValueConvertible {
            case standard
            case zombie
            case moderator
            case admin
        }

        public let groupId: String
        public let profileId: String
        public let role: Role
        
        // MARK: - Initialization
        
        public init(
            groupId: String,
            profileId: String,
            role: Role
        ) {
            self.groupId = groupId
            self.profileId = profileId
            self.role = role
        }
    }
}
