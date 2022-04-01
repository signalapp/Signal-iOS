// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum Legacy {
    // MARK: - Collections and Keys
    
    internal static let swarmCollectionPrefix = "LokiSwarmCollection-"
    internal static let lastSnodePoolRefreshDateKey = "lastSnodePoolRefreshDate"
    internal static let snodePoolCollection = "LokiSnodePoolCollection"
    internal static let onionRequestPathCollection = "LokiOnionRequestPathCollection"
    internal static let lastSnodePoolRefreshDateCollection = "LokiLastSnodePoolRefreshDateCollection"
    internal static let lastMessageHashCollection = "LokiLastMessageHashCollection" // TODO: Remove this one? (make it a query??)
    internal static let receivedMessagesCollection = "LokiReceivedMessagesCollection"
    
    // MARK: - Types
    
    public typealias LegacyOnionRequestAPIPath = [Snode]
    
    @objc(Snode)
    public final class Snode: NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        public let address: String
        public let port: UInt16
        public let publicKeySet: KeySet

        public var ip: String {
            guard let range = address.range(of: "https://"), range.lowerBound == address.startIndex else { return address }
            return String(address[range.upperBound..<address.endIndex])
        }

        // MARK: Nested Types

        public struct KeySet {
            public let ed25519Key: String
            public let x25519Key: String
        }

        // MARK: Initialization
        internal init(address: String, port: UInt16, publicKeySet: KeySet) {
            self.address = address
            self.port = port
            self.publicKeySet = publicKeySet
        }

        // MARK: Coding
        public init?(coder: NSCoder) {
            address = coder.decodeObject(forKey: "address") as! String
            port = coder.decodeObject(forKey: "port") as! UInt16
            guard let idKey = coder.decodeObject(forKey: "idKey") as? String,
                let encryptionKey = coder.decodeObject(forKey: "encryptionKey") as? String else { return nil }
            publicKeySet = KeySet(ed25519Key: idKey, x25519Key: encryptionKey)
            super.init()
        }

        public func encode(with coder: NSCoder) {
            coder.encode(address, forKey: "address")
            coder.encode(port, forKey: "port")
            coder.encode(publicKeySet.ed25519Key, forKey: "idKey")
            coder.encode(publicKeySet.x25519Key, forKey: "encryptionKey")
        }

        override public func isEqual(_ other: Any?) -> Bool {
            guard let other = other as? Snode else { return false }
            return address == other.address && port == other.port
        }

        override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
            return address.hashValue ^ port.hashValue
        }
    }
}
