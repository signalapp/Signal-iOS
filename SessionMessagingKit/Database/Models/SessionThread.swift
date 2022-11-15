// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import SessionUtilitiesKit

public struct SessionThread: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "thread" }
    public static let contact = hasOne(Contact.self, using: Contact.threadForeignKey)
    public static let closedGroup = hasOne(ClosedGroup.self, using: ClosedGroup.threadForeignKey)
    public static let openGroup = hasOne(OpenGroup.self, using: OpenGroup.threadForeignKey)
    private static let disappearingMessagesConfiguration = hasOne(
        DisappearingMessagesConfiguration.self,
        using: DisappearingMessagesConfiguration.threadForeignKey
    )
    public static let interactions = hasMany(Interaction.self, using: Interaction.threadForeignKey)
    public static let typingIndicator = hasOne(
        ThreadTypingIndicator.self,
        using: ThreadTypingIndicator.threadForeignKey
    )
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case variant
        case creationDateTimestamp
        case shouldBeVisible
        case isPinned
        case messageDraft
        case notificationSound
        case mutedUntilTimestamp
        case onlyNotifyForMentions
    }
    
    public enum Variant: Int, Codable, Hashable, DatabaseValueConvertible {
        case contact
        case closedGroup
        case openGroup
    }

    /// Unique identifier for a thread (formerly known as uniqueId)
    ///
    /// This value will depend on the variant:
    /// **contact:** The contact id
    /// **closedGroup:** The closed group public key
    /// **openGroup:** The `\(server.lowercased()).\(room)` value
    public let id: String
    
    /// Enum indicating what type of thread this is
    public let variant: Variant
    
    /// A timestamp indicating when this thread was created
    public let creationDateTimestamp: TimeInterval
    
    /// A flag indicating whether the thread should be visible
    public let shouldBeVisible: Bool
    
    /// A flag indicating whether the thread is pinned
    public let isPinned: Bool
    
    /// The value the user started entering into the input field before they left the conversation screen
    public let messageDraft: String?
    
    /// The sound which should be used when receiving a notification for this thread
    ///
    /// **Note:** If unset this will use the `Preferences.Sound.defaultNotificationSound`
    public let notificationSound: Preferences.Sound?
    
    /// Timestamp (seconds since epoch) for when this thread should stop being muted
    public let mutedUntilTimestamp: TimeInterval?
    
    /// A flag indicating whether the thread should only notify for mentions
    public let onlyNotifyForMentions: Bool
    
    // MARK: - Relationships
    
    public var contact: QueryInterfaceRequest<Contact> {
        request(for: SessionThread.contact)
    }
    
    public var closedGroup: QueryInterfaceRequest<ClosedGroup> {
        request(for: SessionThread.closedGroup)
    }
    
    public var openGroup: QueryInterfaceRequest<OpenGroup> {
        request(for: SessionThread.openGroup)
    }
    
    public var disappearingMessagesConfiguration: QueryInterfaceRequest<DisappearingMessagesConfiguration> {
        request(for: SessionThread.disappearingMessagesConfiguration)
    }
    
    public var interactions: QueryInterfaceRequest<Interaction> {
        request(for: SessionThread.interactions)
    }
    
    public var typingIndicator: QueryInterfaceRequest<ThreadTypingIndicator> {
        request(for: SessionThread.typingIndicator)
    }
    
    // MARK: - Initialization
    
    public init(
        id: String,
        variant: Variant,
        creationDateTimestamp: TimeInterval = Date().timeIntervalSince1970,
        shouldBeVisible: Bool = false,
        isPinned: Bool = false,
        messageDraft: String? = nil,
        notificationSound: Preferences.Sound? = nil,
        mutedUntilTimestamp: TimeInterval? = nil,
        onlyNotifyForMentions: Bool = false
    ) {
        self.id = id
        self.variant = variant
        self.creationDateTimestamp = creationDateTimestamp
        self.shouldBeVisible = shouldBeVisible
        self.isPinned = isPinned
        self.messageDraft = messageDraft
        self.notificationSound = notificationSound
        self.mutedUntilTimestamp = mutedUntilTimestamp
        self.onlyNotifyForMentions = onlyNotifyForMentions
    }
    
    // MARK: - Custom Database Interaction
    
    public func willInsert(_ db: Database) throws {
        db[.hasSavedThread] = true
    }
}

// MARK: - Mutation

public extension SessionThread {
    func with(
        shouldBeVisible: Bool? = nil,
        isPinned: Bool? = nil
    ) -> SessionThread {
        return SessionThread(
            id: id,
            variant: variant,
            creationDateTimestamp: creationDateTimestamp,
            shouldBeVisible: (shouldBeVisible ?? self.shouldBeVisible),
            isPinned: (isPinned ?? self.isPinned),
            messageDraft: messageDraft,
            notificationSound: notificationSound,
            mutedUntilTimestamp: mutedUntilTimestamp,
            onlyNotifyForMentions: onlyNotifyForMentions
        )
    }
}

// MARK: - GRDB Interactions

public extension SessionThread {
    /// Fetches or creates a SessionThread with the specified id and variant
    ///
    /// **Notes:**
    /// - The `variant` will be ignored if an existing thread is found
    /// - This method **will** save the newly created SessionThread to the database
    static func fetchOrCreate(_ db: Database, id: ID, variant: Variant) throws -> SessionThread {
        guard let existingThread: SessionThread = try? fetchOne(db, id: id) else {
            return try SessionThread(id: id, variant: variant)
                .saved(db)
        }
        
        return existingThread
    }
    
    func isMessageRequest(_ db: Database, includeNonVisible: Bool = false) -> Bool {
        return (
            (includeNonVisible || shouldBeVisible) &&
            variant == .contact &&
            id != getUserHexEncodedPublicKey(db) && // Note to self
            (try? Contact
                .filter(id: id)
                .select(.isApproved)
                .asRequest(of: Bool.self)
                .fetchOne(db))
                .defaulting(to: false) == false
        )
    }
}

// MARK: - Convenience

public extension SessionThread {
    static func messageRequestsQuery(userPublicKey: String, includeNonVisible: Bool = false) -> SQLRequest<SessionThread> {
        let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
        let contact: TypedTableAlias<Contact> = TypedTableAlias()
        
        return """
            SELECT \(thread.allColumns())
            FROM \(SessionThread.self)
            LEFT JOIN \(Contact.self) ON \(contact[.id]) = \(thread[.id])
            WHERE (
                \(SessionThread.isMessageRequest(userPublicKey: userPublicKey, includeNonVisible: includeNonVisible))
            )
        """
    }
    
    static func unreadMessageRequestsCountQuery(userPublicKey: String, includeNonVisible: Bool = false) -> SQLRequest<Int> {
        let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let contact: TypedTableAlias<Contact> = TypedTableAlias()
        
        return """
            SELECT COUNT(DISTINCT id) FROM (
                SELECT \(thread[.id]) AS id
                FROM \(SessionThread.self)
                JOIN \(Interaction.self) ON (
                    \(interaction[.threadId]) = \(thread[.id]) AND
                    \(interaction[.wasRead]) = false
                )
                LEFT JOIN \(Contact.self) ON \(contact[.id]) = \(thread[.id])
                WHERE (
                    \(SessionThread.isMessageRequest(userPublicKey: userPublicKey, includeNonVisible: includeNonVisible))
                )
            )
        """
    }
    
    /// This method can be used to filter a thread query to only include messages requests
    ///
    /// **Note:** In order to use this filter you **MUST** have a `joining(required/optional:)` to the
    /// `SessionThread.contact` association or it won't work
    static func isMessageRequest(userPublicKey: String, includeNonVisible: Bool = false) -> SQLSpecificExpressible {
        let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
        let contact: TypedTableAlias<Contact> = TypedTableAlias()
        let shouldBeVisibleSQL: SQL = (includeNonVisible ?
            SQL(stringLiteral: "true") :
            SQL("\(thread[.shouldBeVisible]) = true")
        )
        
        return SQL(
            """
                \(shouldBeVisibleSQL) AND
                \(SQL("\(thread[.variant]) = \(SessionThread.Variant.contact)")) AND
                \(SQL("\(thread[.id]) != \(userPublicKey)")) AND
                IFNULL(\(contact[.isApproved]), false) = false
            """
        )
    }
    
    func isNoteToSelf(_ db: Database? = nil) -> Bool {
        return (
            variant == .contact &&
            id == getUserHexEncodedPublicKey(db)
        )
    }
    
    func shouldShowNotification(_ db: Database, for interaction: Interaction, isMessageRequest: Bool) -> Bool {
        // Ensure that the thread isn't muted and either the thread isn't only notifying for mentions
        // or the user was actually mentioned
        guard
            Date().timeIntervalSince1970 > (self.mutedUntilTimestamp ?? 0) &&
            (
                self.variant == .contact ||
                !self.onlyNotifyForMentions ||
                interaction.hasMention
            )
        else { return false }
        
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        // No need to notify the user for self-send messages
        guard interaction.authorId != userPublicKey else { return false }
        
        // If the thread is a message request then we only want to notify for the first message
        if self.variant == .contact && isMessageRequest {
            let hasHiddenMessageRequests: Bool = db[.hasHiddenMessageRequests]
            
            // If the user hasn't hidden the message requests section then only show the notification if
            // all the other message request threads have been read
            if !hasHiddenMessageRequests {
                let numUnreadMessageRequestThreads: Int = (try? SessionThread
                    .unreadMessageRequestsCountQuery(userPublicKey: userPublicKey, includeNonVisible: true)
                    .fetchOne(db))
                    .defaulting(to: 1)
                
                guard numUnreadMessageRequestThreads == 1 else { return false }
            }
            
            // We only want to show a notification for the first interaction in the thread
            guard ((try? self.interactions.fetchCount(db)) ?? 0) <= 1 else { return false }
            
            // Need to re-show the message requests section if it had been hidden
            if hasHiddenMessageRequests {
                db[.hasHiddenMessageRequests] = false
            }
        }
        
        return true
    }
    
    static func displayName(
        threadId: String,
        variant: Variant,
        closedGroupName: String? = nil,
        openGroupName: String? = nil,
        isNoteToSelf: Bool = false,
        profile: Profile? = nil
    ) -> String {
        switch variant {
            case .closedGroup: return (closedGroupName ?? "Unknown Group")
            case .openGroup: return (openGroupName ?? "Unknown Group")
            case .contact:
                guard !isNoteToSelf else { return "NOTE_TO_SELF".localized() }
                guard let profile: Profile = profile else {
                    return Profile.truncated(id: threadId, truncating: .middle)
                }
                
                return profile.displayName()
        }
    }
    
    static func getUserHexEncodedBlindedKey(
        threadId: String,
        threadVariant: Variant
    ) -> String? {
        guard
            threadVariant == .openGroup,
            let blindingInfo: (edkeyPair: Box.KeyPair?, publicKey: String?) = Storage.shared.read({ db in
                return (
                    Identity.fetchUserEd25519KeyPair(db),
                    try OpenGroup
                        .filter(id: threadId)
                        .select(.publicKey)
                        .asRequest(of: String.self)
                        .fetchOne(db)
                )
            }),
            let userEdKeyPair: Box.KeyPair = blindingInfo.edkeyPair,
            let publicKey: String = blindingInfo.publicKey
        else { return nil }
        
        let sodium: Sodium = Sodium()
        
        let blindedKeyPair: Box.KeyPair? = sodium.blindedKeyPair(
            serverPublicKey: publicKey,
            edKeyPair: userEdKeyPair,
            genericHash: sodium.getGenericHash()
        )
        
        return blindedKeyPair.map { keyPair -> String in
            SessionId(.blinded, publicKey: keyPair.publicKey).hexString
        }
    }
}
