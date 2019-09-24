
public enum DeviceLinkingUtilities {
    
    // When requesting a device link, the slave device signs the master device's public key. When authorizing
    // a device link, the master device signs the slave device's public key.
    
    public static func getLinkingRequestMessage(for masterHexEncodedPublicKey: String) -> DeviceLinkingMessage {
        let slaveKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let slaveHexEncodedPublicKey = slaveKeyPair.hexEncodedPublicKey
        let slaveSignature = try! Ed25519.sign(Data(hex: masterHexEncodedPublicKey), with: slaveKeyPair)
        let thread = TSContactThread.getOrCreateThread(contactId: masterHexEncodedPublicKey)
        return DeviceLinkingMessage(in: thread, masterHexEncodedPublicKey: masterHexEncodedPublicKey, slaveHexEncodedPublicKey: slaveHexEncodedPublicKey, masterSignature: nil, slaveSignature: slaveSignature)
    }
    
    public static func getLinkingAuthorizationMessage(for deviceLink: DeviceLink) -> DeviceLinkingMessage {
        let masterKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let masterHexEncodedPublicKey = masterKeyPair.hexEncodedPublicKey
        let slaveHexEncodedPublicKey = deviceLink.slave.hexEncodedPublicKey
        let masterSignature = try! Ed25519.sign(Data(hex: slaveHexEncodedPublicKey), with: masterKeyPair)
        let slaveSignature = deviceLink.slave.signature!
        let thread = TSContactThread.getOrCreateThread(contactId: slaveHexEncodedPublicKey)
        return DeviceLinkingMessage(in: thread, masterHexEncodedPublicKey: masterHexEncodedPublicKey, slaveHexEncodedPublicKey: slaveHexEncodedPublicKey, masterSignature: masterSignature, slaveSignature: slaveSignature)
    }
}
