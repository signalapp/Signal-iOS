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

    public let id: String
    public let variant: Variant
    public let creationDateTimestamp: TimeInterval
    public let shouldBeVisible: Bool
    public let isPinned: Bool
    public let messageDraft: String?
    public let notificationMode: NotificationMode
    public let notificationSound: Preferences.Sound?
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
            case .contact: return Profile.displayName(db, id: id)
            
            case .closedGroup:
                guard let name: String = try? closedGroup.fetchOne(db)?.name, !name.isEmpty else {
                    return "Group"
                }
                
                return name
                
            case .openGroup:
                guard let name: String = try? openGroup.fetchOne(db)?.name, !name.isEmpty else {
                    return "Group"
                }
                
                return name
        }
    }
}
