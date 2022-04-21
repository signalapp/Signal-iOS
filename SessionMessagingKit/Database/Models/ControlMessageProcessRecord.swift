// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct ControlMessageProcessRecord: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "controlMessageProcessRecord" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case threadId
        case sentTimestampMs
        case serverHash
        case openGroupMessageServerId
    }
    
    public let threadId: String
    public let sentTimestampMs: Int64
    public let serverHash: String
    public let openGroupMessageServerId: Int64
    
}
