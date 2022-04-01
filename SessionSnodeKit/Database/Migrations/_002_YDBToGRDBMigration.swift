// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _002_YDBToGRDBMigration: Migration {
    static let identifier: String = "YDBToGRDBMigration"
    
    // TODO: Autorelease pool???
    static func migrate(_ db: Database) throws {
        // MARK: - OnionRequestPath, Snode Pool & Swarm
        
        // Note: Want to exclude the Snode's we already added from the 'onionRequestPathResult'
        var snodeResult: Set<Legacy.Snode> = []
        var snodeSetResult: [String: Set<Legacy.Snode>] = [:]
        var lastSnodePoolRefreshDate: Date? = nil
        
        Storage.read { transaction in
            // Process the lastSnodePoolRefreshDate
            lastSnodePoolRefreshDate = transaction.object(
                forKey: Legacy.lastSnodePoolRefreshDateKey,
                inCollection: Legacy.lastSnodePoolRefreshDateCollection
            ) as? Date
            
            // Process the OnionRequestPaths
            if
                let path0Snode0 = transaction.object(forKey: "0-0", inCollection: Legacy.onionRequestPathCollection) as? Legacy.Snode,
                let path0Snode1 = transaction.object(forKey: "0-1", inCollection: Legacy.onionRequestPathCollection) as? Legacy.Snode,
                let path0Snode2 = transaction.object(forKey: "0-2", inCollection: Legacy.onionRequestPathCollection) as? Legacy.Snode
            {
                snodeResult.insert(path0Snode0)
                snodeResult.insert(path0Snode1)
                snodeResult.insert(path0Snode2)
                snodeSetResult["\(SnodeSet.onionRequestPathPrefix)0"] = [ path0Snode0, path0Snode1, path0Snode2 ]
                
                if
                    let path1Snode0 = transaction.object(forKey: "1-0", inCollection: Legacy.onionRequestPathCollection) as? Legacy.Snode,
                    let path1Snode1 = transaction.object(forKey: "1-1", inCollection: Legacy.onionRequestPathCollection) as? Legacy.Snode,
                    let path1Snode2 = transaction.object(forKey: "1-2", inCollection: Legacy.onionRequestPathCollection) as? Legacy.Snode
                {
                    snodeResult.insert(path1Snode0)
                    snodeResult.insert(path1Snode1)
                    snodeResult.insert(path1Snode2)
                    snodeSetResult["\(SnodeSet.onionRequestPathPrefix)1"] = [ path1Snode0, path1Snode1, path1Snode2 ]
                }
            }
            
            // Process the SnodePool
            transaction.enumerateKeysAndObjects(inCollection: Legacy.snodePoolCollection) { _, object, _ in
                guard let snode = object as? Legacy.Snode else { return }
                snodeResult.insert(snode)
            }
            
            // Process the Swarms
            var swarmCollections: Set<String> = []
            
            transaction.enumerateCollections { collectionName, _ in
                if collectionName.starts(with: Legacy.swarmCollectionPrefix) {
                    swarmCollections.insert(collectionName.substring(from: Legacy.swarmCollectionPrefix.count))
                }
            }
            
            for swarmCollection in swarmCollections {
                let collection: String = "\(Legacy.swarmCollectionPrefix)\(swarmCollection)"
                
                transaction.enumerateKeysAndObjects(inCollection: collection) { _, object, _ in
                    guard let snode = object as? Legacy.Snode else { return }
                    snodeResult.insert(snode)
                    snodeSetResult[swarmCollection] = (snodeSetResult[swarmCollection] ?? Set()).inserting(snode)
                }
            }
        }
        
        // Insert the data into GRDB
        
        db[.lastSnodePoolRefreshDate] = lastSnodePoolRefreshDate
        
        try snodeResult.forEach { legacySnode in
            try Snode(
                address: legacySnode.address,
                port: legacySnode.port,
                ed25519PublicKey: legacySnode.publicKeySet.ed25519Key,
                x25519PublicKey: legacySnode.publicKeySet.x25519Key
            ).insert(db)
        }
        
        try snodeSetResult.forEach { key, legacySnodeSet in
            try legacySnodeSet.enumerated().forEach { nodeIndex, legacySnode in
                // Note: In this case the 'nodeIndex' is irrelivant
                try SnodeSet(
                    key: key,
                    nodeIndex: nodeIndex,
                    address: legacySnode.address,
                    port: legacySnode.port
                ).insert(db)
            }
        }
        
        // MARK: - Received Messages & Last Message Hash
        
        var lastMessageResults: [String: (hash: String, json: JSON)] = [:]
        var receivedMessageResults: [String: Set<String>] = [:]

        Storage.read { transaction in
            // Extract the received message hashes
            transaction.enumerateKeysAndObjects(inCollection: Legacy.receivedMessagesCollection) { key, object, _ in
                guard let hashSet = object as? Set<String> else { return }
                receivedMessageResults[key] = hashSet
            }
            
            // Retrieve the last message info
            transaction.enumerateKeysAndObjects(inCollection: Legacy.lastMessageHashCollection) { key, object, _ in
                guard let lastMessageJson = object as? JSON else { return }
                guard let lastMessageHash: String = lastMessageJson["hash"] as? String else { return }
                
                // Note: We remove the value from 'receivedMessageResults' as we don't want to default it's
                // expiration value to 0
                lastMessageResults[key] = (lastMessageHash, lastMessageJson)
                receivedMessageResults[key] = receivedMessageResults[key]?.removing(lastMessageHash)
            }
        }

        try receivedMessageResults.forEach { key, hashes in
            try hashes.forEach { hash in
                try SnodeReceivedMessageInfo(
                    key: key,
                    hash: hash,
                    expirationDateMs: 0
                ).insert(db)
            }
        }
        
        try lastMessageResults.forEach { key, data in
            try SnodeReceivedMessageInfo(
                key: key,
                hash: data.hash,
                expirationDateMs: ((data.json["expirationDate"] as? Int64) ?? 0)
            ).insert(db)
        }
    }
}
