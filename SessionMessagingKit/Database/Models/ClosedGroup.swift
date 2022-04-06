// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct ClosedGroup: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "closedGroup" }
    static let keyPairs = hasMany(ClosedGroupKeyPair.self)
    static let members = hasMany(GroupMember.self)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case publicKey
        case name
        case formationTimestamp
    }
    
    public var id: String { publicKey }

    public let publicKey: String
    public let name: String
    public let formationTimestamp: TimeInterval
    
    public var keyPairs: QueryInterfaceRequest<ClosedGroupKeyPair> {
        request(for: ClosedGroup.keyPairs)
    }
    
    public var memberIds: QueryInterfaceRequest<GroupMember> {
        request(for: ClosedGroup.members)
            .filter(GroupMember.Columns.role == GroupMember.Role.standard)
    }
    
    public var zombieIds: QueryInterfaceRequest<GroupMember> {
        request(for: ClosedGroup.members)
            .filter(GroupMember.Columns.role == GroupMember.Role.zombie)
    }
    
    public var moderatorIds: QueryInterfaceRequest<GroupMember> {
        request(for: ClosedGroup.members)
            .filter(GroupMember.Columns.role == GroupMember.Role.moderator)
    }
    
    public var adminIds: QueryInterfaceRequest<GroupMember> {
        request(for: ClosedGroup.members)
            .filter(GroupMember.Columns.role == GroupMember.Role.admin)
    }
}
