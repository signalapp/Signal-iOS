// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Snode: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible, Hashable, CustomStringConvertible {
    public static var databaseTableName: String { "snode" }
    static let snodeSet = hasMany(SnodeSet.self)
    static let snodeSetForeignKey = ForeignKey(
        [Columns.address, Columns.port],
        to: [SnodeSet.Columns.address, SnodeSet.Columns.port]
    )
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case address = "public_ip"
        case port = "storage_port"
        case ed25519PublicKey = "pubkey_ed25519"
        case x25519PublicKey = "pubkey_x25519"
    }

    public let address: String
    public let port: UInt16
    public let ed25519PublicKey: String
    public let x25519PublicKey: String
    
    public var ip: String {
        guard let range = address.range(of: "https://"), range.lowerBound == address.startIndex else {
            return address
        }
        
        return String(address[range.upperBound..<address.endIndex])
    }
    
    public var snodeSet: QueryInterfaceRequest<SnodeSet> {
        request(for: Snode.snodeSet)
    }
    
    public var description: String { return "\(address):\(port)" }
}

// MARK: - Decoder

extension Snode {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        do {
            let address: String = try container.decode(String.self, forKey: .address)
            
            guard address != "0.0.0.0" else { throw SnodeAPI.Error.invalidIP }
            
            self = Snode(
                address: (address.starts(with: "https://") ? address : "https://\(address)"),
                port: try container.decode(UInt16.self, forKey: .port),
                ed25519PublicKey: try container.decode(String.self, forKey: .ed25519PublicKey),
                x25519PublicKey: try container.decode(String.self, forKey: .x25519PublicKey)
            )
        }
        catch {
            SNLog("Failed to parse snode: \(error.localizedDescription).")
            throw HTTP.Error.invalidJSON
        }
    }
}

// MARK: - Convenience

internal extension Snode {
    static func fetchSet(_ db: Database, publicKey: String) throws -> Set<Snode> {
        return try Snode
            .joining(
                required: Snode.snodeSet
                    .filter(SnodeSet.Columns.key == publicKey)
                    .order(SnodeSet.Columns.nodeIndex)
            )
            .fetchSet(db)
    }
}

internal extension Collection where Element == Snode {
    func save(_ db: Database, key: String) throws {
        try self.enumerated().forEach { nodeIndex, node in
            try node.save(db)
            
            try SnodeSet(
                key: key,
                nodeIndex: nodeIndex,
                address: node.address,
                port: node.port
            ).save(db)
        }
    }
}

internal extension Collection where Element == [Snode] {
    func save(_ db: Database) throws {
        try self.enumerated().forEach { pathIndex, path in
            try path.save(db, key: "\(SnodeSet.onionRequestPathPrefix)\(pathIndex)")
        }
    }
}
