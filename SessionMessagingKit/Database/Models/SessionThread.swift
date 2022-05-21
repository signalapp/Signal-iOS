// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
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
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
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
    
    public func insert(_ db: Database) throws {
        try performInsert(db)
        
        db[.hasSavedThread] = true
    }
    
    public func delete(_ db: Database) throws -> Bool {
        // Delete any jobs associated to this thread
        try Job
            .filter(Job.Columns.threadId == id)
            .deleteAll(db)
        
        // Delete any GroupMembers associated to this thread
        if variant == .closedGroup || variant == .openGroup {
            try GroupMember
                .filter(GroupMember.Columns.groupId == id)
                .deleteAll(db)
        }
        
        return try performDelete(db)
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
    
    static func messageRequestThreads(_ db: Database) -> QueryInterfaceRequest<SessionThread> {
        return SessionThread
            .filter(Columns.shouldBeVisible == true)
            .filter(Columns.variant == Variant.contact)
            .filter(Columns.id != getUserHexEncodedPublicKey(db))
            .joining(
                optional: contact
                    .filter(Contact.Columns.isApproved == false)
            )
    }
    
    func isMessageRequest(_ db: Database) -> Bool {
        return (
            shouldBeVisible &&
            variant == .contact &&
            id != getUserHexEncodedPublicKey(db) && // Note to self
            (try? Contact.fetchOne(db, id: id))?.isApproved != true
        )
    }
}

// MARK: - Convenience

public extension SessionThread {
    static func displayName(userPublicKey: String) -> SQLSpecificExpressible {
        let contactAlias: TypedTableAlias<Contact> = TypedTableAlias()
        
        return (
            (
                (
                    SessionThread.Columns.variant == SessionThread.Variant.closedGroup &&
                    ClosedGroup.Columns.name
                ) || (
                    SessionThread.Columns.variant == SessionThread.Variant.openGroup &&
                    OpenGroup.Columns.name
                ) || (
                    isNoteToSelf(userPublicKey: userPublicKey)
                ) || (
                    Profile.Columns.nickname ||
                    Profile.Columns.name
                    //customFallback: Profile.truncated(id: thread.id, truncating: .middle)
                )
            )
        )
    }
    
    /// This method can be used to create a query based on whether a thread is the note to self thread
    static func isNoteToSelf(userPublicKey: String) -> SQLSpecificExpressible {
        return (
            SessionThread.Columns.variant == SessionThread.Variant.contact &&
            SessionThread.Columns.id == userPublicKey
        )
    }
    
    /// This method can be used to filter a thread query to only include messages requests
    ///
    /// **Note:** In order to use this filter you **MUST** have a `joining(required/optional:)` to the
    /// `SessionThread.contact` association or it won't work
    static func isMessageRequest(userPublicKey: String) -> SQLSpecificExpressible {
        let threadAlias: TypedTableAlias<SessionThread> = TypedTableAlias()
        let contactAlias: TypedTableAlias<Contact> = TypedTableAlias()
        
        return SQL(
            """
                \(threadAlias[.shouldBeVisible]) = true AND
                    \(SQL("\(threadAlias[.variant]) = \(SessionThread.Variant.contact)")) AND
                    \(SQL("\(threadAlias[.id]) != \(userPublicKey)")) AND (
                        /* Note: A '!= true' check doesn't work properly so we need to be explicit */
                        \(contactAlias[.isApproved]) IS NULL OR
                        \(contactAlias[.isApproved]) = false
                    )
            """
        )
    }
    
    /// This method can be used to filter a thread query to exclude messages requests
    ///
    /// **Note:** In order to use this filter you **MUST** have a `joining(required/optional:)` to the
    /// `SessionThread.contact` association or it won't work
    static func isNotMessageRequest(userPublicKey: String) -> SQLSpecificExpressible {
        let contactAlias: TypedTableAlias<Contact> = TypedTableAlias()
        
        return (
            SessionThread.Columns.shouldBeVisible == true && (
                SessionThread.Columns.variant != SessionThread.Variant.contact ||
                SessionThread.Columns.id == userPublicKey ||     // Note to self
                contactAlias[.isApproved] == true
            )
        )
    }
    
    func isNoteToSelf(_ db: Database? = nil) -> Bool {
        return (
            variant == .contact &&
            id == getUserHexEncodedPublicKey(db)
        )
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
}

// MARK: - Objective-C Support

// FIXME: Remove when possible

@objc(SMKThread)
public class SMKThread: NSObject {
    @objc(deleteAll)
    public static func deleteAll() {
        GRDBStorage.shared.writeAsync { db in
            _ = try SessionThread.deleteAll(db)
        }
    }
    
    @objc(isThreadMuted:)
    public static func isThreadMuted(_ threadId: String) -> Bool {
        return GRDBStorage.shared.read { db in
            let mutedUntilTimestamp: TimeInterval? = try SessionThread
                .select(SessionThread.Columns.mutedUntilTimestamp)
                .filter(id: threadId)
                .asRequest(of: TimeInterval?.self)
                .fetchOne(db)
            
            return (mutedUntilTimestamp != nil)
        }
        .defaulting(to: false)
    }
    
    @objc(isOnlyNotifyingForMentions:)
    public static func isOnlyNotifyingForMentions(_ threadId: String) -> Bool {
        return GRDBStorage.shared.read { db in
            return try SessionThread
                .select(SessionThread.Columns.onlyNotifyForMentions == true)
                .filter(id: threadId)
                .asRequest(of: Bool.self)
                .fetchOne(db)
        }
        .defaulting(to: false)
    }
    
    @objc(setIsOnlyNotifyingForMentions:to:)
    public static func isOnlyNotifyingForMentions(_ threadId: String, isEnabled: Bool) {
        GRDBStorage.shared.write { db in
            try SessionThread
                .filter(id: threadId)
                .updateAll(db, SessionThread.Columns.onlyNotifyForMentions.set(to: isEnabled))
        }
    }
    
    @objc(mutedUntilDateFor:)
    public static func mutedUntilDateFor(_ threadId: String) -> Date? {
        return GRDBStorage.shared.read { db in
            return try SessionThread
                .select(SessionThread.Columns.mutedUntilTimestamp)
                .filter(id: threadId)
                .asRequest(of: TimeInterval.self)
                .fetchOne(db)
        }
        .map { Date(timeIntervalSince1970: $0) }
    }
    
    @objc(updateWithMutedUntilDateTo:forThreadId:)
    public static func updateWithMutedUntilDate(to date: Date?, threadId: String) {
        GRDBStorage.shared.write { db in
            try SessionThread
                .filter(id: threadId)
                .updateAll(db, SessionThread.Columns.mutedUntilTimestamp.set(to: date?.timeIntervalSince1970))
        }
    }
}
