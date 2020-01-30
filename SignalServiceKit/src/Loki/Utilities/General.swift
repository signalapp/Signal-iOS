
public func getUserHexEncodedPublicKey() -> String {
    return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
}
