import Curve25519Kit
import PromiseKit

@objc (LKDeviceLinkingSession)
public final class DeviceLinkingSession : NSObject {
    private let delegate: DeviceLinkingSessionDelegate
    @objc public var isListeningForLinkingRequests = false
    
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
    
    @objc public func processLinkingRequest(from slaveHexEncodedPublicKey: String, with slaveSignature: Data) {
        guard isListeningForLinkingRequests else { return }
        stopListeningForLinkingRequests()
        let master = DeviceLink.Device(hexEncodedPublicKey: OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey)
        let slave = DeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
        let deviceLink = DeviceLink(between: master, and: slave)
        guard isValidLinkingRequest(deviceLink) else { return }
        delegate.requestUserAuthorization(for: deviceLink)
    }
    
    public func stopListeningForLinkingRequests() {
        DeviceLinkingSession.current = nil
        isListeningForLinkingRequests = false
    }
    
    public func authorizeDeviceLink(_ deviceLink: DeviceLink) {
        // TODO: Send a device link authorized message
    }
    
    // MARK: Private API
    private func isValidLinkingRequest(_ deviceLink: DeviceLink) -> Bool {
        // When requesting a device link, the slave device signs the master device's public key. When authorizing
        // a device link, the master device signs the slave device's public key.
        let slaveSignature = deviceLink.slave.signature!
        let slavePublicKey = Data(hex: deviceLink.slave.hexEncodedPublicKey)
        let masterPublicKey = Data(hex: deviceLink.master.hexEncodedPublicKey)
        return (try? Ed25519.verifySignature(slaveSignature, publicKey: slavePublicKey, data: masterPublicKey)) ?? false
    }
}
