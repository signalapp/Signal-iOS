import SessionSnodeKit
import PromiseKit

@objc(LKClosedGroupPoller)
public final class ClosedGroupPoller : NSObject {
    private var isPolling: [String:Bool] = [:]
    private var timers: [String:Timer] = [:]
    private let internalQueue: DispatchQueue = DispatchQueue(label:"isPollingQueue")

    // MARK: Settings
    private static let minPollInterval: Double = 2
    private static let maxPollInterval: Double = 30

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

    // MARK: Initialization
    public static let shared = ClosedGroupPoller()

    private override init() { }

    // MARK: Public API
    @objc public func start() {
        #if DEBUG
        assert(Thread.current.isMainThread) // Timers don't do well on background queues
        #endif
        let storage = SNMessagingKitConfiguration.shared.storage
        let allGroupPublicKeys = storage.getUserClosedGroupPublicKeys()
        allGroupPublicKeys.forEach { startPolling(for: $0) }
    }

    public func startPolling(for groupPublicKey: String) {
        guard !isPolling(for: groupPublicKey) else { return }
        // Might be a race condition that the setUpPolling finishes too soon,
        // and the timer is not created, if we mark the group as is polling
        // after setUpPolling. So the poller may not work, thus misses messages.
        internalQueue.sync{ isPolling[groupPublicKey] = true }
        setUpPolling(for: groupPublicKey)
    }

    @objc public func stop() {
        let storage = SNMessagingKitConfiguration.shared.storage
        let allGroupPublicKeys = storage.getUserClosedGroupPublicKeys()
        allGroupPublicKeys.forEach { stopPolling(for: $0) }
    }

    public func stopPolling(for groupPublicKey: String) {
        internalQueue.sync{ isPolling[groupPublicKey] = false }
        timers[groupPublicKey]?.invalidate()
    }

    // MARK: Private API
    private func setUpPolling(for groupPublicKey: String) {
        Threading.pollerQueue.async {
            self.poll(groupPublicKey).done(on: Threading.pollerQueue) { [weak self] _ in
                self?.pollRecursively(groupPublicKey)
            }.catch(on: Threading.pollerQueue) { [weak self] error in
                // The error is logged in poll(_:)
                self?.pollRecursively(groupPublicKey)
            }
        }
    }

    private func pollRecursively(_ groupPublicKey: String) {
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        guard isPolling(for: groupPublicKey),
            let thread = TSGroupThread.fetch(uniqueId: TSGroupThread.threadId(fromGroupId: groupID)) else { return }
        // Get the received date of the last message in the thread. If we don't have any messages yet, pick some
        // reasonable fake time interval to use instead.
        let lastMessageDate =
            (thread.numberOfInteractions() > 0) ? thread.lastInteraction.receivedAtDate() : Date().addingTimeInterval(-5 * 60)
        let timeSinceLastMessage = Date().timeIntervalSince(lastMessageDate)
        let minPollInterval = ClosedGroupPoller.minPollInterval
        let limit: Double = 12 * 60 * 60
        let a = (ClosedGroupPoller.maxPollInterval - minPollInterval) / limit
        let nextPollInterval = a * min(timeSinceLastMessage, limit) + minPollInterval
        SNLog("Next poll interval for closed group with public key: \(groupPublicKey) is \(nextPollInterval) s.")
        timers[groupPublicKey] = Timer.scheduledTimerOnMainThread(withTimeInterval: nextPollInterval, repeats: false) { [weak self] timer in
            timer.invalidate()
            Threading.pollerQueue.async {
                self?.poll(groupPublicKey).done(on: Threading.pollerQueue) { _ in
                    self?.pollRecursively(groupPublicKey)
                }.catch(on: Threading.pollerQueue) { error in
                    // The error is logged in poll(_:)
                    self?.pollRecursively(groupPublicKey)
                }
            }
        }
    }

    private func poll(_ groupPublicKey: String) -> Promise<Void> {
        guard isPolling(for: groupPublicKey) else { return Promise.value(()) }
        let promise = SnodeAPI.getSwarm(for: groupPublicKey).then2 { [weak self] swarm -> Promise<(Snode, [JSON], JSON?)> in
            // randomElement() uses the system's default random generator, which is cryptographically secure
            guard let snode = swarm.randomElement() else { return Promise(error: Error.insufficientSnodes) }
            guard let self = self, self.isPolling(for: groupPublicKey) else { return Promise(error: Error.pollingCanceled) }
            return SnodeAPI.getRawMessages(from: snode, associatedWith: groupPublicKey).map2 {
                let (rawMessages, lastRawMessage) = SnodeAPI.parseRawMessagesResponse($0, from: snode, associatedWith: groupPublicKey)
                
                return (snode, rawMessages, lastRawMessage)
            }
        }
        promise.done2 { [weak self] snode, rawMessages, lastRawMessage in
            guard let self = self, self.isPolling(for: groupPublicKey) else { return }
            if !rawMessages.isEmpty {
                SNLog("Received \(rawMessages.count) new message(s) in closed group with public key: \(groupPublicKey).")
            }
            rawMessages.forEach { json in
                guard let envelope = SNProtoEnvelope.from(json) else { return }
                do {
                    let data = try envelope.serializedData()
                    let job = MessageReceiveJob(data: data, serverHash: json["hash"] as? String, isBackgroundPoll: false)
                    SNMessagingKitConfiguration.shared.storage.write { transaction in
                        SessionMessagingKit.JobQueue.shared.add(job, using: transaction)
                    }
                } catch {
                    SNLog("Failed to deserialize envelope due to error: \(error).")
                }
            }
            
            // Now that the MessageReceiveJob's have been created we can update the `lastMessageHash` value
            SnodeAPI.updateLastMessageHashValueIfPossible(for: snode, associatedWith: groupPublicKey, from: lastRawMessage)
        }
        promise.catch2 { error in
            SNLog("Polling failed for closed group with public key: \(groupPublicKey) due to error: \(error).")
        }
        return promise.map { _ in }
    }

    // MARK: Convenience
    private func isPolling(for groupPublicKey: String) -> Bool {
        return internalQueue.sync{ isPolling[groupPublicKey] ?? false }
    }
}
