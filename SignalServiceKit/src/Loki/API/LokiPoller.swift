import PromiseKit

@objc(LKPoller)
public final class LokiPoller : NSObject {
    private let onMessagesReceived: ([SSKProtoEnvelope]) -> Void
    private let storage = OWSPrimaryStorage.shared()
    private var hasStarted = false
    private var hasStopped = false
    private var usedSnodes = Set<LokiAPITarget>()

    // MARK: Settings
    private static let retryInterval: TimeInterval = 4

    // MARK: Initialization
    @objc public init(onMessagesReceived: @escaping ([SSKProtoEnvelope]) -> Void) {
        self.onMessagesReceived = onMessagesReceived
        super.init()
    }

    // MARK: Public API
    @objc public func startIfNeeded() {
        guard !hasStarted else { return }
        print("[Loki] Started polling.")
        hasStarted = true
        hasStopped = false
        setUpPolling()
    }

    @objc public func stopIfNeeded() {
        guard !hasStopped else { return }
        print("[Loki] Stopped polling.")
        hasStarted = false
        hasStopped = true
        usedSnodes.removeAll()
    }

    // MARK: Private API
    private func setUpPolling() {
        guard !hasStopped else { return }
        LokiAPI.getSwarm(for: getUserHexEncodedPublicKey()).then { [weak self] _ -> Promise<Void> in
            guard let strongSelf = self else { return Promise { $0.fulfill(()) } }
            strongSelf.usedSnodes.removeAll()
            let (promise, seal) = Promise<Void>.pending()
            strongSelf.pollNextSnode(seal: seal)
            return promise
        }.ensure { [weak self] in
            guard let strongSelf = self, !strongSelf.hasStopped else { return }
            Timer.scheduledTimer(withTimeInterval: LokiPoller.retryInterval, repeats: false) { _ in
                guard let strongSelf = self else { return }
                strongSelf.setUpPolling()
            }
        }
    }

    private func pollNextSnode(seal: Resolver<Void>) {
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        let swarm = LokiAPI.swarmCache[userHexEncodedPublicKey] ?? []
        let unusedSnodes = Set(swarm).subtracting(usedSnodes)
        if !unusedSnodes.isEmpty {
            // randomElement() uses the system's default random generator, which is cryptographically secure
            let nextSnode = unusedSnodes.randomElement()!
            usedSnodes.insert(nextSnode)
            print("[Loki] Polling \(nextSnode).")
            poll(nextSnode, seal: seal).done(on: DispatchQueue.global()) {
                seal.fulfill(())
            }.catch(on: LokiAPI.errorHandlingQueue) { [weak self] error in
                print("[Loki] Polling \(nextSnode) failed; dropping it and switching to next snode.")
                LokiAPI.dropIfNeeded(nextSnode, hexEncodedPublicKey: userHexEncodedPublicKey)
                self?.pollNextSnode(seal: seal)
            }
        } else {
            seal.fulfill(())
        }
    }

    private func poll(_ target: LokiAPITarget, seal longTermSeal: Resolver<Void>) -> Promise<Void> {
        return LokiAPI.getRawMessages(from: target, usingLongPolling: false).then(on: DispatchQueue.global()) { [weak self] rawResponse -> Promise<Void> in
            guard let strongSelf = self, !strongSelf.hasStopped else { return Promise { $0.fulfill(()) } }
            let messages = LokiAPI.parseRawMessagesResponse(rawResponse, from: target)
            strongSelf.onMessagesReceived(messages)
            return strongSelf.poll(target, seal: longTermSeal)
        }
    }
}
