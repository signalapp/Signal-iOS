import PromiseKit

// TODO: Clean

@objc(LKPublicChatManager)
public final class PublicChatManager : NSObject {
    private let storage = OWSPrimaryStorage.shared()
    @objc public var chats: [String:PublicChat] = [:]
    private var pollers: [String:PublicChatPoller] = [:]
    private var isPolling = false
    
    private var userHexEncodedPublicKey: String? {
        return OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey
    }
    
    public enum Error : Swift.Error {
        case chatCreationFailed
        case userPublicKeyNotFound
    }
    
    @objc public static let shared = PublicChatManager()
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(onThreadDeleted(_:)), name: .threadDeleted, object: nil)
        refreshChatsAndPollers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc public func startPollersIfNeeded() {
        for (threadID, publicChat) in chats {
            if let poller = pollers[threadID] {
                poller.startIfNeeded()
            } else {
                let poller = PublicChatPoller(for: publicChat)
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
    
    public func addChat(server: String, channel: UInt64) -> Promise<PublicChat> {
        if let existingChat = getChat(server: server, channel: channel) {
            if let newChat = self.addChat(server: server, channel: channel, name: existingChat.displayName) {
                return Promise.value(newChat)
            } else {
                return Promise(error: Error.chatCreationFailed)
            }
        }
        return PublicChatAPI.getAuthToken(for: server).then2 { token in
            return PublicChatAPI.getInfo(for: channel, on: server)
        }.map2 { channelInfo -> PublicChat in
            guard let chat = self.addChat(server: server, channel: channel, name: channelInfo.displayName) else { throw Error.chatCreationFailed }
            return chat
        }
    }
    
    @discardableResult
    @objc(addChatWithServer:channel:name:)
    public func addChat(server: String, channel: UInt64, name: String) -> PublicChat? {
        guard let chat = PublicChat(channel: channel, server: server, displayName: name, isDeletable: true) else { return nil }
        let model = TSGroupModel(title: chat.displayName, memberIds: [userHexEncodedPublicKey!, chat.server], image: nil, groupId: LKGroupUtilities.getEncodedOpenGroupIDAsData(chat.id), groupType: .openGroup, adminIds: [])
        
        // Store the group chat mapping
        try! Storage.writeSync { transaction in
            let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
           
            // Save the group chat
            LokiDatabaseUtilities.setPublicChat(chat, for: thread.uniqueId!, in: transaction)
        }
        
        // Update chats and pollers
        self.refreshChatsAndPollers()
        
        return chat
    }
    
    @objc(addChatWithServer:channel:)
    public func objc_addChat(server: String, channel: UInt64) -> AnyPromise {
        return AnyPromise.from(addChat(server: server, channel: channel))
    }
    
    @objc func refreshChatsAndPollers() {
        storage.dbReadConnection.read { transaction in
            let newChats = LokiDatabaseUtilities.getAllPublicChats(in: transaction)
            
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
            PublicChatAPI.clearCaches(for: chat.channel, on: chat.server)
        }
        
        // Remove the chat from the db
        try! Storage.writeSync { transaction in
            LokiDatabaseUtilities.removePublicChat(for: threadId, in: transaction)
        }

        refreshChatsAndPollers()
    }
    
    public func getChat(server: String, channel: UInt64) -> PublicChat? {
        return chats.values.first { chat in
            return chat.server == server && chat.channel == channel
        }
    }
}
