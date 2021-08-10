import Foundation

public final class Snode : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public let address: String
    public let port: UInt16
    public let publicKeySet: KeySet

    public var ip: String {
        address.removingPrefix("https://")
    }

    // MARK: Nested Types
    public enum Method : String {
        case getSwarm = "get_snodes_for_pubkey"
        case getMessages = "retrieve"
        case sendMessage = "store"
        case deleteMessage = "delete"
        case oxenDaemonRPCCall = "oxend_request"
        case getInfo = "info"
        case clearAllData = "delete_all"
    }

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

    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? Snode else { return false }
        return address == other.address && port == other.port
    }

    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return address.hashValue ^ port.hashValue
    }

    // MARK: Description
    override public var description: String { return "\(address):\(port)" }
}
