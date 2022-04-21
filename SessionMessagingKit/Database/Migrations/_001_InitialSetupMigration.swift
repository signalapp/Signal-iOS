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
            t.column(.notificationMode, .integer)
                .notNull()
                .defaults(to: SessionThread.NotificationMode.all)
            t.column(.notificationSound, .integer)
            t.column(.mutedUntilTimestamp, .double)
        }
        
        try db.create(table: DisappearingMessagesConfiguration.self) { t in
            t.column(.threadId, .text)
                .notNull()
                .primaryKey()
                .references(SessionThread.self, onDelete: .cascade)   // Delete if Thread deleted
            t.column(.isEnabled, .boolean)
                .defaults(to: false)
                .notNull()
            t.column(.durationSeconds, .double)
                .defaults(to: 0)
                .notNull()
        }
        
        try db.create(table: ClosedGroup.self) { t in
            t.column(.threadId, .text)
                .notNull()
                .primaryKey()
                .references(SessionThread.self, onDelete: .cascade)   // Delete if Thread deleted
            t.column(.name, .text).notNull()
            t.column(.formationTimestamp, .double).notNull()
        }
        
        try db.create(table: ClosedGroupKeyPair.self) { t in
            t.column(.publicKey, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(ClosedGroup.self, onDelete: .cascade)     // Delete if ClosedGroup deleted
            t.column(.secretKey, .blob).notNull()
            t.column(.receivedTimestamp, .double).notNull()
        }
        
        try db.create(table: OpenGroup.self) { t in
            t.column(.threadId, .text)
                .notNull()
                .primaryKey()
                .references(SessionThread.self, onDelete: .cascade)   // Delete if Thread deleted
            t.column(.server, .text).notNull()
            t.column(.room, .text).notNull()
            t.column(.publicKey, .text).notNull()
            t.column(.name, .text).notNull()
            t.column(.groupDescription, .text)
            t.column(.imageId, .text)
            t.column(.imageData, .blob)
            t.column(.userCount, .integer).notNull()
            t.column(.infoUpdates, .integer).notNull()
        }
        
        try db.create(table: Capability.self) { t in
            t.column(.openGroupId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(OpenGroup.self, onDelete: .cascade)       // Delete if OpenGroup deleted
            t.column(.capability, .text).notNull()
            t.column(.isMissing, .boolean).notNull()
            
            t.primaryKey([.openGroupId, .capability])
        }
        
        try db.create(table: GroupMember.self) { t in
            // Note: Not adding a "proper" foreign key constraint as this
            // table gets used by both 'OpenGroup' and 'ClosedGroup' types
            t.column(.groupId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.profileId, .text).notNull()
            t.column(.role, .integer).notNull()
        }
        
        try db.create(table: Interaction.self) { t in
            t.column(.id, .integer)
                .notNull()
                .primaryKey(autoincrement: true)
            t.column(.serverHash, .text)
            t.column(.threadId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(SessionThread.self, onDelete: .cascade)   // Delete if Thread deleted
            t.column(.authorId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(Profile.self)
            
            t.column(.variant, .integer).notNull()
            t.column(.body, .text)
            t.column(.timestampMs, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.receivedAtTimestampMs, .integer).notNull()
            t.column(.wasRead, .boolean)
                .notNull()
                .indexed()                                            // Quicker querying
                .defaults(to: false)
            t.column(.expiresInSeconds, .double)
            t.column(.expiresStartedAtMs, .double)
            t.column(.linkPreviewUrl, .text)
            
            t.column(.openGroupServerMessageId, .integer)
                .indexed()                                            // Quicker querying
            t.column(.openGroupWhisperMods, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.openGroupWhisperTo, .text)
            
            /// Note: The below unique constraints are added to prevent messages being duplicated, we need
            /// multiple constraints because `null` is not unique in SQLite which means any unique constraint
            /// which contained a nullable column would not be seen as unique if the value is null (this is good to
            /// avoid outgoing message from conflicting due to not having a `serverHash` but bad when different
            /// columns are only unique in certain circumstances)
            ///
            /// The values have the following behaviours:
            ///
            /// Threads with variants: [`contact`, `closedGroup`]:
            ///    `threadId`                    - Unique per thread
            ///    `serverHash`                - Unique per message for service-node-based messages
            ///                       **Note:** Some InfoMessage's will have this intentionally left `null`
            ///                       as we want to ignore any collisions and re-process them
            ///    `timestampMs`              - Very low chance of collision (especially combined with other two)
            ///
            /// Threads with variants: [`openGroup`]:
            /// `threadId`                                        - Unique per thread
            /// `openGroupServerMessageId`     - Unique for VisibleMessage's on an OpenGroup server
            t.uniqueKey([.threadId, .serverHash, .timestampMs])
            t.uniqueKey([.threadId, .openGroupServerMessageId])
        }
        
        try db.create(table: RecipientState.self) { t in
            t.column(.interactionId, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(Interaction.self, onDelete: .cascade)     // Delete if interaction deleted
            t.column(.recipientId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(Profile.self)
            t.column(.state, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.readTimestampMs, .double)
            t.column(.mostRecentFailureText, .text)
            
            // We want to ensure that a recipient can only have a single state for
            // each interaction
            t.primaryKey([.interactionId, .recipientId])
        }
        
        try db.create(table: Attachment.self) { t in
            t.column(.id, .text)
                .notNull()
                .primaryKey()
            t.column(.serverId, .text)
            t.column(.variant, .integer).notNull()
            t.column(.state, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.contentType, .text).notNull()
            t.column(.byteCount, .integer)
                .notNull()
                .defaults(to: 0)
            t.column(.creationTimestamp, .double)
            t.column(.sourceFilename, .text)
            t.column(.downloadUrl, .text)
            t.column(.width, .integer)
            t.column(.height, .integer)
            t.column(.encryptionKey, .blob)
            t.column(.digest, .blob)
            t.column(.caption, .text)
        }
        
        try db.create(table: InteractionAttachment.self) { t in
            t.column(.interactionId, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(Interaction.self, onDelete: .cascade)     // Delete if interaction deleted
            t.column(.attachmentId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(Attachment.self, onDelete: .cascade)      // Delete if attachment deleted
        }
        
        try db.create(table: Quote.self) { t in
            t.column(.interactionId, .integer)
                .notNull()
                .primaryKey()
                .references(Interaction.self, onDelete: .cascade)     // Delete if interaction deleted
            t.column(.authorId, .text)
                .notNull()
                .references(Profile.self)
            t.column(.timestampMs, .double).notNull()
            t.column(.body, .text)
            t.column(.attachmentId, .text)
                .references(Attachment.self, onDelete: .setNull)      // Clear if attachment deleted
        }
        
        try db.create(table: LinkPreview.self) { t in
            t.column(.url, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.timestamp, .double)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.variant, .integer).notNull()
            t.column(.title, .text)
            t.column(.attachmentId, .text)
                .references(Attachment.self, onDelete: .setNull)      // Clear if attachment deleted
            
            t.primaryKey([.url, .timestamp])
        }
        
        try db.create(table: ControlMessageProcessRecord.self) { t in
            t.column(.threadId, .text).notNull()
            t.column(.sentTimestampMs, .integer).notNull()
            t.column(.serverHash, .text).notNull()
            t.column(.openGroupMessageServerId, .integer).notNull()
            
            t.uniqueKey([.threadId, .sentTimestampMs, .serverHash, .openGroupMessageServerId])
        }
        
        try db.create(table: Job.self) { t in
            t.column(.id, .integer)
                .notNull()
                .primaryKey(autoincrement: true)
            t.column(.failureCount, .integer)
                .notNull()
                .defaults(to: 0)
            t.column(.variant, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.behaviour, .integer).notNull()    // TODO: Indexed???
            t.column(.nextRunTimestamp, .double)
                .notNull()  // TODO: Should this just be nullable??? (or do we want to fetch by this?)
                .indexed()                                            // Quicker querying
                .defaults(to: 0)
            t.column(.threadId, .text)
                .indexed()                                            // Quicker querying
                .references(SessionThread.self, onDelete: .cascade)   // Delete if thread deleted
            t.column(.details, .blob)
        }
    }
}
