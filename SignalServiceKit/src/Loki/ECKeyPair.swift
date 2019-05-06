
public extension ECKeyPair {
    
    var hexEncodedPrivateKey: String {
        return privateKey.map { String(format: "%02hhx", $0) }.joined()
    }
    
    var hexEncodedPublicKey: String {
        // Prefixing with "05" is necessary for what seems to be a sort of Signal public key versioning system
        return "05" + publicKey.map { String(format: "%02hhx", $0) }.joined()
    }
}
