// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct OpenGroup: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "openGroup" }
    static let capabilities = hasMany(Capability.self)
    static let members = hasMany(GroupMember.self)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
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
    
    public var id: String { "\(server).\(room)" }

    public let server: String
    public let room: String
    public let publicKey: String
    public let name: String
    public let groupDescription: String?
    public let imageId: Int?
    public let imageData: Data?
    public let userCount: Int
    public let infoUpdates: Int
    
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
}
