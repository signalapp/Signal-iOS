
public extension ECKeyPair {
    
    @objc public var hexEncodedPrivateKey: String {
        return privateKey.map { String(format: "%02hhx", $0) }.joined()
    }
    
    @objc public var hexEncodedPublicKey: String {
        // Prefixing with "05" is necessary for what seems to be a sort of Signal public key versioning system
        return "05" + publicKey.map { String(format: "%02hhx", $0) }.joined()
    }
    
    @objc public static func isValidHexEncodedPublicKey(candidate: String) -> Bool {
        // Check that it's a valid hexadecimal encoding
        let allowedCharacters = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard candidate.uppercased().unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else { return false }
        // Check that it has length 66 and a leading "05"
        guard candidate.count == 66 && candidate.hasPrefix("05") else { return false }
        // It appears to be a valid public key
        return true
    }
}
