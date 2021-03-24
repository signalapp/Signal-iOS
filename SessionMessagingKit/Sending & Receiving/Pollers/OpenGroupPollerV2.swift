import PromiseKit

@objc(SNOpenGroupPollerV2)
public final class OpenGroupPollerV2 : NSObject {
    private let openGroup: OpenGroupV2
    private var pollForNewMessagesTimer: Timer? = nil
    private var pollForDeletedMessagesTimer: Timer? = nil
    private var pollForModeratorsTimer: Timer? = nil
    private var hasStarted = false
    private var isPolling = false

    private var isMainAppAndActive: Bool {
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        return isMainAppAndActive
    }

    // MARK: Settings
    private let pollForNewMessagesInterval: TimeInterval = 4
    private let pollForDeletedMessagesInterval: TimeInterval = 30
    private let pollForModeratorsInterval: TimeInterval = 10 * 60

    // MARK: Lifecycle
    public init(for openGroup: OpenGroupV2) {
        self.openGroup = openGroup
        super.init()
    }

    @objc public func startIfNeeded() {
        guard !hasStarted else { return }
        guard isMainAppAndActive else { stop(); return }
        DispatchQueue.main.async { [weak self] in // Timers don't do well on background queues
            guard let strongSelf = self else { return }
            strongSelf.hasStarted = true
            // Create timers
            strongSelf.pollForNewMessagesTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForNewMessagesInterval, repeats: true) { _ in self?.pollForNewMessages() }
            strongSelf.pollForDeletedMessagesTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForDeletedMessagesInterval, repeats: true) { _ in self?.pollForDeletedMessages() }
            strongSelf.pollForModeratorsTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.pollForModeratorsInterval, repeats: true) { _ in self?.pollForModerators() }
            // Perform initial updates
            strongSelf.pollForNewMessages()
            strongSelf.pollForDeletedMessages()
            strongSelf.pollForModerators()
        }
    }

    @objc public func stop() {
        pollForNewMessagesTimer?.invalidate()
        pollForDeletedMessagesTimer?.invalidate()
        pollForModeratorsTimer?.invalidate()
        hasStarted = false
    }

    // MARK: Polling
    @discardableResult
    public func pollForNewMessages() -> Promise<Void> {
        guard isMainAppAndActive else { stop(); return Promise.value(()) }
        return pollForNewMessages(isBackgroundPoll: false)
    }

    @discardableResult
    public func pollForNewMessages(isBackgroundPoll: Bool) -> Promise<Void> {
        guard !self.isPolling else { return Promise.value(()) }
        self.isPolling = true
        let openGroup = self.openGroup
        let (promise, seal) = Promise<Void>.pending()
        promise.retainUntilComplete()
        OpenGroupAPIV2.getMessages(for: openGroup.room, on: openGroup.server).done(on: DispatchQueue.global(qos: .default)) { [weak self] messages in
            guard let self = self else { return }
            self.isPolling = false
            // Sorting the messages by server ID before importing them fixes an issue where messages that quote older messages can't find those older messages
            let messages = messages.sorted { $0.serverID! < $1.serverID! } // Safe because messages with a nil serverID are filtered out
            messages.forEach { message in
                guard let data = Data(base64Encoded: message.base64EncodedData) else {
                    return SNLog("Ignoring open group message with invalid encoding.")
                }
                let job = MessageReceiveJob(data: data, openGroupMessageServerID: UInt64(message.serverID!), openGroupID: self.openGroup.id, isBackgroundPoll: isBackgroundPoll)
                SNMessagingKitConfiguration.shared.storage.write { transaction in
                    SessionMessagingKit.JobQueue.shared.add(job, using: transaction)
                }
            }
        }.catch(on: DispatchQueue.global(qos: .userInitiated)) { _ in
            seal.fulfill(()) // The promise is just used to keep track of when we're done
        }.retainUntilComplete()
        return promise
    }

    private func pollForDeletedMessages() {
        let openGroup = self.openGroup
        OpenGroupAPIV2.getDeletedMessages(for: openGroup.room, on: openGroup.server).done(on: DispatchQueue.global(qos: .default)) { serverIDs in
            let messageIDs = serverIDs.compactMap { Storage.shared.getIDForMessage(withServerID: UInt64($0)) }
            SNMessagingKitConfiguration.shared.storage.write { transaction in
                let transaction = transaction as! YapDatabaseReadWriteTransaction
                messageIDs.forEach { messageID in
                    TSMessage.fetch(uniqueId: messageID, transaction: transaction)?.remove(with: transaction)
                }
            }
        }.retainUntilComplete()
    }

    private func pollForModerators() {
        OpenGroupAPIV2.getModerators(for: openGroup.room, on: openGroup.server).retainUntilComplete()
    }
}
