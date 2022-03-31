// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

struct SnodeSet: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    static var databaseTableName: String { "snodeSet" }
    static let nodes = hasMany(Snode.self)
    static let onionRequestPathPrefix = "OnionRequestPath-"
    
    public enum Columns: String, CodingKey, ColumnExpression {
        case key
        case nodeIndex
        case address
        case port
    }
    
    let key: String
    let nodeIndex: UInt
    let address: String
    let port: UInt16
    
    var nodes: QueryInterfaceRequest<Snode> {
        request(for: SnodeSet.nodes)
    }
}
