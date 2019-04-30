
extension ECKeyPair {
    
    var hexEncodedPublicKey: String {
        return publicKey.map { String(format: "%02hhx", $0) }.joined()
    }
}
