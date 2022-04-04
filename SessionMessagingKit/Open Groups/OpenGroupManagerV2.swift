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
    
    public func hasExistingOpenGroup(room: String, server: String, publicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> Bool {
        guard let serverUrl: URL = URL(string: server) else { return false }
        
        let serverHost: String = (serverUrl.host ?? server)
        let serverPort: String = (serverUrl.port.map { ":\($0)" } ?? "")
        let defaultServerHost: String = OpenGroupAPIV2.defaultServer.substring(from: "http://".count)
        var serverOptions: Set<String> = Set([
            server,
            "\(serverHost)\(serverPort)",
            "http://\(serverHost)\(serverPort)",
            "https://\(serverHost)\(serverPort)"
        ])
        
        if serverHost == OpenGroupAPIV2.legacyDefaultServerDNS {
            let defaultServerOptions: Set<String> = Set([
                defaultServerHost,
                OpenGroupAPIV2.defaultServer,
                "https://\(defaultServerHost)"
            ])
            serverOptions = serverOptions.union(defaultServerOptions)
        }
        else if serverHost == defaultServerHost {
            let legacyServerOptions: Set<String> = Set([
                OpenGroupAPIV2.legacyDefaultServerDNS,
                "http://\(OpenGroupAPIV2.legacyDefaultServerDNS)",
                "https://\(OpenGroupAPIV2.legacyDefaultServerDNS)"
            ])
            serverOptions = serverOptions.union(legacyServerOptions)
        }
        
        // First check if there is no poller for the specified server
        if serverOptions.first(where: { OpenGroupManagerV2.shared.pollers[$0] != nil }) == nil {
            return false
        }
        
        // Then check if there is an existing open group thread
        let hasExistingThread: Bool = serverOptions.contains(where: { serverName in
            let groupId: Data = LKGroupUtilities.getEncodedOpenGroupIDAsData("\(serverName).\(room)")
            
            return (TSGroupThread.fetch(groupId: groupId, transaction: transaction) != nil)
        })
                                                                  
        return hasExistingThread
    }
    
    public func add(room: String, server: String, publicKey: String, using transaction: Any) -> Promise<Void> {
        // If we are currently polling for this server and already have a TSGroupThread for this room the do nothing
        let transaction = transaction as! YapDatabaseReadWriteTransaction

        if hasExistingOpenGroup(room: room, server: server, publicKey: publicKey, using: transaction) {
            SNLog("Ignoring join open group attempt (already joined)")
            return Promise.value(())
        }
        
        let storage = Storage.shared
        // Clear any existing data if needed
        storage.removeLastMessageServerID(for: room, on: server, using: transaction)
        storage.removeLastDeletionServerID(for: room, on: server, using: transaction)
        storage.removeAuthToken(for: room, on: server, using: transaction)
        // Store the public key
        storage.setOpenGroupPublicKey(for: server, to: publicKey, using: transaction)
        let (promise, seal) = Promise<Void>.pending()
        
        transaction.addCompletionQueue(DispatchQueue.global(qos: .userInitiated)) {
            // Get the group info
            OpenGroupAPIV2.getInfo(for: room, on: server).done(on: DispatchQueue.global(qos: .userInitiated)) { info in
                // Create the open group model and the thread
                let openGroup = OpenGroupV2(server: server, room: room, name: info.name, publicKey: publicKey, imageID: info.imageID)
                let groupID = LKGroupUtilities.getEncodedOpenGroupIDAsData(openGroup.id)
                let model = TSGroupModel(title: openGroup.name, memberIds: [ getUserHexEncodedPublicKey() ], image: nil, groupId: groupID, groupType: .openGroup, adminIds: [])
                // Store everything
                storage.write(with: { transaction in
                    let transaction = transaction as! YapDatabaseReadWriteTransaction
                    let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                    thread.shouldBeVisible = true
                    thread.save(with: transaction)
                    storage.setV2OpenGroup(openGroup, for: thread.uniqueId!, using: transaction)
                }, completion: {
                    // Start the poller if needed
                    if OpenGroupManagerV2.shared.pollers[server] == nil {
                        let poller = OpenGroupPollerV2(for: server)
                        poller.startIfNeeded()
                        OpenGroupManagerV2.shared.pollers[server] = poller
                    }
                    // Fetch the group image
                    OpenGroupAPIV2.getGroupImage(for: room, on: server).done(on: DispatchQueue.global(qos: .userInitiated)) { data in
                        storage.write { transaction in
                            // Update the thread
                            let transaction = transaction as! YapDatabaseReadWriteTransaction
                            let thread = TSGroupThread.getOrCreateThread(with: model, transaction: transaction)
                            thread.groupModel.groupImage = UIImage(data: data)
                            thread.save(with: transaction)
                        }
                    }.retainUntilComplete()
                    // Finish
                    seal.fulfill(())
                })
            }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
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
        Storage.shared.removeReceivedMessageTimestamps(messageTimestamps, using: transaction)
        Storage.shared.removeLastMessageServerID(for: openGroup.room, on: openGroup.server, using: transaction)
        Storage.shared.removeLastDeletionServerID(for: openGroup.room, on: openGroup.server, using: transaction)
        let _ = OpenGroupAPIV2.deleteAuthToken(for: openGroup.room, on: openGroup.server)
        Storage.shared.removeOpenGroupPublicKey(for: openGroup.server, using: transaction)
        thread.removeAllThreadInteractions(with: transaction)
        thread.remove(with: transaction)
        Storage.shared.removeV2OpenGroup(for: thread.uniqueId!, using: transaction)
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
        
        // If there is no scheme then the host is included in the path (so handle that case)
        let hostFreePath = (url.host != nil || !url.path.starts(with: host) ? url.path : url.path.substring(from: host.count))
        let updatedPath = (hostFreePath.starts(with: "/r/") ? hostFreePath.substring(from: 2) : hostFreePath)
        let room = String(updatedPath.dropFirst()) // Drop the leading slash
        let queryParts = query.split(separator: "=")
        guard !room.isEmpty && !room.contains("/"), queryParts.count == 2, queryParts[0] == "public_key" else { return nil }
        let publicKey = String(queryParts[1])
        guard publicKey.count == 64 && Hex.isValid(publicKey) else { return nil }
        var server = (useTLS ? "https://" : "http://") + host
        if let port = url.port { server += ":\(port)" }
        return (room: room, server: server, publicKey: publicKey)
    }
}
