
public enum DeviceLinkingUtilities {
    
    // When requesting a device link, the slave device signs the master device's public key. When authorizing
    // a device link, the master device signs the slave device's public key.
    
    public static func getLinkingRequestMessage(for masterHexEncodedPublicKey: String) -> DeviceLinkMessage {
        let slaveKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let slaveHexEncodedPublicKey = slaveKeyPair.hexEncodedPublicKey
        var kind = LKDeviceLinkMessageKind.request
        let data = Data(hex: masterHexEncodedPublicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        let slaveSignature = try! Ed25519.sign(data, with: slaveKeyPair)
        let thread = TSContactThread.getOrCreateThread(contactId: masterHexEncodedPublicKey)
        return DeviceLinkMessage(in: thread, masterHexEncodedPublicKey: masterHexEncodedPublicKey, slaveHexEncodedPublicKey: slaveHexEncodedPublicKey, masterSignature: nil, slaveSignature: slaveSignature)
    }
    
    public static func getLinkingAuthorizationMessage(for deviceLink: DeviceLink) -> DeviceLinkMessage {
        let masterKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let masterHexEncodedPublicKey = masterKeyPair.hexEncodedPublicKey
        let slaveHexEncodedPublicKey = deviceLink.slave.hexEncodedPublicKey
        var kind = LKDeviceLinkMessageKind.authorization
        let data = Data(hex: slaveHexEncodedPublicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        let masterSignature = try! Ed25519.sign(data, with: masterKeyPair)
        let slaveSignature = deviceLink.slave.signature!
        let thread = TSContactThread.getOrCreateThread(contactId: slaveHexEncodedPublicKey)
        return DeviceLinkMessage(in: thread, masterHexEncodedPublicKey: masterHexEncodedPublicKey, slaveHexEncodedPublicKey: slaveHexEncodedPublicKey, masterSignature: masterSignature, slaveSignature: slaveSignature)
    }
}
