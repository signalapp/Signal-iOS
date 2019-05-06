
public extension ECKeyPair {
    
    var hexEncodedPrivateKey: String {
        return privateKey.map { String(format: "%02hhx", $0) }.joined()
    }
    
    var hexEncodedPublicKey: String {
        // Prefixing with "05" is necessary for what seems to be a sort of Signal public key versioning system
        return "05" + publicKey.map { String(format: "%02hhx", $0) }.joined()
    }
    
    @objc public static func isValidHexEncodedPublicKey(candidate: String) -> Bool {
        // Check that it's a valid hexadecimal encoding
        let allowedCharacters = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard candidate.uppercased().unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else { return false }
        // Check that it has either length 66 and a leading "05" or length 64
        guard (candidate.count == 66 && candidate.hasPrefix("05")) || candidate.count == 64 else { return false }
        // It appears to be a valid public key
        return true
    }
}
