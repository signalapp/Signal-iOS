// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct GroupMember: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "groupMember" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case groupId
        case profileId
        case role
    }
    
    public enum Role: Int, Codable, DatabaseValueConvertible {
        case standard
        case zombie
        case moderator
        case admin
    }

    public let groupId: String
    public let profileId: String
    public let role: Role
}
