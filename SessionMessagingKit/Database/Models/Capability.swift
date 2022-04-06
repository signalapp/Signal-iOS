// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Capability: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "capability" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case server
        case room
        case capability
        case isMissing
    }
    
    public let server: String
    public let room: String
    public let capability: String
    public let isMissing: Bool
}
