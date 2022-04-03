// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct SnodeReceivedMessageInfo: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "snodeReceivedMessageInfo" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case key
        case hash
        case expirationDateMs
    }
    
    public let key: String
    public let hash: String
    public let expirationDateMs: Int64
}

// MARK: - Convenience

public extension SnodeReceivedMessageInfo {
    private static func key(for snode: Snode, publicKey: String) -> String {
        return "\(snode.address):\(snode.port).\(publicKey)"
    }
    
    init(
        snode: Snode,
        publicKey: String,
        hash: String,
        expirationDateMs: Int64?
    ) {
        self.key = SnodeReceivedMessageInfo.key(for: snode, publicKey: publicKey)
        self.hash = hash
        self.expirationDateMs = (expirationDateMs ?? 0)
    }
}

// MARK: - GRDB Interactions

public extension SnodeReceivedMessageInfo {
    static func pruneLastMessageHashInfoIfExpired(for snode: Snode, associatedWith publicKey: String) {
        // Clear out the 'expirationDateMs' value for all expired (but non-0) message infos
        GRDBStorage.shared.write { db in
            try? SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.key == key(for: snode, publicKey: publicKey))
                .filter(SnodeReceivedMessageInfo.Columns.expirationDateMs > 0)
                .updateAll(db, SnodeReceivedMessageInfo.Columns.expirationDateMs.set(to: 0))
        }
    }
    
    static func fetchLastNotExpired(for snode: Snode, associatedWith publicKey: String) -> SnodeReceivedMessageInfo? {
        return GRDBStorage.shared.read { db in
            try? SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.key == key(for: snode, publicKey: publicKey))
                .order(SnodeReceivedMessageInfo.Columns.expirationDateMs)
                .reversed()
                .fetchOne(db)
        }
    }
}
