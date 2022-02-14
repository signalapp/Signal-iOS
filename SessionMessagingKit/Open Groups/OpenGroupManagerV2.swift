import PromiseKit

@objc(SNOpenGroupManagerV2)
public final class OpenGroupManagerV2 : NSObject {
    private var pollers: [String:OpenGroupPollerV2] = [:] // One for each server
    private var isPolling = false

    // MARK: Initialization
    @objc public static let shared = OpenGroupManagerV2()

    private override init() { }

    // MARK: Polling
    @objc public func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        let servers = Set(Storage.shared.getAllV2OpenGroups().values.map { $0.server })
        servers.forEach { server in
            if let poller = pollers[server] { poller.stop() } // Should never occur
            let poller = OpenGroupPollerV2(for: server)
            poller.startIfNeeded()
            pollers[server] = poller
        }
    }

    @objc public func stopPolling() {
        pollers.forEach { (_, openGroupPoller) in openGroupPoller.stop() }
        pollers.removeAll()
    }

    // MARK: Adding & Removing
    public func add(room: String, server: String, publicKey: String, using transaction: Any) -> Promise<Void> {
        let storage = Storage.shared
        // Clear any existing data if needed
        storage.removeLastMessageServerID(for: room, on: server, using: transaction)
        storage.removeLastDeletionServerID(for: room, on: server, using: transaction)
        storage.removeAuthToken(for: room, on: server, using: transaction)
        // Store the public key
        storage.setOpenGroupPublicKey(for: server, to: publicKey, using: transaction)
        let (promise, seal) = Promise<Void>.pending()
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        transaction.addCompletionQueue(DispatchQueue.global(qos: .userInitiated)) {
            // Get the group info
            // TODO: Remove this legacy method
//            OpenGroupAPIV2.legacyGetRoomInfo(for: room, on: server).done(on: DispatchQueue.global(qos: .userInitiated)) { info in
//                // Create the open group model and the thread
//                let openGroup = OpenGroupV2(server: server, room: room, name: info.name, publicKey: publicKey, imageID: info.imageID)
//                let groupID = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
//                let model = TSGroupModel(title: openGroup.name, memberIds: [ getUserHexEncodedPublicKey() ], image: nil, groupId: groupID, groupType: .openGroup, adminIds: [])
//                // Store everything
//                storage.write(with: { transaction in
//                    let transaction = transaction as! YapDatabaseReadWriteTransaction
//                    let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
//                    thread.shouldBeVisible = true
//                    thread.save(with: transaction)
//                    storage.setV2OpenGroup(openGroup, for: thread.uniqueId!, using: transaction)
//                }, completion: {
//                    // Start the poller if needed
//                    if OpenGroupManagerV2.shared.pollers[server] == nil {
//                        let poller = OpenGroupPollerV2(for: server)
//                        poller.startIfNeeded()
//                        OpenGroupManagerV2.shared.pollers[server] = poller
//                    }
//                    // Fetch the group image
//                    OpenGroupAPIV2.legacyGetGroupImage(for: room, on: server).done(on: DispatchQueue.global(qos: .userInitiated)) { data in
//                        storage.write { transaction in
//                            // Update the thread
//                            let transaction = transaction as! YapDatabaseReadWriteTransaction
//                            let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
//                            thread.groupModel.groupImage = UIImage(data: data)
//                            thread.save(with: transaction)
//                        }
//                    }.retainUntilComplete()
//                    // Finish
//                    seal.fulfill(())
//                })
//            }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
//                seal.reject(error)
//            }
            
            OpenGroupAPIV2.room(for: room, on: server)
                .done(on: DispatchQueue.global(qos: .userInitiated)) { _, room in
                    // Create the open group model and the thread
                    let openGroup: OpenGroupV2 = OpenGroupV2(
                        server: server,
                        room: room.token,
                        name: room.name,
                        publicKey: publicKey,
                        imageID: room.imageId.map { "\($0)" }   // TODO: Update this?
                    )

                    let groupID: Data = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
                    let model: TSGroupModel = TSGroupModel(
                        title: openGroup.name,
                        memberIds: [ getUserHexEncodedPublicKey() ],
                        image: nil,
                        groupId: groupID,
                        groupType: .openGroup,
                        adminIds: []    // TODO: This is part of the 'room' object
                    )

                    // Store everything
                    storage.write(
                        with: { transaction in
                            let transaction = transaction as! YapDatabaseReadWriteTransaction
                            let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                            thread.shouldBeVisible = true
                            thread.save(with: transaction)
                            storage.setV2OpenGroup(openGroup, for: thread.uniqueId!, using: transaction)
                        },
                        completion: {
                            // Start the poller if needed
                            if OpenGroupManagerV2.shared.pollers[server] == nil {
                                let poller = OpenGroupPollerV2(for: server)
                                poller.startIfNeeded()
                                OpenGroupManagerV2.shared.pollers[server] = poller
                            }

                            // Fetch the group image (if there is one)
                            // TODO: Need to test this
                            // TODO: Clean this up (can we avoid the if/else with fancy promise wrangling?)
                            if let imageId: Int64 = room.imageId {
                                OpenGroupAPIV2.roomImage(imageId, for: room.token, on: server)
                                    .done(on: DispatchQueue.global(qos: .userInitiated)) { data in
                                        storage.write { transaction in
                                            // Update the thread
                                            let transaction = transaction as! YapDatabaseReadWriteTransaction
                                            let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                                            thread.groupModel.groupImage = UIImage(data: data)
                                            thread.save(with: transaction)
                                        }
                                    }
                                    .retainUntilComplete()
                            }
                            else {
                                storage.write { transaction in
                                    // Update the thread
                                    let transaction = transaction as! YapDatabaseReadWriteTransaction
                                    let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                                    thread.save(with: transaction)
                                }
                            }

                            // Finish
                            seal.fulfill(())
                        }
                    )
                }
                .catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                    seal.reject(error)
                }
        }
        
        return promise
    }

    public func delete(_ openGroup: OpenGroupV2, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        let storage = SNMessagingKitConfiguration.shared.storage
        
        // Stop the poller if needed
        let openGroups = storage.getAllV2OpenGroups().values.filter { $0.server == openGroup.server }
        if openGroups.count == 1 && openGroups.last == openGroup {
            let poller = pollers[openGroup.server]
            poller?.stop()
            pollers[openGroup.server] = nil
        }
        
        // Remove all data
        var messageIDs: Set<String> = []
        var messageTimestamps: Set<UInt64> = []
        thread.enumerateInteractions(with: transaction) { interaction, _ in
            messageIDs.insert(interaction.uniqueId!)
            messageTimestamps.insert(interaction.timestamp)
        }
        storage.updateMessageIDCollectionByPruningMessagesWithIDs(messageIDs, using: transaction)
        Storage.shared.removeReceivedMessageTimestamps(messageTimestamps, using: transaction)
        Storage.shared.removeLastMessageServerID(for: openGroup.room, on: openGroup.server, using: transaction)
        Storage.shared.removeLastDeletionServerID(for: openGroup.room, on: openGroup.server, using: transaction)
        let _ = OpenGroupAPIV2.legacyDeleteAuthToken(for: openGroup.room, on: openGroup.server)
        thread.removeAllThreadInteractions(with: transaction)
        thread.remove(with: transaction)
        Storage.shared.removeV2OpenGroup(for: thread.uniqueId!, using: transaction)
        
        // Only remove the open group public key if the user isn't in any other rooms 
        if openGroups.count <= 1 {
            Storage.shared.removeOpenGroupPublicKey(for: openGroup.server, using: transaction)
        }
    }
    
    // MARK: Convenience
    public static func parseV2OpenGroup(from string: String) -> (room: String, server: String, publicKey: String)? {
        guard let url = URL(string: string), let host = url.host ?? given(string.split(separator: "/").first, { String($0) }), let query = url.query else { return nil }
        // Inputs that should work:
        // https://sessionopengroup.co/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // http://sessionopengroup.co/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // sessionopengroup.co/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c (does NOT go to HTTPS)
        // https://143.198.213.225:443/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // 143.198.213.255:80/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        let useTLS = (url.scheme == "https")
        let room = String(url.path.dropFirst()) // Drop the leading slash
        let queryParts = query.split(separator: "=")
        guard !room.isEmpty && !room.contains("/"), queryParts.count == 2, queryParts[0] == "public_key" else { return nil }
        let publicKey = String(queryParts[1])
        guard publicKey.count == 64 && Hex.isValid(publicKey) else { return nil }
        var server = (useTLS ? "https://" : "http://") + host
        if let port = url.port { server += ":\(port)" }
        return (room: room, server: server, publicKey: publicKey)
    }
}
