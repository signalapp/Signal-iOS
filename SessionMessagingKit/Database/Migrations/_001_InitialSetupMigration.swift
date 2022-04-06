// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _001_InitialSetupMigration: Migration {
    static let identifier: String = "initialSetup"
    
    static func migrate(_ db: Database) throws {
        try db.create(table: Contact.self) { t in
            t.column(.id, .text)
                .notNull()
                .primaryKey()
            t.column(.isTrusted, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.isApproved, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.isBlocked, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.didApproveMe, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.hasBeenBlocked, .boolean)
                .notNull()
                .defaults(to: false)
        }
        
        try db.create(table: Profile.self) { t in
            t.column(.id, .text)
                .notNull()
                .primaryKey()
            t.column(.name, .text).notNull()
            t.column(.nickname, .text)
            t.column(.profilePictureUrl, .text)
            t.column(.profilePictureFileName, .text)
            t.column(.profileEncryptionKey, .blob)
        }
        
        try db.create(table: SessionThread.self) { t in
            t.column(.id, .text)
                .notNull()
                .primaryKey()
            t.column(.variant, .integer).notNull()
            t.column(.creationDateTimestamp, .double).notNull()
            t.column(.shouldBeVisible, .boolean).notNull()
            t.column(.isPinned, .boolean).notNull()
            t.column(.messageDraft, .text)
            t.column(.notificationMode, .integer).notNull()
            t.column(.mutedUntilTimestamp, .double)
        }
        
        try db.create(table: DisappearingMessagesConfiguration.self) { t in
            t.column(.id, .text)
                .notNull()
                .primaryKey()
                .references(SessionThread.self)
            t.column(.isEnabled, .boolean)
                .defaults(to: false)
                .notNull()
            t.column(.durationSeconds, .double)
                .defaults(to: 0)
                .notNull()
        }
        
        try db.create(table: ClosedGroup.self) { t in
            t.column(.publicKey, .text)
                .notNull()
                .primaryKey()
            t.column(.name, .text).notNull()
            t.column(.formationTimestamp, .double).notNull()
        }
        
        try db.create(table: ClosedGroupKeyPair.self) { t in
            t.column(.publicKey, .text)
                .notNull()
                .indexed()
                .references(ClosedGroup.self)
            t.column(.secretKey, .blob).notNull()
            t.column(.receivedTimestamp, .double).notNull()
        }
        
        try db.create(table: GroupMember.self) { t in
            t.column(.groupId, .text)
                .notNull()
                .indexed()
            t.column(.profileId, .text).notNull()
            t.column(.role, .integer).notNull()
        }
    }
}
