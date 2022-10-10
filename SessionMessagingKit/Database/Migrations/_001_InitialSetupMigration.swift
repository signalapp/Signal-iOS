// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _001_InitialSetupMigration: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "initialSetup"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    public static let fullTextSearchTokenizer: FTS5TokenizerDescriptor = {
        // Define the tokenizer to be used in all the FTS tables
        // https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md#fts5-tokenizers
        return .porter(wrapping: .unicode61())
    }()
    
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
        
        /// Create a full-text search table synchronized with the Profile table
        try db.create(virtualTable: Profile.fullTextSearchTableName, using: FTS5()) { t in
            t.synchronize(withTable: Profile.databaseTableName)
            t.tokenizer = _001_InitialSetupMigration.fullTextSearchTokenizer
            
            t.column(Profile.Columns.nickname.name)
            t.column(Profile.Columns.name.name)
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
            t.column(.notificationSound, .integer)
            t.column(.mutedUntilTimestamp, .double)
            t.column(.onlyNotifyForMentions, .boolean)
                .notNull()
                .defaults(to: false)
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
        
        /// Create a full-text search table synchronized with the ClosedGroup table
        try db.create(virtualTable: ClosedGroup.fullTextSearchTableName, using: FTS5()) { t in
            t.synchronize(withTable: ClosedGroup.databaseTableName)
            t.tokenizer = _001_InitialSetupMigration.fullTextSearchTokenizer
            
            t.column(ClosedGroup.Columns.name.name)
        }
        
        try db.create(table: ClosedGroupKeyPair.self) { t in
            t.column(.threadId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(ClosedGroup.self, onDelete: .cascade)     // Delete if ClosedGroup deleted
            t.column(.publicKey, .blob).notNull()
            t.column(.secretKey, .blob).notNull()
            t.column(.receivedTimestamp, .double)
                .notNull()
                .indexed()                                            // Quicker querying
            
            t.uniqueKey([.publicKey, .secretKey, .receivedTimestamp])
        }
        
        try db.create(table: OpenGroup.self) { t in
            // Note: There is no foreign key constraint here because we need an OpenGroup entry to
            // exist to be able to retrieve the default open group rooms - as a result we need to
            // manually handle deletion of this object (in both OpenGroupManager and GarbageCollectionJob)
            t.column(.threadId, .text)
                .notNull()
                .primaryKey()
            t.column(.server, .text)
                .indexed()                                            // Quicker querying
                .notNull()
            t.column(.roomToken, .text).notNull()
            t.column(.publicKey, .text).notNull()
            t.column(.isActive, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.name, .text).notNull()
            t.column(.roomDescription, .text)
            t.column(.imageId, .text)
            t.column(.imageData, .blob)
            t.column(.userCount, .integer).notNull()
            t.column(.infoUpdates, .integer).notNull()
            t.column(.sequenceNumber, .integer).notNull()
            t.column(.inboxLatestMessageId, .integer).notNull()
            t.column(.outboxLatestMessageId, .integer).notNull()
            t.column(.pollFailureCount, .integer)
                .notNull()
                .defaults(to: 0)
        }
        
        /// Create a full-text search table synchronized with the OpenGroup table
        try db.create(virtualTable: OpenGroup.fullTextSearchTableName, using: FTS5()) { t in
            t.synchronize(withTable: OpenGroup.databaseTableName)
            t.tokenizer = _001_InitialSetupMigration.fullTextSearchTokenizer
            
            t.column(OpenGroup.Columns.name.name)
        }
        
        try db.create(table: Capability.self) { t in
            t.column(.openGroupServer, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.variant, .text).notNull()
            t.column(.isMissing, .boolean).notNull()
            
            t.primaryKey([.openGroupServer, .variant])
        }
        
        try db.create(table: BlindedIdLookup.self) { t in
            t.column(.blindedId, .text)
                .primaryKey()
            t.column(.sessionId, .text)
                .indexed()                                            // Quicker querying
            t.column(.openGroupServer, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.openGroupPublicKey, .text)
                .notNull()
        }
        
        try db.create(table: _006_FixHiddenModAdminSupport.PreMigrationGroupMember.self) { t in
            // Note: Since we don't know whether this will be stored against a 'ClosedGroup' or
            // an 'OpenGroup' we add the foreign key constraint against the thread itself (which
            // shares the same 'id' as the 'groupId') so we can cascade delete automatically
            t.column(.groupId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(SessionThread.self, onDelete: .cascade)   // Delete if Thread deleted
            t.column(.profileId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.role, .integer).notNull()
        }
        
        try db.create(table: Interaction.self) { t in
            t.column(.id, .integer)
                .notNull()
                .primaryKey(autoincrement: true)
            t.column(.serverHash, .text)
            t.column(.messageUuid, .text)
                .indexed()                                            // Quicker querying
            t.column(.threadId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(SessionThread.self, onDelete: .cascade)   // Delete if Thread deleted
            t.column(.authorId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            
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
            t.column(.hasMention, .boolean)
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
            
            /// The below unique constraints are added to prevent messages being duplicated, we need
            /// multiple constraints to handle the different situations which can result in duplicate messages,
            /// the following describes the different cases where messages can be duplicated:
            ///
            /// Threads with variants: [`contact`, `closedGroup`]:
            ///   "Sync" messages (messages we resend to the current to ensure it appears on all linked devices):
            ///     `threadId`                    - Unique per thread
            ///     `authorId`                    - Unique per user
            ///     `timestampMs`              - Very low chance of collision (especially combined with other two)
            ///
            ///   Standard messages #1:
            ///     `threadId`                    - Unique per thread
            ///     `serverHash`                - Unique per message (deterministically generated)
            ///
            ///   Standard messages #1:
            ///     `threadId`                    - Unique per thread
            ///     `messageUuid`             - Very low chance of collision (especially combined with threadId)
            ///
            /// Threads with variants: [`openGroup`]:
            ///   `threadId`                                        - Unique per thread
            ///   `openGroupServerMessageId`     - Unique for VisibleMessage's on an OpenGroup server
            t.uniqueKey([.threadId, .authorId, .timestampMs])
            t.uniqueKey([.threadId, .serverHash])
            t.uniqueKey([.threadId, .messageUuid])
            t.uniqueKey([.threadId, .openGroupServerMessageId])
        }
        
        /// Create a full-text search table synchronized with the Interaction table
        try db.create(virtualTable: Interaction.fullTextSearchTableName, using: FTS5()) { t in
            t.synchronize(withTable: Interaction.databaseTableName)
            t.tokenizer = _001_InitialSetupMigration.fullTextSearchTokenizer
            
            t.column(Interaction.Columns.body.name)
        }
        
        try db.create(table: RecipientState.self) { t in
            t.column(.interactionId, .integer)
                .notNull()
                .indexed()                                            // Quicker querying
                .references(Interaction.self, onDelete: .cascade)     // Delete if interaction deleted
            t.column(.recipientId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
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
            t.column(.localRelativeFilePath, .text)
            t.column(.width, .integer)
            t.column(.height, .integer)
            t.column(.duration, .double)
            t.column(.isVisualMedia, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.isValid, .boolean)
                .notNull()
                .defaults(to: false)
            t.column(.encryptionKey, .blob)
            t.column(.digest, .blob)
            t.column(.caption, .text)
        }
        
        try db.create(table: InteractionAttachment.self) { t in
            t.column(.albumIndex, .integer).notNull()
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
                .indexed()                                            // Quicker querying
                .references(Profile.self)
            t.column(.timestampMs, .double).notNull()
            t.column(.body, .text)
            t.column(.attachmentId, .text)
                .indexed()                                            // Quicker querying
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
                .indexed()                                            // Quicker querying
                .references(Attachment.self)                          // Managed via garbage collection
            
            t.primaryKey([.url, .timestamp])
        }
        
        try db.create(table: ControlMessageProcessRecord.self) { t in
            t.column(.threadId, .text)
                .notNull()
                .indexed()                                            // Quicker querying
            t.column(.variant, .integer).notNull()
            t.column(.timestampMs, .integer).notNull()
            t.column(.serverExpirationTimestamp, .double)
            
            t.uniqueKey([.threadId, .variant, .timestampMs])
        }
        
        try db.create(table: ThreadTypingIndicator.self) { t in
            t.column(.threadId, .text)
                .primaryKey()
                .references(SessionThread.self, onDelete: .cascade)   // Delete if thread deleted
            t.column(.timestampMs, .integer).notNull()
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
