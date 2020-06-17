import PromiseKit

@objc(LKPoller)
public final class LokiPoller : NSObject {
    private let onMessagesReceived: ([SSKProtoEnvelope]) -> Void
    private let storage = OWSPrimaryStorage.shared()
    private var hasStarted = false
    private var hasStopped = false
    private var usedSnodes = Set<LokiAPITarget>()
    private var pollCount = 0

    // MARK: Settings
    private static let retryInterval: TimeInterval = 0.25
    /// After polling a given snode this many times we always switch to a new one.
    ///
    /// The reason for doing this is that sometimes a snode will be giving us successful responses while
    /// it isn't actually getting messages from other snodes.
    private static let maxPollCount: UInt = 6

    // MARK: Error
    private enum Error : LocalizedError {
        case pollLimitReached

        var localizedDescription: String {
            switch self {
            case .pollLimitReached: return "Poll limit reached for current snode."
            }
        }
    }

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
        LokiAPI.getSwarm(for: getUserHexEncodedPublicKey(), isForcedReload: true).then2 { [weak self] _ -> Promise<Void> in
            guard let strongSelf = self else { return Promise { $0.fulfill(()) } }
            strongSelf.usedSnodes.removeAll()
            let (promise, seal) = Promise<Void>.pending()
            strongSelf.pollNextSnode(seal: seal)
            return promise
        }.ensure(on: DispatchQueue.main) { [weak self] in
            guard let strongSelf = self, !strongSelf.hasStopped else { return }
            Timer.scheduledTimer(withTimeInterval: LokiPoller.retryInterval, repeats: false) { _ in
                guard let strongSelf = self else { return }
                strongSelf.setUpPolling()
            }
        }
    }

    private func pollNextSnode(seal: Resolver<Void>) {
        let userPublicKey = getUserHexEncodedPublicKey()
        let swarm = LokiAPI.swarmCache[userPublicKey] ?? []
        let unusedSnodes = Set(swarm).subtracting(usedSnodes)
        if !unusedSnodes.isEmpty {
            // randomElement() uses the system's default random generator, which is cryptographically secure
            let nextSnode = unusedSnodes.randomElement()!
            usedSnodes.insert(nextSnode)
            poll(nextSnode, seal: seal).done2 {
                seal.fulfill(())
            }.catch2 { [weak self] error in
                if let error = error as? Error, error == .pollLimitReached {
                    self?.pollCount = 0
                } else {
                    print("[Loki] Polling \(nextSnode) failed; dropping it and switching to next snode.")
                    LokiAPI.dropSnodeFromSwarmIfNeeded(nextSnode, hexEncodedPublicKey: userPublicKey)
                }
                self?.pollNextSnode(seal: seal)
            }
        } else {
            seal.fulfill(())
        }
    }

    private func poll(_ target: LokiAPITarget, seal longTermSeal: Resolver<Void>) -> Promise<Void> {
        return LokiAPI.getRawMessages(from: target, usingLongPolling: false).then2 { [weak self] rawResponse -> Promise<Void> in
            guard let strongSelf = self, !strongSelf.hasStopped else { return Promise { $0.fulfill(()) } }
            let messages = LokiAPI.parseRawMessagesResponse(rawResponse, from: target)
            strongSelf.onMessagesReceived(messages)
            strongSelf.pollCount += 1
            if strongSelf.pollCount == LokiPoller.maxPollCount {
                throw Error.pollLimitReached
            } else {
                return strongSelf.poll(target, seal: longTermSeal)
            }
        }
    }
}
