
@objc(LKDeviceLinkingUtilities)
public final class DeviceLinkingUtilities : NSObject {
    private static var lastUnexpectedDeviceLinkRequestDate: Date? = nil

    private override init() { }

    @objc public static var shouldShowUnexpectedDeviceLinkRequestReceivedAlert: Bool {
        let now = Date()
        if let lastUnexpectedDeviceLinkRequestDate = lastUnexpectedDeviceLinkRequestDate {
            if now.timeIntervalSince(lastUnexpectedDeviceLinkRequestDate) < 30 { return false }
        }
        lastUnexpectedDeviceLinkRequestDate = now
        return true
    }

    // When requesting a device link, the slave device signs the master device's public key. When authorizing
    // a device link, the master device signs the slave device's public key.
    
    public static func getLinkingRequestMessage(for masterPublicKey: String) -> DeviceLinkMessage {
        let slaveKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let slavePublicKey = slaveKeyPair.hexEncodedPublicKey
        var kind = UInt8(LKDeviceLinkMessageKind.request.rawValue)
        let data = Data(hex: masterPublicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        let slaveSignature = try! Ed25519.sign(data, with: slaveKeyPair)
        let thread = TSContactThread.getOrCreateThread(contactId: masterPublicKey)
        return DeviceLinkMessage(in: thread, masterPublicKey: masterPublicKey, slavePublicKey: slavePublicKey, masterSignature: nil, slaveSignature: slaveSignature)
    }
    
    public static func getLinkingAuthorizationMessage(for deviceLink: DeviceLink) -> DeviceLinkMessage {
        let masterKeyPair = OWSIdentityManager.shared().identityKeyPair()!
        let masterPublicKey = masterKeyPair.hexEncodedPublicKey
        let slavePublicKey = deviceLink.slave.publicKey
        var kind = UInt8(LKDeviceLinkMessageKind.authorization.rawValue)
        let data = Data(hex: slavePublicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        let masterSignature = try! Ed25519.sign(data, with: masterKeyPair)
        let slaveSignature = deviceLink.slave.signature!
        let thread = TSContactThread.getOrCreateThread(contactId: slavePublicKey)
        return DeviceLinkMessage(in: thread, masterPublicKey: masterPublicKey, slavePublicKey: slavePublicKey, masterSignature: masterSignature, slaveSignature: slaveSignature)
    }

    public static func hasValidSlaveSignature(_ deviceLink: DeviceLink) -> Bool {
        guard let slaveSignature = deviceLink.slave.signature else { return false }
        let slavePublicKey = Data(hex: deviceLink.slave.publicKey.removing05PrefixIfNeeded())
        var kind = UInt8(LKDeviceLinkMessageKind.request.rawValue)
        let data = Data(hex: deviceLink.master.publicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        return (try? Ed25519.verifySignature(slaveSignature, publicKey: slavePublicKey, data: data)) ?? false
    }

    public static func hasValidMasterSignature(_ deviceLink: DeviceLink) -> Bool {
        guard let masterSignature = deviceLink.master.signature else { return false }
        let masterPublicKey = Data(hex: deviceLink.master.publicKey.removing05PrefixIfNeeded())
        var kind = UInt8(LKDeviceLinkMessageKind.authorization.rawValue)
        let data = Data(hex: deviceLink.slave.publicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        return (try? Ed25519.verifySignature(masterSignature, publicKey: masterPublicKey, data: data)) ?? false
    }
}
