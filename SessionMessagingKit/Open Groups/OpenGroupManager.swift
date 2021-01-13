import PromiseKit

@objc(SNOpenGroupManager)
public final class OpenGroupManager : NSObject {
    private var pollers: [String:OpenGroupPoller] = [:]
    private var isPolling = false
    
    // MARK: Error
    public enum Error : LocalizedError {
        case invalidURL

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL."
            }
        }
    }

    // MARK: Initialization
    @objc public static let shared = OpenGroupManager()

    private override init() { }
    
    // MARK: Polling
    @objc public func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        let openGroups = Storage.shared.getAllUserOpenGroups()
        for (_, openGroup) in openGroups {
            if let poller = pollers[openGroup.id] { poller.stop() } // Should never occur
            let poller = OpenGroupPoller(for: openGroup)
            poller.startIfNeeded()
            pollers[openGroup.id] = poller
        }
    }
    
    @objc public func stopPolling() {
        pollers.forEach { (_, openGroupPoller) in openGroupPoller.stop() }
        pollers.removeAll()
    }

    // MARK: Adding & Removing
    public func add(with url: String, using transaction: Any) -> Promise<Void> {
        guard let url = URL(string: url), let scheme = url.scheme, scheme == "https", url.host != nil else {
            return Promise(error: Error.invalidURL)
        }
        let channel: UInt64 = 1
        let server = url.absoluteString
        let userPublicKey = getUserHexEncodedPublicKey()
        let profileManager = SSKEnvironment.shared.profileManager
        let displayName = profileManager.profileNameForRecipient(withID: userPublicKey)
        let profilePictureURL = profileManager.profilePictureURL()
        let profileKey = profileManager.localProfileKey().keyData
        Storage.shared.removeLastMessageServerID(for: channel, on: server, using: transaction)
        Storage.shared.removeLastDeletionServerID(for: channel, on: server, using: transaction)
        return OpenGroupAPI.getInfo(for: channel, on: server).done { info in
            let openGroup = OpenGroup(channel: channel, server: server, displayName: info.displayName, isDeletable: true)!
            let groupID = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
            let model = TSGroupModel(title: openGroup.displayName, memberIds: [ userPublicKey ], image: nil, groupId: groupID, groupType: .openGroup, adminIds: [])
            Storage.shared.write(with: { transaction in
                let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction as! YapDatabaseReadWriteTransaction)
                Storage.shared.setOpenGroup(openGroup, for: thread.uniqueId!, using: transaction)
            }, completion: {
                let _ = OpenGroupAPI.setDisplayName(to: displayName, on: server)
                let _ = OpenGroupAPI.setProfilePictureURL(to: profilePictureURL, using: profileKey, on: server)
                let _ = OpenGroupAPI.join(channel, on: server)
                if let poller = OpenGroupManager.shared.pollers[openGroup.id] {
                    poller.stop()
                    OpenGroupManager.shared.pollers[openGroup.id] = nil
                }
                let poller = OpenGroupPoller(for: openGroup)
                poller.startIfNeeded()
                OpenGroupManager.shared.pollers[openGroup.id] = poller
            })
        }
    }
    
    public func delete(_ openGroup: OpenGroup, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        if let poller = pollers[openGroup.id] {
            poller.stop()
            pollers[openGroup.id] = nil
        }
        var messageIDs: Set<String> = []
        var messageTimestamps: Set<UInt64> = []
        thread.enumerateInteractions(with: transaction) { interaction, _ in
            messageIDs.insert(interaction.uniqueId!)
            messageTimestamps.insert(interaction.timestamp)
        }
        SNMessagingKitConfiguration.shared.storage.updateMessageIDCollectionByPruningMessagesWithIDs(messageIDs, using: transaction)
        Storage.shared.removeReceivedMessageTimestamps(messageTimestamps, using: transaction)
        Storage.shared.removeLastMessageServerID(for: openGroup.channel, on: openGroup.server, using: transaction)
        Storage.shared.removeLastDeletionServerID(for: openGroup.channel, on: openGroup.server, using: transaction)
        let _ = OpenGroupAPI.leave(openGroup.channel, on: openGroup.server)
        Storage.shared.removeOpenGroupPublicKey(for: openGroup.server, using: transaction)
        thread.removeAllThreadInteractions(with: transaction)
        thread.remove(with: transaction)
        Storage.shared.removeOpenGroup(for: thread.uniqueId!, using: transaction)
    }
}
