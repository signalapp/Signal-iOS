// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import YapDatabase
import SessionUtilitiesKit

enum _003_YDBToGRDBMigration: Migration {
    static let target: TargetMigrations.Identifier = .snodeKit
    static let identifier: String = "YDBToGRDBMigration"
    static let needsConfigSync: Bool = false
    
    /// This migration can take a while if it's a very large database or there are lots of closed groups (want this to account
    /// for about 10% of the progress bar so we intentionally have a higher `minExpectedRunDuration` so show more
    /// progress during the migration)
    static let minExpectedRunDuration: TimeInterval = 2.0
    
    static func migrate(_ db: Database) throws {
        guard let dbConnection: YapDatabaseConnection = SUKLegacy.newDatabaseConnection() else {
            SNLog("[Migration Warning] No legacy database, skipping \(target.key(with: self))")
            return
        }
        
        // MARK: - Read from Legacy Database
        
        // Note: Want to exclude the Snode's we already added from the 'onionRequestPathResult'
        var snodeResult: Set<SSKLegacy.Snode> = []
        var snodeSetResult: [String: Set<SSKLegacy.Snode>] = [:]
        var lastSnodePoolRefreshDate: Date? = nil
        var lastMessageResults: [String: (hash: String, json: JSON)] = [:]
        var receivedMessageResults: [String: Set<String>] = [:]
        
        // Map the Legacy types for the NSKeyedUnarchiver
        NSKeyedUnarchiver.setClass(
            SSKLegacy.Snode.self,
            forClassName: "SessionSnodeKit.Snode"
        )
        
        dbConnection.read { transaction in
            // MARK: --lastSnodePoolRefreshDate
            
            lastSnodePoolRefreshDate = transaction.object(
                forKey: SSKLegacy.lastSnodePoolRefreshDateKey,
                inCollection: SSKLegacy.lastSnodePoolRefreshDateCollection
            ) as? Date
            
            // MARK: --OnionRequestPaths
            
            if
                let path0Snode0 = transaction.object(forKey: "0-0", inCollection: SSKLegacy.onionRequestPathCollection) as? SSKLegacy.Snode,
                let path0Snode1 = transaction.object(forKey: "0-1", inCollection: SSKLegacy.onionRequestPathCollection) as? SSKLegacy.Snode,
                let path0Snode2 = transaction.object(forKey: "0-2", inCollection: SSKLegacy.onionRequestPathCollection) as? SSKLegacy.Snode
            {
                snodeResult.insert(path0Snode0)
                snodeResult.insert(path0Snode1)
                snodeResult.insert(path0Snode2)
                snodeSetResult["\(SnodeSet.onionRequestPathPrefix)0"] = [ path0Snode0, path0Snode1, path0Snode2 ]
                
                if
                    let path1Snode0 = transaction.object(forKey: "1-0", inCollection: SSKLegacy.onionRequestPathCollection) as? SSKLegacy.Snode,
                    let path1Snode1 = transaction.object(forKey: "1-1", inCollection: SSKLegacy.onionRequestPathCollection) as? SSKLegacy.Snode,
                    let path1Snode2 = transaction.object(forKey: "1-2", inCollection: SSKLegacy.onionRequestPathCollection) as? SSKLegacy.Snode
                {
                    snodeResult.insert(path1Snode0)
                    snodeResult.insert(path1Snode1)
                    snodeResult.insert(path1Snode2)
                    snodeSetResult["\(SnodeSet.onionRequestPathPrefix)1"] = [ path1Snode0, path1Snode1, path1Snode2 ]
                }
            }
            Storage.update(progress: 0.02, for: self, in: target)
            
            // MARK: --SnodePool
            
            transaction.enumerateKeysAndObjects(inCollection: SSKLegacy.snodePoolCollection) { _, object, _ in
                guard let snode = object as? SSKLegacy.Snode else { return }
                snodeResult.insert(snode)
            }
            
            // MARK: --Swarms
            
            /// **Note:** There is no index on the collection column so unfortunately it takes the same amount of time to enumerate through all
            /// collections as it does to just get the count of collections, due to this, if the database is very large, importing thecollections can be
            /// very slow (~15s with 2,000,000 rows) - we want to show some kind of progress while enumerating so the below code creates a
            /// very rought guess of the number of collections based on the file size of the database (this shouldn't affect most users at all)
            let roughMbPerCollection: CGFloat = 2.5
            let oldDatabaseSizeBytes: CGFloat = (try? FileManager.default
                .attributesOfItem(atPath: SUKLegacy.legacyDatabaseFilepath)[.size]
                .asType(CGFloat.self))
                .defaulting(to: 0)
            let roughNumCollections: CGFloat = (((oldDatabaseSizeBytes / 1024) / 1024) / roughMbPerCollection)
            let startProgress: CGFloat = 0.02
            let swarmCompleteProgress: CGFloat = 0.90
            var swarmCollections: Set<String> = []
            var collectionIndex: CGFloat = 0
            
            transaction.enumerateCollections { collectionName, _ in
                if collectionName.starts(with: SSKLegacy.swarmCollectionPrefix) {
                    swarmCollections.insert(collectionName.substring(from: SSKLegacy.swarmCollectionPrefix.count))
                }
                
                collectionIndex += 1
                
                Storage.update(
                    progress: min(
                        swarmCompleteProgress,
                        ((collectionIndex / roughNumCollections) * (swarmCompleteProgress - startProgress))
                    ),
                    for: self,
                    in: target
                )
            }
            Storage.update(progress: swarmCompleteProgress, for: self, in: target)
            
            for swarmCollection in swarmCollections {
                let collection: String = "\(SSKLegacy.swarmCollectionPrefix)\(swarmCollection)"
                
                transaction.enumerateKeysAndObjects(inCollection: collection) { _, object, _ in
                    guard let snode = object as? SSKLegacy.Snode else { return }
                    snodeResult.insert(snode)
                    snodeSetResult[swarmCollection] = (snodeSetResult[swarmCollection] ?? Set()).inserting(snode)
                }
            }
            Storage.update(progress: 0.92, for: self, in: target)
            
            // MARK: --Received message hashes
            
            transaction.enumerateKeysAndObjects(inCollection: SSKLegacy.receivedMessagesCollection) { key, object, _ in
                guard let hashSet = object as? Set<String> else { return }
                receivedMessageResults[key] = hashSet
            }
            Storage.update(progress: 0.93, for: self, in: target)
            
            // MARK: --Last message info
            
            transaction.enumerateKeysAndObjects(inCollection: SSKLegacy.lastMessageHashCollection) { key, object, _ in
                guard let lastMessageJson = object as? JSON else { return }
                guard let lastMessageHash: String = lastMessageJson["hash"] as? String else { return }
                
                // Note: We remove the value from 'receivedMessageResults' as we want to try and use
                // it's actual 'expirationDate' value
                lastMessageResults[key] = (lastMessageHash, lastMessageJson)
                receivedMessageResults[key] = receivedMessageResults[key]?.removing(lastMessageHash)
            }
            Storage.update(progress: 0.94, for: self, in: target)
        }
        
        // MARK: - Insert into GRDB
        
        try autoreleasepool {
            // MARK: --lastSnodePoolRefreshDate
            
            db[.lastSnodePoolRefreshDate] = lastSnodePoolRefreshDate
            
            // MARK: --SnodePool
            
            try snodeResult.forEach { legacySnode in
                try Snode(
                    address: legacySnode.address,
                    port: legacySnode.port,
                    ed25519PublicKey: legacySnode.publicKeySet.ed25519Key,
                    x25519PublicKey: legacySnode.publicKeySet.x25519Key
                ).migrationSafeInsert(db)
            }
            Storage.update(progress: 0.96, for: self, in: target)
            
            // MARK: --SnodeSets
            
            try snodeSetResult.forEach { key, legacySnodeSet in
                try legacySnodeSet.enumerated().forEach { nodeIndex, legacySnode in
                    // Note: In this case the 'nodeIndex' is irrelivant
                    try SnodeSet(
                        key: key,
                        nodeIndex: nodeIndex,
                        address: legacySnode.address,
                        port: legacySnode.port
                    ).migrationSafeInsert(db)
                }
            }
            Storage.update(progress: 0.98, for: self, in: target)
        }
        
        try autoreleasepool {
            // MARK: --Received Messages
            
            try receivedMessageResults.forEach { key, hashes in
                try hashes.forEach { hash in
                    _ = try SnodeReceivedMessageInfo(
                        key: key,
                        hash: hash,
                        expirationDateMs: SnodeReceivedMessage.defaultExpirationSeconds
                    ).migrationSafeInserted(db)
                }
            }
            Storage.update(progress: 0.99, for: self, in: target)
            
            // MARK: --Last Message Hash
            
            try lastMessageResults.forEach { key, data in
                let expirationDateMs: Int64 = ((data.json["expirationDate"] as? Int64) ?? 0)
                
                _ = try SnodeReceivedMessageInfo(
                    key: key,
                    hash: data.hash,
                    expirationDateMs: (expirationDateMs > 0 ?
                        expirationDateMs :
                        SnodeReceivedMessage.defaultExpirationSeconds
                    )
                ).migrationSafeInserted(db)
            }
        }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
