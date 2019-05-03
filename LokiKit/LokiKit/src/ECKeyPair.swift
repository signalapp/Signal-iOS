
public extension ECKeyPair {
    
    var hexEncodedPrivateKey: String {
        return privateKey.map { String(format: "%02hhx", $0) }.joined()
    }
    
    var hexEncodedPublicKey: String {
        return "05" + publicKey.map { String(format: "%02hhx", $0) }.joined()
    }
}
