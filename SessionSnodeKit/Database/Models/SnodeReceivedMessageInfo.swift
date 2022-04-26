// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct SnodeReceivedMessageInfo: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "snodeReceivedMessageInfo" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case key
        case hash
        case expirationDateMs
    }
    
    /// The `id` value is auto incremented by the database, if the `Job` hasn't been inserted into
    /// the database yet this value will be `nil`
    public var id: Int64? = nil
    
    /// The key this message hash is associated to
    ///
    /// This will be a combination of {address}.{port}.{publicKey} for new rows and just the {publicKey} for legacy rows
    public let key: String
    
    /// The is the hash for the received message
    public let hash: String
    
    /// This is the timestamp (in milliseconds since epoch) when the message hash should expire
    ///
    /// **Note:** A value of `0` means this hash should not expire
    public let expirationDateMs: Int64
    
    // MARK: - Custom Database Interaction
    
    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
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
    
    /// This method fetches the last non-expired hash from the database for message retrieval
    ///
    /// **Note:** This method uses a `write` instead of a read because there is a single write queue for the database and it's very common for
    /// this method to be called after the hash value has been updated but before the various `read` threads have been updated, resulting in a
    /// pointless fetch for data the app has already received
    static func fetchLastNotExpired(for snode: Snode, associatedWith publicKey: String) -> SnodeReceivedMessageInfo? {
        return GRDBStorage.shared.write { db in
            try SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.key == key(for: snode, publicKey: publicKey))
                .filter(SnodeReceivedMessageInfo.Columns.expirationDateMs <= (Date().timeIntervalSince1970 * 1000))
                .order(SnodeReceivedMessageInfo.Columns.id.desc)
                .fetchOne(db)
        }
    }
}
