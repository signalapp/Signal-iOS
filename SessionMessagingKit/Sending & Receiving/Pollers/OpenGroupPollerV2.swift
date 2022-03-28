import PromiseKit

@objc(SNOpenGroupPollerV2)
public final class OpenGroupPollerV2 : NSObject {
    private let server: String
    private var timer: Timer? = nil
    private var hasStarted = false
    private var isPolling = false

    // MARK: Settings
    private let pollInterval: TimeInterval = 4
    static let maxInactivityPeriod: Double = 14 * 24 * 60 * 60

    // MARK: Lifecycle
    public init(for server: String) {
        self.server = server
        super.init()
    }

    @objc public func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        timer = Timer.scheduledTimerOnMainThread(withTimeInterval: pollInterval, repeats: true) { _ in
            self.poll().retainUntilComplete()
        }
        poll().retainUntilComplete()
    }

    @objc public func stop() {
        timer?.invalidate()
        hasStarted = false
    }

    // MARK: Polling
    @discardableResult
    public func poll() -> Promise<Void> {
        return poll(isBackgroundPoll: false)
    }

    @discardableResult
    public func poll(isBackgroundPoll: Bool) -> Promise<Void> {
        guard !self.isPolling else { return Promise.value(()) }
        self.isPolling = true
        let (promise, seal) = Promise<Void>.pending()
        promise.retainUntilComplete()
        Threading.pollerQueue.async {
            OpenGroupAPIV2.compactPoll(self.server).done(on: OpenGroupAPIV2.workQueue) { [weak self] bodies in
                guard let self = self else { return }
                self.isPolling = false
                bodies.forEach { self.handleCompactPollBody($0, isBackgroundPoll: isBackgroundPoll) }
                SNLog("Open group polling finished for \(self.server).")
                seal.fulfill(())
            }.catch(on: OpenGroupAPIV2.workQueue) { error in
                SNLog("Open group polling failed due to error: \(error).")
                self.isPolling = false
                seal.fulfill(()) // The promise is just used to keep track of when we're done
            }
        }
        return promise
    }

    private func handleCompactPollBody(_ body: OpenGroupAPIV2.CompactPollResponseBody, isBackgroundPoll: Bool) {
        let storage = SNMessagingKitConfiguration.shared.storage
        // - Messages
        // Sorting the messages by server ID before importing them fixes an issue where messages that quote older messages can't find those older messages
        let openGroupID = "\(server).\(body.room)"
        let messages = body.messages.sorted { $0.serverID! < $1.serverID! } // Safe because messages with a nil serverID are filtered out
        storage.write { transaction in
            messages.forEach { message in
                guard let data = Data(base64Encoded: message.base64EncodedData) else {
                    return SNLog("Ignoring open group message with invalid encoding.")
                }
                let envelope = SNProtoEnvelope.builder(type: .sessionMessage, timestamp: message.sentTimestamp)
                envelope.setContent(data)
                envelope.setSource(message.sender!) // Safe because messages with a nil sender are filtered out
                do {
                    let data = try envelope.buildSerializedData()
                    let (message, proto) = try MessageReceiver.parse(data, openGroupMessageServerID: UInt64(message.serverID!), isRetry: false, using: transaction)
                    try MessageReceiver.handle(message, associatedWithProto: proto, openGroupID: openGroupID, isBackgroundPoll: isBackgroundPoll, using: transaction)
                } catch {
                    SNLog("Couldn't receive open group message due to error: \(error).")
                }
            }
        }
        
        // - Moderators
        if var x = OpenGroupAPIV2.moderators[server] {
            x[body.room] = Set(body.moderators)
            OpenGroupAPIV2.moderators[server] = x
        } else {
            OpenGroupAPIV2.moderators[server] = [ body.room : Set(body.moderators) ]
        }
        
        // - Deletions
        guard !body.deletions.isEmpty else { return }
        
        let deletedMessageServerIDs = Set(body.deletions.map { UInt64($0.deletedMessageID) })
        storage.write { transaction in
            guard let transaction: YapDatabaseReadWriteTransaction = transaction as? YapDatabaseReadWriteTransaction else { return }
            
            deletedMessageServerIDs.forEach { openGroupServerMessageId in
                guard let messageLookup: OpenGroupServerIdLookup = storage.getOpenGroupServerIdLookup(openGroupServerMessageId, in: body.room, on: self.server, using: transaction) else {
                    return
                }
                guard let tsMessage: TSMessage = TSMessage.fetch(uniqueId: messageLookup.tsMessageId, transaction: transaction) else { return }
                
                tsMessage.remove(with: transaction)
                storage.removeOpenGroupServerIdLookup(openGroupServerMessageId, in: body.room, on: self.server, using: transaction)
            }
        }
    }
}
