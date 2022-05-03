// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct SessionThread: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "thread" }
    private static let contact = hasOne(Contact.self, using: Contact.threadForeignKey)
    private static let closedGroup = hasOne(ClosedGroup.self, using: ClosedGroup.threadForeignKey)
    private static let openGroup = hasOne(OpenGroup.self, using: OpenGroup.threadForeignKey)
    private static let disappearingMessagesConfiguration = hasOne(
        DisappearingMessagesConfiguration.self,
        using: DisappearingMessagesConfiguration.threadForeignKey
    )
    public static let interactions = hasMany(Interaction.self, using: Interaction.threadForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case variant
        case creationDateTimestamp
        case shouldBeVisible
        case isPinned
        case messageDraft
        case notificationMode
        case notificationSound
        case mutedUntilTimestamp
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case contact
        case closedGroup
        case openGroup
    }
    
    public enum NotificationMode: Int, Codable, DatabaseValueConvertible {
        case none
        case all
        case mentionsOnly   // Only applicable to group threads
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
    
    /// The notification mode this thread is set to
    public let notificationMode: NotificationMode
    
    /// The sound which should be used when receiving a notification for this thread
    ///
    /// **Note:** If unset this will use the `Preferences.Sound.defaultNotificationSound`
    public let notificationSound: Preferences.Sound?
    
    /// Timestamp (seconds since epoch) for when this thread should stop being muted
    public let mutedUntilTimestamp: TimeInterval?
    
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
    
    // MARK: - Initialization
    
    public init(
        id: String,
        variant: Variant,
        creationDateTimestamp: TimeInterval = Date().timeIntervalSince1970,
        shouldBeVisible: Bool = false,
        isPinned: Bool = false,
        messageDraft: String? = nil,
        notificationMode: NotificationMode = .all,
        notificationSound: Preferences.Sound? = nil,
        mutedUntilTimestamp: TimeInterval? = nil
    ) {
        self.id = id
        self.variant = variant
        self.creationDateTimestamp = creationDateTimestamp
        self.shouldBeVisible = shouldBeVisible
        self.isPinned = isPinned
        self.messageDraft = messageDraft
        self.notificationMode = notificationMode
        self.notificationSound = notificationSound
        self.mutedUntilTimestamp = mutedUntilTimestamp
    }
    
    // MARK: - Custom Database Interaction
    
    public func delete(_ db: Database) throws -> Bool {
        // Delete any jobs associated to this thread
        try Job
            .filter(Job.Columns.threadId == id)
            .deleteAll(db)
        
        return try performDelete(db)
    }
}

// MARK: - Mutation

public extension SessionThread {
    func with(
        shouldBeVisible: Bool? = nil
    ) -> SessionThread {
        return SessionThread(
            id: id,
            variant: variant,
            creationDateTimestamp: creationDateTimestamp,
            shouldBeVisible: (shouldBeVisible ?? self.shouldBeVisible),
            isPinned: isPinned,
            messageDraft: messageDraft,
            notificationMode: notificationMode,
            notificationSound: notificationSound,
            mutedUntilTimestamp: mutedUntilTimestamp
        )
    }
}

// MARK: - GRDB Interactions

public extension SessionThread {
    /// The `variant` will be ignored if an existing thread is found
    static func fetchOrCreate(_ db: Database, id: ID, variant: Variant) -> SessionThread {
        return ((try? fetchOne(db, id: id)) ?? SessionThread(id: id, variant: variant))
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
    func isNoteToSelf(_ db: Database? = nil) -> Bool {
        return (
            variant == .contact &&
            id == getUserHexEncodedPublicKey(db)
        )
    }
    
    func name(_ db: Database) -> String {
        switch variant {
            case .contact:
                guard !isNoteToSelf(db) else { return name(isNoteToSelf: true) }
                
                return name(
                    displayName: Profile.displayName(
                        db,
                        id: id,
                        customFallback: Profile.truncated(id: id, truncating: .middle)
                    )
                )
            
            case .closedGroup:
                return name(displayName: try? String.fetchOne(db, closedGroup.select(.name)))
                
            case .openGroup:
                return name(displayName: try? String.fetchOne(db, openGroup.select(.name)))
        }
    }
    
    func name(isNoteToSelf: Bool = false, displayName: String? = nil) -> String {
        switch variant {
            case .contact:
                guard !isNoteToSelf else { return "Note to Self" }
                
                return displayName
                    .defaulting(to: "Anonymous", useDefaultIfEmpty: true)
            
            case .closedGroup, .openGroup:
                return displayName
                    .defaulting(to: "Group", useDefaultIfEmpty: true)
        }
    }
}
