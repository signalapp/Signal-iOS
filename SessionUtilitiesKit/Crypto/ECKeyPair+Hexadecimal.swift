import Curve25519Kit

public extension ECKeyPair {
    
    @objc var hexEncodedPrivateKey: String {
        return privateKey.map { String(format: "%02hhx", $0) }.joined()
    }
    
    @objc var hexEncodedPublicKey: String {
        // Prefixing with 'SessionId.Prefix.standard' is necessary for what seems to be a sort of Signal public key versioning system
        return SessionId(.standard, publicKey: publicKey.bytes).hexString
    }
    
    @objc static func isValidHexEncodedPublicKey(candidate: String) -> Bool {
        // Note: If the logic in here changes ensure it doesn't break `SessionId.Prefix(from:)`
        // Check that it's a valid hexadecimal encoding
        guard Hex.isValid(candidate) else { return false }
        // Check that it has length 66 and a valid prefix
        guard candidate.count == 66 && SessionId.Prefix.allCases.first(where: { candidate.hasPrefix($0.rawValue) }) != nil else {
            return false
        }
        
        // It appears to be a valid public key
        return true
    }
}
