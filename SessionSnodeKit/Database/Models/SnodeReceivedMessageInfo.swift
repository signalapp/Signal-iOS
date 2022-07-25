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
    /// **Note:** If no value exists this will default to 15 days from now (since the service node caches messages for
    /// 14 days)
    public let expirationDateMs: Int64
    
    // MARK: - Custom Database Interaction
    
    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}

// MARK: - Convenience

public extension SnodeReceivedMessageInfo {
    private static func key(for snode: Snode, publicKey: String, namespace: Int) -> String {
        guard namespace != SnodeAPI.defaultNamespace else {
            return "\(snode.address):\(snode.port).\(publicKey)"
        }
        
        return "\(snode.address):\(snode.port).\(publicKey).\(namespace)"
    }
    
    init(
        snode: Snode,
        publicKey: String,
        namespace: Int,
        hash: String,
        expirationDateMs: Int64?
    ) {
        self.key = SnodeReceivedMessageInfo.key(for: snode, publicKey: publicKey, namespace: namespace)
        self.hash = hash
        self.expirationDateMs = (expirationDateMs ?? 0)
    }
}

// MARK: - GRDB Interactions

public extension SnodeReceivedMessageInfo {
    static func pruneExpiredMessageHashInfo(for snode: Snode, namespace: Int, associatedWith publicKey: String) {
        // Delete any expired SnodeReceivedMessageInfo values associated to a specific node
        Storage.shared.write { db in
            // Only prune the hashes if new hashes exist for this Snode (if they don't then we don't want
            // to clear out the legacy hashes)
            let hasNonLegacyHash: Bool = try SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.key == key(for: snode, publicKey: publicKey, namespace: namespace))
                .isNotEmpty(db)
            
            guard hasNonLegacyHash else { return }
            
            try SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.key == key(for: snode, publicKey: publicKey, namespace: namespace))
                .filter(SnodeReceivedMessageInfo.Columns.expirationDateMs <= (Date().timeIntervalSince1970 * 1000))
                .deleteAll(db)
        }
    }
    
    /// This method fetches the last non-expired hash from the database for message retrieval
    ///
    /// **Note:** This method uses a `write` instead of a read because there is a single write queue for the database and it's very common for
    /// this method to be called after the hash value has been updated but before the various `read` threads have been updated, resulting in a
    /// pointless fetch for data the app has already received
    static func fetchLastNotExpired(for snode: Snode, namespace: Int, associatedWith publicKey: String) -> SnodeReceivedMessageInfo? {
        return Storage.shared.read { db in
            let nonLegacyHash: SnodeReceivedMessageInfo? = try SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.key == key(for: snode, publicKey: publicKey, namespace: namespace))
                .filter(SnodeReceivedMessageInfo.Columns.expirationDateMs > (Date().timeIntervalSince1970 * 1000))
                .order(SnodeReceivedMessageInfo.Columns.id.desc)
                .fetchOne(db)
            
            // If we have a non-legacy hash then return it immediately (legacy hashes had a different
            // 'key' structure)
            if nonLegacyHash != nil { return nonLegacyHash }
            
            return try SnodeReceivedMessageInfo
                .filter(SnodeReceivedMessageInfo.Columns.key == publicKey)
                .order(SnodeReceivedMessageInfo.Columns.id.desc)
                .fetchOne(db)
        }
    }
}
