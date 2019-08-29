
@objc(LKGroupChatModPoller)
public final class LokiGroupChatModPoller : NSObject {
    private let group: LokiGroupChat
    private var timer: Timer? = nil
    private var hasStarted = false
    
    private let interval: TimeInterval = 10 * 60
    
    private let storage = OWSPrimaryStorage.shared()
    private let ourHexEncodedPubKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    
    @objc(initForGroup:)
    public init(for group: LokiGroupChat) {
        self.group = group
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.pollForModeratorStatus() }
        pollForModeratorStatus() // Perform initial update
        hasStarted = true
    }
    
    @objc public func stop() {
        timer?.invalidate()
        hasStarted = false
    }
    
    private func pollForModeratorStatus() {
        let group = self.group
        let _ = LokiGroupChatAPI.isCurrentUserMod(on: group.server).done { [weak self] isModerator in
            guard let self = self else { return }
            self.storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setIsModerator(isModerator, for: group.server, transaction: transaction)
            }
        }
    }
}
