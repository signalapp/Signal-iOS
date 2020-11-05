import Foundation

public struct Snode : Hashable, CustomStringConvertible {
    public let address: String
    public let port: UInt16
    public let publicKeySet: KeySet

    public var ip: String {
        address.removingPrefix("https://")
    }

    // MARK: Method
    public enum Method : String {
        case getSwarm = "get_snodes_for_pubkey"
        case getMessages = "retrieve"
        case sendMessage = "store"
    }

    // MARK: Key Set
    public struct KeySet : Hashable {
        public let ed25519Key: String
        public let x25519Key: String

        public static func == (lhs: KeySet, rhs: KeySet) -> Bool {
            return lhs.ed25519Key == rhs.ed25519Key && lhs.x25519Key == rhs.x25519Key
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(ed25519Key)
            hasher.combine(x25519Key)
        }
    }
    
    // MARK: Initialization
    internal init(address: String, port: UInt16, publicKeySet: KeySet) {
        self.address = address
        self.port = port
        self.publicKeySet = publicKeySet
    }
    
    // MARK: Equality
    public static func == (lhs: Snode, rhs: Snode) -> Bool {
        return lhs.address == rhs.address && lhs.port == rhs.port && lhs.publicKeySet == rhs.publicKeySet
    }

    // MARK: Hashing
    public func hash(into hasher: inout Hasher) {
        hasher.combine(address)
        hasher.combine(port)
        publicKeySet.hash(into: &hasher)
    }

    // MARK: Description
    public var description: String { "\(address):\(port)" }
}
