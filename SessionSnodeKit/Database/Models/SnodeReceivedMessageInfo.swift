// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

struct SnodeReceivedMessageInfo: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    static var databaseTableName: String { "snodeReceivedMessageInfo" }
    
    public enum Columns: String, CodingKey, ColumnExpression {
        case key
        case hash
        case expirationDateMs
    }
    
    let key: String
    let hash: String
    let expirationDateMs: Int64
}
