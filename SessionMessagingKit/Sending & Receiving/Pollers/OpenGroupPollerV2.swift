import PromiseKit
import SessionSnodeKit

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
        DispatchQueue.main.async { [weak self] in // Timers don't do well on background queues
            guard let strongSelf = self else { return }
            strongSelf.hasStarted = true
            strongSelf.timer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollInterval, repeats: true) { _ in
                self?.poll().retainUntilComplete()
            }
            strongSelf.poll().retainUntilComplete()
        }
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
        
        OpenGroupAPIV2.poll(server)
            .done(on: OpenGroupAPIV2.workQueue) { [weak self] response in
                self?.isPolling = false
                self?.handlePollResponse(response, isBackgroundPoll: isBackgroundPoll)
                seal.fulfill(())
            }
            .catch(on: OpenGroupAPIV2.workQueue) { [weak self] error in
                SNLog("Open group polling failed due to error: \(error).")
                self?.isPolling = false
                seal.fulfill(()) // The promise is just used to keep track of when we're done
            }
        
        return promise
    }
    
    private func handlePollResponse(_ response: [Endpoint: (info: OnionRequestResponseInfoType, data: Codable)], isBackgroundPoll: Bool) {
        let storage = SNMessagingKitConfiguration.shared.storage
        
        response.forEach { endpoint, response in
            switch endpoint {
                case .roomMessagesRecent(let roomToken), .roomMessagesBefore(let roomToken, _), .roomMessagesSince(let roomToken, _):
                    guard let responseData: [OpenGroupAPIV2.Message] = response.data as? [OpenGroupAPIV2.Message] else {
                        //SNLog("Open group polling failed due to error: \(error).")
                        return  // TODO: Throw error?
                    }
                    
                    handleMessages(responseData, roomToken: roomToken, isBackgroundPoll: isBackgroundPoll, using: storage)
                    
                case .roomPollInfo(let roomToken, _):
                    guard let responseData: OpenGroupAPIV2.RoomPollInfo = response.data as? OpenGroupAPIV2.RoomPollInfo else {
                        //SNLog("Open group polling failed due to error: \(error).")
                        return  // TODO: Throw error?
                    }
                    
                    handlePollInfo(responseData, roomToken: roomToken, isBackgroundPoll: isBackgroundPoll, using: storage)
                    
                default: break // No custom handling needed
            }
        }
    }
    
    // MARK: - Custom response handling
    // TODO: Shift this logic to the OpenGroupManagerV2? (seems like the place it should belong?)
    
    private func handleMessages(_ messages: [OpenGroupAPIV2.Message], roomToken: String, isBackgroundPoll: Bool, using storage: SessionMessagingKitStorageProtocol) {
        // Sorting the messages by server ID before importing them fixes an issue where messages that quote older messages can't find those older messages
        let openGroupID = "\(server).\(roomToken)"
        let sortedMessages: [OpenGroupAPIV2.Message] = messages
            .sorted { lhs, rhs in lhs.seqNo < rhs.seqNo }
        
        storage.write { transaction in
            var messageServerIDsToRemove: [UInt64] = []
            
            sortedMessages.forEach { message in
                guard let base64EncodedString: String = message.base64EncodedData, let data = Data(base64Encoded: base64EncodedString), let sender: String = message.sender else {
                    // A message with no data has been deleted so add it to the list to remove
                    messageServerIDsToRemove.append(UInt64(message.seqNo))
                    return
                }
                
                let envelope = SNProtoEnvelope.builder(type: .sessionMessage, timestamp: UInt64(floor(message.posted)))
                envelope.setContent(data)
                envelope.setSource(sender)
                
                do {
                    let data = try envelope.buildSerializedData()
                    let (message, proto) = try MessageReceiver.parse(data, openGroupMessageServerID: UInt64(message.seqNo), isRetry: false, using: transaction)
                    try MessageReceiver.handle(message, associatedWithProto: proto, openGroupID: openGroupID, isBackgroundPoll: isBackgroundPoll, using: transaction)
                }
                catch {
                    SNLog("Couldn't receive open group message due to error: \(error).")
                }
            }

            // Handle any deletions that are needed
            guard !messageServerIDsToRemove.isEmpty else { return }
            guard let transaction: YapDatabaseReadWriteTransaction = transaction as? YapDatabaseReadWriteTransaction else { return }
            guard let threadID = storage.v2GetThreadID(for: openGroupID), let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
                return
            }
            
            var messagesToRemove: [TSMessage] = []
            
            thread.enumerateInteractions(with: transaction) { interaction, stop in
                guard let message: TSMessage = interaction as? TSMessage, messageServerIDsToRemove.contains(message.openGroupServerMessageID) else { return }
                messagesToRemove.append(message)
            }
            
            messagesToRemove.forEach { $0.remove(with: transaction) }
        }
    }
    
    private func handlePollInfo(_ pollInfo: OpenGroupAPIV2.RoomPollInfo, roomToken: String, isBackgroundPoll: Bool, using storage: SessionMessagingKitStorageProtocol) {
        // TODO: Handle other properties???
        
        // - Moderators
        OpenGroupAPIV2.moderators[server] = (OpenGroupAPIV2.moderators[server] ?? [:])
            .setting(roomToken, Set(pollInfo.moderators ?? []))

    }
    
    // MARK: - Legacy Handling

    private func handleCompactPollBody(_ body: OpenGroupAPIV2.LegacyCompactPollResponse.Result, isBackgroundPoll: Bool) {
        let storage = SNMessagingKitConfiguration.shared.storage
        // - Messages
        // Sorting the messages by server ID before importing them fixes an issue where messages that quote older messages can't find those older messages
        let openGroupID = "\(server).\(body.room)"
        let messages = (body.messages ?? []).sorted { ($0.serverID ?? 0) < ($1.serverID ?? 0) }
        
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
            x[body.room] = Set(body.moderators ?? [])
            OpenGroupAPIV2.moderators[server] = x
        }
        else {
            OpenGroupAPIV2.moderators[server] = [ body.room : Set(body.moderators ?? []) ]
        }
        
        // - Deletions
        let deletedMessageServerIDs = Set((body.deletions ?? []).map { UInt64($0.deletedMessageID) })
        storage.write { transaction in
            let transaction = transaction as! YapDatabaseReadWriteTransaction
            guard let threadID = storage.v2GetThreadID(for: openGroupID),
                let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else { return }
            var messagesToRemove: [TSMessage] = []
            
            thread.enumerateInteractions(with: transaction) { interaction, stop in
                guard let message = interaction as? TSMessage, deletedMessageServerIDs.contains(message.openGroupServerMessageID) else { return }
                messagesToRemove.append(message)
            }
            
            messagesToRemove.forEach { $0.remove(with: transaction) }
        }
    }
}
