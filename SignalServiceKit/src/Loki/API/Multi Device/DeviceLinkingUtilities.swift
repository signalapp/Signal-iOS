
public enum DeviceLinkingUtilities {
    
    // When requesting a device link, the slave device signs the master device's public key. When authorizing
    // a device link, the master device signs the slave device's public key.
    
    public static func getLinkingRequestMessage(for masterHexEncodedPublicKey: String) -> DeviceLinkMessage {
        let slaveKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let slaveHexEncodedPublicKey = slaveKeyPair.hexEncodedPublicKey.removing05PrefixIfNeeded()
        let slaveSignature = try! Ed25519.sign(Data(hex: masterHexEncodedPublicKey.removing05PrefixIfNeeded()), with: slaveKeyPair)
        let thread = TSContactThread.getOrCreateThread(contactId: masterHexEncodedPublicKey)
        return DeviceLinkMessage(in: thread, masterHexEncodedPublicKey: masterHexEncodedPublicKey.removing05PrefixIfNeeded(), slaveHexEncodedPublicKey: slaveHexEncodedPublicKey,
            masterSignature: nil, slaveSignature: slaveSignature, kind: .request)
    }
    
    public static func getLinkingAuthorizationMessage(for deviceLink: DeviceLink) -> DeviceLinkMessage {
        let masterKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let masterHexEncodedPublicKey = masterKeyPair.hexEncodedPublicKey.removing05PrefixIfNeeded()
        let slaveHexEncodedPublicKey = deviceLink.slave.hexEncodedPublicKey
        let masterSignature = try! Ed25519.sign(Data(hex: slaveHexEncodedPublicKey.removing05PrefixIfNeeded()), with: masterKeyPair)
        let slaveSignature = deviceLink.slave.signature!
        let thread = TSContactThread.getOrCreateThread(contactId: slaveHexEncodedPublicKey.adding05PrefixIfNeeded())
        return DeviceLinkMessage(in: thread, masterHexEncodedPublicKey: masterHexEncodedPublicKey, slaveHexEncodedPublicKey: slaveHexEncodedPublicKey.removing05PrefixIfNeeded(),
            masterSignature: masterSignature, slaveSignature: slaveSignature, kind: .authorization)
    }
}
