
public func getUserHexEncodedPublicKey() -> String {
    // In some cases like deleting an account
    // the backgroud fetch was not stopped
    // so the identityKeyPair can be nil
    if let keyPair = OWSIdentityManager.shared().identityKeyPair() {
        return keyPair.hexEncodedPublicKey
    }
    return ""
}
