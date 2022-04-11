// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Interaction: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "interaction" }
    internal static let threadForeignKey = ForeignKey([Columns.threadId], to: [SessionThread.Columns.id])
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    internal static let linkPreviewForeignKey = ForeignKey(
        [Columns.linkPreviewUrl],
        to: [LinkPreview.Columns.url]
    )
    private static let thread = belongsTo(SessionThread.self, using: threadForeignKey)
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    private static let attachments = hasMany(Attachment.self, using: Attachment.interactionForeignKey)
    private static let quote = hasOne(Quote.self, using: Quote.interactionForeignKey)
    private static let linkPreview = hasOne(LinkPreview.self, using: LinkPreview.interactionForeignKey)
    private static let recipientStates = hasMany(RecipientState.self, using: RecipientState.interactionForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case serverHash
        case threadId
        case authorId
        
        case variant
        case body
        case timestampMs
        case receivedAtTimestampMs
        
        case expiresInSeconds
        case expiresStartedAtMs
        case linkPreviewUrl
        
        // Open Group specific properties
        
        case openGroupServerMessageId
        case openGroupWhisperMods
        case openGroupWhisperTo
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case standardIncoming
        case standardOutgoing
        case standardIncomingDeleted
        
        // Info Message Types (spacing the values out to make it easier to extend)
        case infoClosedGroupCreated = 1000
        case infoClosedGroupUpdated
        case infoClosedGroupCurrentUserLeft
        
        case infoDisappearingMessagesUpdate = 2000
        
        case infoScreenshotNotification = 3000
        case infoMediaSavedNotification
        
        case infoMessageRequestAccepted = 4000
    }
    
    /// The `id` value is auto incremented by the database, if the `Interaction` hasn't been inserted into
    /// the database yet this value will be `nil`
    public var id: Int64? = nil
    
    /// The hash returned by the server when this message was created on the server
    ///
    /// **Note:** This will only be populated for `standardIncoming`/`standardOutgoing` interactions
    /// from either `contact` or `closedGroup` threads
    public let serverHash: String?
    
    /// The id of the thread that this interaction belongs to (used to expose the `thread` variable)
    private let threadId: String
    
    /// The id of the user who sent the message, also used to expose the `profile` variable)
    public let authorId: String
    
    /// The type of interaction
    public let variant: Variant
    
    /// The body of this interaction
    public let body: String?
    
    /// When the interaction was created in milliseconds since epoch
    public let timestampMs: Double
    
    /// When the interaction was received in milliseconds since epoch
    public let receivedAtTimestampMs: Double
    
    /// The number of seconds until this message should expire
    public fileprivate(set) var expiresInSeconds: TimeInterval? = nil
    
    /// The timestamp in milliseconds since 1970 at which this messages expiration timer started counting
    /// down (this is stored in order to allow the `expiresInSeconds` value to be updated before a
    /// message has expired)
    public fileprivate(set) var expiresStartedAtMs: Double? = nil
    
    /// This value is the url for the link preview for this interaction
    ///
    /// **Note:** This is also used for open group invitations
    public let linkPreviewUrl: String?
    
    // Open Group specific properties
    
    /// The `openGroupServerMessageId` value will only be set for messages from SOGS
    public fileprivate(set) var openGroupServerMessageId: Int64? = nil
    
    /// This flag indicates whether this interaction is a whisper to the mods of an Open Group
    public let openGroupWhisperMods: Bool
    
    /// This value is the id of the user within an Open Group who is the target of this whisper interaction
    public let openGroupWhisperTo: String?
    
    // MARK: - Relationships
         
    public var thread: QueryInterfaceRequest<SessionThread> {
        request(for: Interaction.thread)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: Interaction.profile)
    }
    
    public var attachments: QueryInterfaceRequest<Attachment> {
        request(for: Interaction.attachments)
    }

    public var quote: QueryInterfaceRequest<Quote> {
        request(for: Interaction.quote)
    }

    public var linkPreview: QueryInterfaceRequest<LinkPreview> {
        let linkPreviewAlias: TableAlias = TableAlias()
        
        return LinkPreview
            .aliased(linkPreviewAlias)
            .joining(
                required: LinkPreview.interactions
                    .filter(literal: [
                        "(ROUND((\(Interaction.Columns.timestampMs) / 1000 / 100000) - 0.5) * 100000)",
                        "=",
                        "\(linkPreviewAlias[LinkPreview.Columns.timestamp])"
                    ].joined(separator: " "))
                    .limit(1)   // Avoid joining to multiple interactions
            )
            .limit(1)   // Avoid joining to multiple interactions
    }
    
    public var recipientStates: QueryInterfaceRequest<RecipientState> {
        request(for: Interaction.recipientStates)
    }
    
    // MARK: - Initialization
    
    // TODO: Do we actually want these values to have defaults? (check how messages are getting created - convenience constructors??)
    init(
        serverHash: String?,
        threadId: String,
        authorId: String,
        variant: Variant,
        body: String?,
        timestampMs: Double,
        receivedAtTimestampMs: Double,
        expiresInSeconds: TimeInterval?,
        expiresStartedAtMs: Double?,
        linkPreviewUrl: String?,
        openGroupServerMessageId: Int64?,
        openGroupWhisperMods: Bool,
        openGroupWhisperTo: String?
    ) {
        self.serverHash = serverHash
        self.threadId = threadId
        self.authorId = authorId
        self.variant = variant
        self.body = body
        self.timestampMs = timestampMs
        self.receivedAtTimestampMs = receivedAtTimestampMs
        self.expiresInSeconds = expiresInSeconds
        self.expiresStartedAtMs = expiresStartedAtMs
        self.linkPreviewUrl = linkPreviewUrl
        self.openGroupServerMessageId = openGroupServerMessageId
        self.openGroupWhisperMods = openGroupWhisperMods
        self.openGroupWhisperTo = openGroupWhisperTo
    }
    
    // MARK: - Custom Database Interaction
    
    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
    
    public func delete(_ db: Database) throws -> Bool {
        // If we have a LinkPreview then check if this is the only interaction that has it
        // and delete the LinkPreview if so
        if linkPreviewUrl != nil {
            let interactionAlias: TableAlias = TableAlias()
            let numInteractions: Int? = try? Interaction
                .aliased(interactionAlias)
                .joining(
                    required: Interaction.linkPreview
                        .filter(literal: [
                            "(ROUND((\(interactionAlias[Columns.timestampMs]) / 1000 / 100000) - 0.5) * 100000)",
                            "=",
                            "\(LinkPreview.Columns.timestamp)"
                        ].joined(separator: " "))
                )
                .fetchCount(db)
            let tmp = try linkPreview.fetchAll(db)
            
            if numInteractions == 1 {
                try linkPreview.deleteAll(db)
            }
        }
        
        return try performDelete(db)
    }
}

// MARK: - Convenience

public extension Interaction {
    // MARK: - Variables
    
    var isExpiringMessage: Bool {
        guard variant == .standardIncoming || variant == .standardOutgoing else { return false }
        
        return (expiresInSeconds ?? 0 > 0)
    }
    
    var openGroupWhisper: Bool { return (openGroupWhisperMods || (openGroupWhisperTo != nil)) }
    
    // MARK: - Functions
    
    func with(
        expiresInSeconds: TimeInterval? = nil,
        expiresStartedAtMs: Double? = nil,
        openGroupServerMessageId: Int64? = nil
    ) -> Interaction {
        var updatedInteraction: Interaction = self
        updatedInteraction.expiresInSeconds = (expiresInSeconds ?? updatedInteraction.expiresInSeconds)
        updatedInteraction.expiresStartedAtMs = (expiresStartedAtMs ?? updatedInteraction.expiresStartedAtMs)
        updatedInteraction.openGroupServerMessageId = (openGroupServerMessageId ?? updatedInteraction.openGroupServerMessageId)
        return updatedInteraction
    }
}
