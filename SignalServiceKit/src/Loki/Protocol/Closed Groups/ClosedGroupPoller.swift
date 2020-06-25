import PromiseKit

@objc(LKClosedGroupPoller)
public final class ClosedGroupPoller : NSObject {
    private var isPolling = false
    private var timer: Timer?

    // MARK: Settings
    private static let pollInterval: TimeInterval = 4

    // MARK: Error
    private enum Error : LocalizedError {
        case insufficientSnodes
        case pollingCanceled

        internal var errorDescription: String? {
            switch self {
            case .insufficientSnodes: return "No snodes left to poll."
            case .pollingCanceled: return "Polling canceled."
            }
        }
    }

    // MARK: Public API
    @objc public func startIfNeeded() {
        AssertIsOnMainThread() // Timers don't do well on background queues
        guard !isPolling else { return }
        isPolling = true
        timer = Timer.scheduledTimer(withTimeInterval: ClosedGroupPoller.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    @objc public func stop() {
        isPolling = false
        timer?.invalidate()
    }

    // MARK: Private API
    private func poll() {
        guard isPolling else { return }
        let publicKeys = Storage.getUserClosedGroupPublicKeys()
        publicKeys.forEach { publicKey in
            SnodeAPI.getSwarm(for: publicKey).then2 { [weak self] swarm -> Promise<[SSKProtoEnvelope]> in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                guard let snode = swarm.randomElement() else { return Promise(error: Error.insufficientSnodes) }
                guard let self = self, self.isPolling else { return Promise(error: Error.pollingCanceled) }
                return SnodeAPI.getRawMessages(from: snode, associatedWith: publicKey).map2 {
                    SnodeAPI.parseRawMessagesResponse($0, from: snode, associatedWith: publicKey)
                }
            }.done2 { [weak self] messages in
                guard let self = self, self.isPolling else { return }
                if !messages.isEmpty {
                    print("[Loki] Received \(messages.count) new message(s) in closed group with public key: \(publicKey).")
                }
                messages.forEach { message in
                    do {
                        let data = try message.serializedData()
                        SSKEnvironment.shared.messageReceiver.handleReceivedEnvelopeData(data)
                    } catch {
                        print("[Loki] Failed to deserialize envelope due to error: \(error).")
                    }
                }
            }.catch2 { error in
                print("[Loki] Polling failed for closed group with public key: \(publicKey) due to error: \(error).")
            }
        }
    }
}
