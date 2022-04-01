// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct SnodeSet: Codable, FetchableRecord, EncodableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static let onionRequestPathPrefix = "OnionRequestPath-"
    public static var databaseTableName: String { "snodeSetAssociation" }
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

// MARK: - Convenience

internal extension SnodeSet {
    static func fetchAllOnionRequestPaths(_ db: Database) throws -> [[Snode]] {
        struct ResultWrapper: Decodable, FetchableRecord {
            let key: String
            let nodeIndex: Int
            let address: String
            let port: UInt16
            let snode: Snode
        }
        
        return try SnodeSet
            .filter(SnodeSet.Columns.key.like("\(SnodeSet.onionRequestPathPrefix)%"))
            .order(SnodeSet.Columns.nodeIndex)
            .order(SnodeSet.Columns.key)
            .including(required: SnodeSet.node)
            .asRequest(of: ResultWrapper.self)
            .fetchAll(db)
            .reduce(into: [:]) { prev, next in  // Reducing will lose the 'key' sorting
                prev[next.key] = (prev[next.key] ?? []).appending(next.snode)
            }
            .asArray()
            .sorted(by: { lhs, rhs in lhs.key < rhs.key })
            .compactMap { _, nodes in !nodes.isEmpty ? nodes : nil }  // Exclude empty sets
    }
    
    static func clearOnionRequestPaths(_ db: Database) throws {
        try SnodeSet
            .filter(SnodeSet.Columns.key.like("\(SnodeSet.onionRequestPathPrefix)%"))
            .deleteAll(db)
    }
}
