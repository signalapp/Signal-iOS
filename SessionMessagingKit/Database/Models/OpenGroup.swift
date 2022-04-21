// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct OpenGroup: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "openGroup" }
    internal static let threadForeignKey = ForeignKey([Columns.threadId], to: [SessionThread.Columns.id])
    private static let thread = belongsTo(SessionThread.self, using: threadForeignKey)
    private static let capabilities = hasMany(Capability.self, using: Capability.openGroupForeignKey)
    private static let members = hasMany(GroupMember.self, using: GroupMember.openGroupForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case threadId
        case server
        case room
        case publicKey
        case name
        case groupDescription = "description"
        case imageId
        case imageData
        case userCount
        case infoUpdates
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
    public let room: String
    
    /// The public key for the group
    public let publicKey: String
    
    /// The name for the group
    public let name: String
    
    /// The description for the group
    public let groupDescription: String?
    
    /// The ID with which the image can be retrieved from the server
    public let imageId: Int?
    
    /// The image for the group
    public let imageData: Data?
    
    /// The number of users in the group
    public let userCount: Int
    
    /// Monotonic room information counter that increases each time the room's metadata changes
    public let infoUpdates: Int
    
    // MARK: - Relationships
    
    public var thread: QueryInterfaceRequest<SessionThread> {
        request(for: OpenGroup.thread)
    }
    
    public var capabilities: QueryInterfaceRequest<Capability> {
        request(for: OpenGroup.capabilities)
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
    
    init(
        server: String,
        room: String,
        publicKey: String,
        name: String,
        groupDescription: String?,
        imageId: Int?,
        imageData: Data?,
        userCount: Int,
        infoUpdates: Int
    ) {
        // Always force the server to lowercase
        self.threadId = OpenGroup.idFor(room: room, server: server)
        self.server = server.lowercased()
        self.room = room
        self.publicKey = publicKey
        self.name = name
        self.groupDescription = groupDescription
        self.imageId = imageId
        self.imageData = imageData
        self.userCount = userCount
        self.infoUpdates = infoUpdates
    }
    
    // MARK: - Custom Database Interaction
    
    public func delete(_ db: Database) throws -> Bool {
        // Delete all 'GroupMember' records associated with this OpenGroup (can't
        // have a proper ForeignKey constraint as 'GroupMember' is reused for the
        // 'ClosedGroup' table as well)
        try request(for: OpenGroup.members).deleteAll(db)
        return try performDelete(db)
    }
}

// MARK: - Convenience

public extension OpenGroup {
    static func idFor(room: String, server: String) -> String {
        return "\(server.lowercased()).\(room)"
    }
}
