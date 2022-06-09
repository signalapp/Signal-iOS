// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct OpenGroup: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "openGroup" }
    internal static let threadForeignKey = ForeignKey([Columns.threadId], to: [SessionThread.Columns.id])
    private static let thread = belongsTo(SessionThread.self, using: threadForeignKey)
    private static let members = hasMany(GroupMember.self, using: GroupMember.openGroupForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case threadId
        case server
        case roomToken
        case publicKey
        case name
        case isActive
        case roomDescription = "description"
        case imageId
        case imageData
        case userCount
        case infoUpdates
        case sequenceNumber
        case inboxLatestMessageId
        case outboxLatestMessageId
    }
    
    public var id: String { threadId }  // Identifiable
    
    /// The id for the thread this open group belongs to
    ///
    /// **Note:** This value will always be `\(server).\(room)` (This needs it’s own column to
    /// allow for db joining to the Thread table)
    public let threadId: String
    
    /// The server for the group
    public let server: String
    
    /// The specific room on the server for the group
    ///
    /// **Note:** In order to support the default open group query we need an OpenGroup entry in
    /// the database, for this entry the `roomToken` value will be an empty string so we can ignore
    /// it when polling
    public let roomToken: String
    
    /// The public key for the group
    public let publicKey: String
    
    /// Flag indicating whether this is an OpenGroup the user has actively joined (we store inactive
    /// open groups so we can display them in the UI but they won't be polled for)
    public let isActive: Bool
    
    /// The name for the group
    public let name: String
    
    /// The description for the room
    public let roomDescription: String?
    
    /// The ID with which the image can be retrieved from the server
    public let imageId: String?
    
    /// The image for the group
    public let imageData: Data?
    
    /// The number of users in the group
    public let userCount: Int64
    
    /// Monotonic room information counter that increases each time the room's metadata changes
    public let infoUpdates: Int64
    
    /// Sequence number for the most recently received message from the open group
    public let sequenceNumber: Int64
    
    /// The id of the most recently received inbox message
    ///
    /// **Note:** This value is unique per server rather than per room (ie. all rooms in the same server will be
    /// updated whenever this value changes)
    public let inboxLatestMessageId: Int64
    
    /// The id of the most recently received outbox message
    ///
    /// **Note:** This value is unique per server rather than per room (ie. all rooms in the same server will be
    /// updated whenever this value changes)
    public let outboxLatestMessageId: Int64
    
    // MARK: - Relationships
    
    public var thread: QueryInterfaceRequest<SessionThread> {
        request(for: OpenGroup.thread)
    }

    public var moderatorIds: QueryInterfaceRequest<GroupMember> {
        request(for: OpenGroup.members)
            .filter(GroupMember.Columns.role == GroupMember.Role.moderator)
    }
    
    public var adminIds: QueryInterfaceRequest<GroupMember> {
        request(for: OpenGroup.members)
            .filter(GroupMember.Columns.role == GroupMember.Role.admin)
    }
    
    // MARK: - Initialization
    
    public init(
        server: String,
        roomToken: String,
        publicKey: String,
        isActive: Bool,
        name: String,
        roomDescription: String? = nil,
        imageId: String? = nil,
        imageData: Data? = nil,
        userCount: Int64,
        infoUpdates: Int64,
        sequenceNumber: Int64 = 0,
        inboxLatestMessageId: Int64 = 0,
        outboxLatestMessageId: Int64 = 0
    ) {
        self.threadId = OpenGroup.idFor(roomToken: roomToken, server: server)
        self.server = server.lowercased()
        self.roomToken = roomToken
        self.publicKey = publicKey
        self.isActive = isActive
        self.name = name
        self.roomDescription = roomDescription
        self.imageId = imageId
        self.imageData = imageData
        self.userCount = userCount
        self.infoUpdates = infoUpdates
        self.sequenceNumber = sequenceNumber
        self.inboxLatestMessageId = inboxLatestMessageId
        self.outboxLatestMessageId = outboxLatestMessageId
    }
}

// MARK: - Mutation

public extension OpenGroup {
    func with(
        isActive: Bool? = nil,
        name: String? = nil,
        roomDescription: String? = nil,
        imageId: String? = nil,
        imageData: Data? = nil,
        userCount: Int64? = nil,
        infoUpdates: Int64? = nil,
        sequenceNumber: Int64? = nil
    ) -> OpenGroup {
        return OpenGroup(
            server: self.server,
            roomToken: self.roomToken,
            publicKey: self.publicKey,
            isActive: (isActive ?? self.isActive),
            name: (name ?? self.name),
            roomDescription: (roomDescription ?? self.roomDescription),
            imageId: (imageId ?? self.imageId),
            imageData: (imageData ?? self.imageData),
            userCount: (userCount ?? self.userCount),
            infoUpdates: (infoUpdates ?? self.infoUpdates),
            sequenceNumber: (sequenceNumber ?? self.sequenceNumber),
            inboxLatestMessageId: self.inboxLatestMessageId,
            outboxLatestMessageId: self.outboxLatestMessageId
        )
    }
}

// MARK: - Convenience

public extension OpenGroup {
    static func idFor(roomToken: String, server: String) -> String {
        // Always force the server to lowercase
        return "\(server.lowercased()).\(roomToken)"
    }
}

// MARK: - Objective-C Support

// TODO: Remove this when possible

@objc(SMKOpenGroup)
public class SMKOpenGroup: NSObject {
    @objc(inviteUsers:toOpenGroupFor:)
    public static func invite(selectedUsers: Set<String>, openGroupThreadId: String) {
        GRDBStorage.shared.write { db in
            guard let openGroup: OpenGroup = try OpenGroup.fetchOne(db, id: openGroupThreadId) else { return }
            
            let urlString: String = "\(openGroup.server)/\(openGroup.roomToken)?public_key=\(openGroup.publicKey)"
            
            try selectedUsers.forEach { userId in
                let thread: SessionThread = try SessionThread.fetchOrCreate(db, id: userId, variant: .contact)
                
                try LinkPreview(
                    url: urlString,
                    variant: .openGroupInvitation,
                    title: openGroup.name
                )
                .save(db)
                
                let interaction: Interaction = try Interaction(
                    threadId: thread.id,
                    authorId: userId,
                    variant: .standardOutgoing,
                    timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000)),
                    linkPreviewUrl: urlString
                )
                .saved(db)
                
                try MessageSender.send(
                    db,
                    interaction: interaction,
                    in: thread
                )
            }
        }
    }
}
