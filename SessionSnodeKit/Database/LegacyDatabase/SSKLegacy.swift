// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum SSKLegacy {
    // MARK: - Collections and Keys
    
    internal static let swarmCollectionPrefix = "LokiSwarmCollection-"
    internal static let lastSnodePoolRefreshDateKey = "lastSnodePoolRefreshDate"
    internal static let snodePoolCollection = "LokiSnodePoolCollection"
    internal static let onionRequestPathCollection = "LokiOnionRequestPathCollection"
    internal static let lastSnodePoolRefreshDateCollection = "LokiLastSnodePoolRefreshDateCollection"
    internal static let lastMessageHashCollection = "LokiLastMessageHashCollection"
    internal static let receivedMessagesCollection = "LokiReceivedMessagesCollection"
    
    // MARK: - Types
    
    public typealias LegacyOnionRequestAPIPath = [Snode]
    
    @objc(Snode)
    public final class Snode: NSObject, NSCoding {
        public let address: String
        public let port: UInt16
        public let publicKeySet: KeySet

        // MARK: - Nested Types

        public struct KeySet {
            public let ed25519Key: String
            public let x25519Key: String
        }
        
        // MARK: - NSCoding
        
        public init?(coder: NSCoder) {
            address = coder.decodeObject(forKey: "address") as! String
            port = coder.decodeObject(forKey: "port") as! UInt16

            guard
                let idKey = coder.decodeObject(forKey: "idKey") as? String,
                let encryptionKey = coder.decodeObject(forKey: "encryptionKey") as? String
            else { return nil }
            
            publicKeySet = KeySet(ed25519Key: idKey, x25519Key: encryptionKey)
            
            super.init()
        }

        public func encode(with coder: NSCoder) {
            fatalError("encode(with:) should never be called for legacy types")
        }
        
        // Note: The 'isEqual' and 'hash' overrides are both needed to ensure the migration
        // doesn't try to insert duplicate SNode entries into the new database (which would
        // result in unique key constraint violations)
        override public func isEqual(_ other: Any?) -> Bool {
            guard let other = other as? Snode else { return false }
            
            return address == other.address && port == other.port
        }

        override public var hash: Int {
            return address.hashValue ^ port.hashValue
        }
    }
}
