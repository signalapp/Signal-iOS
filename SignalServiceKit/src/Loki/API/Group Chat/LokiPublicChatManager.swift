import PromiseKit

@objc(LKPublicChatManager)
public final class LokiPublicChatManager: NSObject {
    
    // MARK: Error
    public enum Error : Swift.Error {
        case userPublicKeyNotFound
    }
    
    @objc public static let shared = LokiPublicChatManager()
    
    private var chats: [String: LokiGroupChat] = [:]
    private var pollers: [String: LokiGroupChatPoller] = [:]
    private var isPolling = false
    
    private let storage = OWSPrimaryStorage.shared()
    private var ourHexEncodedPublicKey: String? { return OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey }
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(onThreadDeleted(_:)), name: .threadDeleted, object: nil)
        refreshChatsAndPollers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc public func startPollersIfNeeded() {
        for (threadID, groupChat) in chats {
            if let poller = pollers[threadID] {
                poller.startIfNeeded()
            } else {
                let poller = LokiGroupChatPoller(for: groupChat)
                poller.startIfNeeded()
                pollers[threadID] = poller
            }
        }
        isPolling = true
    }
    
    @objc public func stopPollers() {
        for poller in pollers.values { poller.stop() }
        isPolling = false
    }
    
    public func addChat(server: String, channel: UInt64) -> Promise<LokiGroupChat> {
        if let existingChat = getChat(server: server, channel: channel) {
            return Promise.value(self.addChat(server: server, channel: channel, name: existingChat.displayName))
        }
        
        return LokiGroupChatAPI.getAuthToken(for: server).then { token in
            return LokiGroupChatAPI.getChannelInfo(channel, on: server)
        }.map { channelInfo -> LokiGroupChat in
            return self.addChat(server: server, channel: channel, name: channelInfo.name)
        }
    }
    
    @discardableResult
    @objc(addChatWithServer:channel:name:)
    public func addChat(server: String, channel: UInt64, name: String) -> LokiGroupChat {
        let chat = LokiGroupChat(channel: channel, server: server, displayName: name, isDeletable: true)
        let model = TSGroupModel(title: chat.displayName, memberIds: [ourHexEncodedPublicKey!, chat.server], image: nil, groupId: chat.idAsData!)
        
        // Store the group chat mapping
        self.storage.dbReadWriteConnection.readWrite { transaction in
            let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
            
            // Mute the thread
            if let utc = TimeZone(identifier: "UTC") {
                var calendar = Calendar.current
               calendar.timeZone = utc
               var dateComponents = DateComponents()
               dateComponents.setValue(999, for: .year)
                if let date = calendar.date(byAdding: dateComponents, to: Date()) {
                    thread.updateWithMuted(until: date, transaction: transaction)
                }
            }
           
            // Save the group chat
            self.storage.setGroupChat(chat, for: thread.uniqueId!, in: transaction)
        }
        
        // Update chats and pollers
        self.refreshChatsAndPollers()
        
        return chat
    }
    
    @objc(addChatWithServer:channel:)
    public func objc_addChat(server: String, channel: UInt64) -> AnyPromise {
        return AnyPromise.from(addChat(server: server, channel: channel))
    }
    
    private func refreshChatsAndPollers() {
        storage.dbReadConnection.read { transaction in
            let newChats = self.storage.getAllGroupChats(with: transaction)
            
            // Remove any chats that don't exist in the database
            let removedChatThreadIds = self.chats.keys.filter { !newChats.keys.contains($0) }
            removedChatThreadIds.forEach { threadID in
                let poller = self.pollers.removeValue(forKey: threadID)
                poller?.stop()
            }
            
            // Only append to chats if we have a thread for the chat
            self.chats = newChats.filter { (threadID, group) in
                return TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) != nil
            }
        }
        
        if (isPolling) { startPollersIfNeeded() }
    }
    
    @objc private func onThreadDeleted(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? String else { return }
        
        // Reset the last message cache
        if let chat = self.chats[threadId] {
            LokiGroupChatAPI.resetLastMessageCache(for: chat.channel, on: chat.server)
        }
        
        // Remove the chat from the db
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.removeGroupChat(for: threadId, in: transaction)
        }

        refreshChatsAndPollers()
    }
    
    private func getChat(server: String, channel: UInt64) -> LokiGroupChat? {
        return chats.values.first { chat in
            return chat.server == server && chat.channel == channel
        }
    }
}
