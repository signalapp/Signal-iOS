import SessionSnodeKit
import PromiseKit

@objc(LKClosedGroupPoller)
public final class ClosedGroupPoller : NSObject {
    private var isPolling = false
    private var timer: Timer?

    // MARK: Settings
    private static let pollInterval: TimeInterval = 2

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
        #if DEBUG
        assert(Thread.current.isMainThread) // Timers don't do well on background queues
        #endif
        guard !isPolling else { return }
        isPolling = true
        timer = Timer.scheduledTimer(withTimeInterval: ClosedGroupPoller.pollInterval, repeats: true) { [weak self] _ in
            let _ = self?.poll()
        }
    }

    public func pollOnce() -> [Promise<Void>] {
        guard !isPolling else { return [] }
        isPolling = true
        return poll()
    }

    @objc public func stop() {
        isPolling = false
        timer?.invalidate()
    }

    // MARK: Private API
    private func poll() -> [Promise<Void>] {
        guard isPolling else { return [] }
        let publicKeys = Storage.shared.getUserClosedGroupPublicKeys()
        return publicKeys.map { publicKey in
            let promise = SnodeAPI.getSwarm(for: publicKey).then2 { [weak self] swarm -> Promise<[JSON]> in
                // randomElement() uses the system's default random generator, which is cryptographically secure
                guard let snode = swarm.randomElement() else { return Promise(error: Error.insufficientSnodes) }
                guard let self = self, self.isPolling else { return Promise(error: Error.pollingCanceled) }
                return SnodeAPI.getRawMessages(from: snode, associatedWith: publicKey).map2 {
                    SnodeAPI.parseRawMessagesResponse($0, from: snode, associatedWith: publicKey)
                }
            }
            promise.done2 { [weak self] messages in
                guard let self = self, self.isPolling else { return }
                if !messages.isEmpty {
                    SNLog("Received \(messages.count) new message(s) in closed group with public key: \(publicKey).")
                }
                messages.forEach { json in
                    guard let envelope = SNProtoEnvelope.from(json) else { return }
                    do {
                        let data = try envelope.serializedData()
                        let job = MessageReceiveJob(data: data, isBackgroundPoll: false)
                        Storage.write { transaction in
                            SessionMessagingKit.JobQueue.shared.add(job, using: transaction)
                        }
                    } catch {
                        SNLog("Failed to deserialize envelope due to error: \(error).")
                    }
                }
            }
            promise.catch2 { error in
                SNLog("Polling failed for closed group with public key: \(publicKey) due to error: \(error).")
            }
            return promise.map { _ in }
        }
    }
}
