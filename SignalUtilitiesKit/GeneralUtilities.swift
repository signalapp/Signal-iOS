
public func getUserHexEncodedPublicKey() -> String {
    if let keyPair = OWSIdentityManager.shared().identityKeyPair() { // Can be nil under some circumstances
        return keyPair.hexEncodedPublicKey
    }
    return ""
}
