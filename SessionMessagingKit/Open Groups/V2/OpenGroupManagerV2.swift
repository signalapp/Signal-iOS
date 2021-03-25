import PromiseKit

@objc(SNOpenGroupManagerV2)
public final class OpenGroupManagerV2 : NSObject {
    private var pollers: [String:OpenGroupPollerV2] = [:]
    private var isPolling = false

    // MARK: Initialization
    @objc public static let shared = OpenGroupManagerV2()

    private override init() { }

    // MARK: Polling
    @objc public func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        let openGroups = Storage.shared.getAllV2OpenGroups()
        for (_, openGroup) in openGroups {
            if let poller = pollers[openGroup.id] { poller.stop() } // Should never occur
            let poller = OpenGroupPollerV2(for: openGroup)
            poller.startIfNeeded()
            pollers[openGroup.id] = poller
        }
    }

    @objc public func stopPolling() {
        pollers.forEach { (_, openGroupPoller) in openGroupPoller.stop() }
        pollers.removeAll()
    }

    // MARK: Adding & Removing
    public func add(room: String, server: String, publicKey: String, using transaction: Any) -> Promise<Void> {
        let storage = Storage.shared
        storage.removeLastMessageServerID(for: room, on: server, using: transaction)
        storage.removeLastDeletionServerID(for: room, on: server, using: transaction)
        storage.setOpenGroupPublicKey(for: server, to: publicKey, using: transaction)
        let (promise, seal) = Promise<Void>.pending()
        OpenGroupAPIV2.getInfo(for: room, on: server).done(on: DispatchQueue.global(qos: .default)) { info in
            let openGroup = OpenGroupV2(server: server, room: room, name: info.name, imageID: info.imageID)
            let groupID = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
            let model = TSGroupModel(title: openGroup.name, memberIds: [ getUserHexEncodedPublicKey() ], image: nil, groupId: groupID, groupType: .openGroup, adminIds: [])
            storage.write(with: { transaction in
                let transaction = transaction as! YapDatabaseReadWriteTransaction
                let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                thread.shouldThreadBeVisible = true
                thread.save(with: transaction)
                storage.setV2OpenGroup(openGroup, for: thread.uniqueId!, using: transaction)
            }, completion: {
                if let poller = OpenGroupManagerV2.shared.pollers[openGroup.id] {
                    poller.stop()
                    OpenGroupManagerV2.shared.pollers[openGroup.id] = nil
                }
                let poller = OpenGroupPollerV2(for: openGroup)
                poller.startIfNeeded()
                OpenGroupManagerV2.shared.pollers[openGroup.id] = poller
                seal.fulfill(())
            })
        }.catch(on: DispatchQueue.global(qos: .default)) { error in
            seal.reject(error)
        }
        return promise
    }

    public func delete(_ openGroup: OpenGroupV2, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
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
        Storage.shared.removeLastMessageServerID(for: openGroup.room, on: openGroup.server, using: transaction)
        Storage.shared.removeLastDeletionServerID(for: openGroup.room, on: openGroup.server, using: transaction)
        let _ = OpenGroupAPIV2.deleteAuthToken(for: openGroup.room, on: openGroup.server)
        Storage.shared.removeOpenGroupPublicKey(for: openGroup.server, using: transaction)
        thread.removeAllThreadInteractions(with: transaction)
        thread.remove(with: transaction)
        Storage.shared.removeV2OpenGroup(for: thread.uniqueId!, using: transaction)
    }
}
