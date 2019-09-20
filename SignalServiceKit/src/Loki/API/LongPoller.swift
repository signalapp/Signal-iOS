import PromiseKit

@objc(LKLongPoller)
public final class LongPoller : NSObject {
    private let onMessagesReceived: ([SSKProtoEnvelope]) -> Void
    private let storage = OWSPrimaryStorage.shared()
    private var hasStarted = false
    private var hasStopped = false
    private var connections = Set<Promise<Void>>()
    private var usedSnodes = Set<LokiAPITarget>()

    // MARK: Settings
    private let connectionCount = 3
    private let retryInterval: TimeInterval = 4

    // MARK: Convenience
    private var userHexEncodedPublicKey: String { return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey }

    // MARK: Initialization
    @objc public init(onMessagesReceived: @escaping ([SSKProtoEnvelope]) -> Void) {
        self.onMessagesReceived = onMessagesReceived
        super.init()
    }

    // MARK: Public API
    @objc public func startIfNeeded() {
        guard !hasStarted else { return }
        print("[Loki] Started long polling.")
        hasStarted = true
        hasStopped = false
        openConnections()
    }

    @objc public func stopIfNeeded() {
        guard !hasStopped else { return }
        print("[Loki] Stopped long polling.")
        hasStarted = false
        hasStopped = true
        usedSnodes.removeAll()
    }

    // MARK: Private API
    private func openConnections() {
        guard !hasStopped else { return }
        LokiAPI.getSwarm(for: userHexEncodedPublicKey).then { [weak self] _ -> Guarantee<[Result<Void>]> in
            guard let strongSelf = self else { return Guarantee.value([Result<Void>]()) }
            strongSelf.usedSnodes.removeAll()
            let connections: [Promise<Void>] = (0..<strongSelf.connectionCount).map { _ in
                let (promise, seal) = Promise<Void>.pending()
                strongSelf.openConnectionToNextSnode(seal: seal)
                return promise
            }
            strongSelf.connections = Set(connections)
            return when(resolved: connections)
        }.ensure { [weak self] in
            guard let strongSelf = self else { return }
            Timer.scheduledTimer(withTimeInterval: strongSelf.retryInterval, repeats: false) { _ in
                guard let strongSelf = self else { return }
                strongSelf.openConnections()
            }
        }
    }

    private func openConnectionToNextSnode(seal: Resolver<Void>) {
        let swarm = LokiAPI.swarmCache[userHexEncodedPublicKey] ?? []
        let userHexEncodedPublicKey = self.userHexEncodedPublicKey
        let unusedSnodes = Set(swarm).subtracting(usedSnodes)
        if !unusedSnodes.isEmpty {
            let nextSnode = unusedSnodes.randomElement()!
            usedSnodes.insert(nextSnode)
            print("[Loki] Opening long polling connection to \(nextSnode).")
            longPoll(nextSnode, seal: seal).catch { [weak self] error in
                print("[Loki] Long polling connection to \(nextSnode) failed; dropping it and switching to next snode.")
                LokiAPI.dropIfNeeded(nextSnode, hexEncodedPublicKey: userHexEncodedPublicKey)
                self?.openConnectionToNextSnode(seal: seal)
            }
        } else {
            seal.fulfill(())
        }
    }

    private func longPoll(_ target: LokiAPITarget, seal: Resolver<Void>) -> Promise<Void> {
        return LokiAPI.getRawMessages(from: target, usingLongPolling: true).then { [weak self] rawResponse -> Promise<Void> in
            guard let strongSelf = self, !strongSelf.hasStopped else { return Promise.value(()) }
            let messages = LokiAPI.parseRawMessagesResponse(rawResponse, from: target)
            strongSelf.onMessagesReceived(messages)
            return strongSelf.longPoll(target, seal: seal)
        }
    }
}
