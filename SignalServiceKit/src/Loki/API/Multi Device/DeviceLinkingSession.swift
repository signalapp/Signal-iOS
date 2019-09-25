import Curve25519Kit
import PromiseKit

@objc (LKDeviceLinkingSession)
public final class DeviceLinkingSession : NSObject {
    private let delegate: DeviceLinkingSessionDelegate
    @objc public var isListeningForLinkingRequests = false
    @objc public var isProcessingLinkingRequest = false
    @objc public var isListeningForLinkingAuthorization = false
    
    // MARK: Lifecycle
    @objc public static var current: DeviceLinkingSession?
    
    private init(delegate: DeviceLinkingSessionDelegate) {
        self.delegate = delegate
    }

    // MARK: Public API
    public static func startListeningForLinkingRequests(with delegate: DeviceLinkingSessionDelegate) -> DeviceLinkingSession {
        let session = DeviceLinkingSession(delegate: delegate)
        session.isListeningForLinkingRequests = true
        DeviceLinkingSession.current = session
        return session
    }
    
    public static func startListeningForLinkingAuthorization(with delegate: DeviceLinkingSessionDelegate) -> DeviceLinkingSession {
        let session = DeviceLinkingSession(delegate: delegate)
        session.isListeningForLinkingAuthorization = true
        DeviceLinkingSession.current = session
        return session
    }
    
    @objc public func processLinkingRequest(from slaveHexEncodedPublicKey: String, to masterHexEncodedPublicKey: String, with slaveSignature: Data) {
        guard isListeningForLinkingRequests, !isProcessingLinkingRequest, masterHexEncodedPublicKey == OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey else { return }
        let master = DeviceLink.Device(hexEncodedPublicKey: masterHexEncodedPublicKey)
        let slave = DeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
        let deviceLink = DeviceLink(between: master, and: slave)
        guard hasValidSlaveSignature(deviceLink) else { return }
        isProcessingLinkingRequest = true
        DispatchQueue.main.async {
            self.delegate.requestUserAuthorization(for: deviceLink)
        }
    }
    
    @objc public func processLinkingAuthorization(from masterHexEncodedPublicKey: String, for slaveHexEncodedPublicKey: String, masterSignature: Data, slaveSignature: Data) {
        guard isListeningForLinkingAuthorization, slaveHexEncodedPublicKey == OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey else { return }
        let master = DeviceLink.Device(hexEncodedPublicKey: masterHexEncodedPublicKey, signature: masterSignature)
        let slave = DeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
        let deviceLink = DeviceLink(between: master, and: slave)
        guard hasValidSlaveSignature(deviceLink) && hasValidMasterSignature(deviceLink) else { return }
        DispatchQueue.main.async {
            self.delegate.handleDeviceLinkAuthorized(deviceLink)
        }
    }
    
    public func stopListeningForLinkingRequests() {
        DeviceLinkingSession.current = nil
        isListeningForLinkingRequests = false
    }
    
    public func stopListeningForLinkingAuthorization() {
        DeviceLinkingSession.current = nil
        isListeningForLinkingAuthorization = false
    }
    
    public func markLinkingRequestAsProcessed() {
        isProcessingLinkingRequest = false
    }
    
    // MARK: Private API
    
    // When requesting a device link, the slave device signs the master device's public key. When authorizing
    // a device link, the master device signs the slave device's public key.
    
    private func hasValidSlaveSignature(_ deviceLink: DeviceLink) -> Bool {
        guard let slaveSignature = deviceLink.slave.signature else { return false }
        let slavePublicKey = Data(hex: deviceLink.slave.hexEncodedPublicKey.removing05PrefixIfNeeded())
        var kind = LKDeviceLinkMessageKind.request
        let data = Data(hex: deviceLink.master.hexEncodedPublicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        return (try? Ed25519.verifySignature(slaveSignature, publicKey: slavePublicKey, data: data)) ?? false
    }
    
    private func hasValidMasterSignature(_ deviceLink: DeviceLink) -> Bool {
        guard let masterSignature = deviceLink.master.signature else { return false }
        let masterPublicKey = Data(hex: deviceLink.master.hexEncodedPublicKey.removing05PrefixIfNeeded())
        var kind = LKDeviceLinkMessageKind.authorization
        let data = Data(hex: deviceLink.slave.hexEncodedPublicKey) + Data(bytes: &kind, count: MemoryLayout.size(ofValue: kind))
        return (try? Ed25519.verifySignature(masterSignature, publicKey: masterPublicKey, data: data)) ?? false
    }
}
