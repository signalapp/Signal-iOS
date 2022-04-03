// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct SnodeSet: Codable, FetchableRecord, EncodableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static let onionRequestPathPrefix = "OnionRequestPath-"
    public static var databaseTableName: String { "snodeSet" }
    static let node = hasOne(Snode.self, using: Snode.snodeSetForeignKey)
        
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case key
        case nodeIndex
        case address
        case port
    }
    
    public let key: String
    public let nodeIndex: Int
    public let address: String
    public let port: UInt16
    
    public var node: QueryInterfaceRequest<Snode> {
        request(for: SnodeSet.node)
    }
}
