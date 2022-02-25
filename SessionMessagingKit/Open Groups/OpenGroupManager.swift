import PromiseKit
import Sodium
import SessionUtilitiesKit

@objc(SNOpenGroupManager)
public final class OpenGroupManager: NSObject {
    @objc public static let shared = OpenGroupManager()
    
    private var pollers: [String: OpenGroupAPI.Poller] = [:] // One for each server
    private var isPolling = false
    
    // MARK: - Cache
    
    public static var defaultRoomsPromise: Promise<[OpenGroupAPI.Room]>?
    private static var groupImagePromises: [String: Promise<Data>] = [:]
    private static var moderators: [String: [String: Set<String>]] = [:] // Server URL to room ID to set of moderator IDs
    private static var admins: [String: [String: Set<String>]] = [:] // Server URL to room ID to set of admin IDs

    // MARK: - Polling
    
    @objc public func startPolling() {
        guard !isPolling else { return }
        
        isPolling = true
        pollers = Set(Storage.shared.getAllOpenGroups().values.map { $0.server })
            .reduce(into: [:]) { prev, server in
                pollers[server]?.stop() // Should never occur
                
                let poller = OpenGroupAPI.Poller(for: server)
                poller.startIfNeeded()
                
                prev[server] = poller
            }
    }

    @objc public func stopPolling() {
        pollers.forEach { (_, openGroupPoller) in openGroupPoller.stop() }
        pollers.removeAll()
    }

    // MARK: - Adding & Removing
    
    public func add(roomToken: String, server: String, publicKey: String, using transaction: Any) -> Promise<Void> {
        let storage = Storage.shared
        
        // Clear any existing data if needed
        storage.removeOpenGroupSequenceNumber(for: roomToken, on: server, using: transaction)
        storage.removeAuthToken(for: roomToken, on: server, using: transaction)
        
        // Store the public key
        storage.setOpenGroupPublicKey(for: server, to: publicKey, using: transaction)
        
        let (promise, seal) = Promise<Void>.pending()
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        
        transaction.addCompletionQueue(DispatchQueue.global(qos: .userInitiated)) {
            OpenGroupAPI.room(for: roomToken, on: server)
                .done(on: DispatchQueue.global(qos: .userInitiated)) { _, room in
                    OpenGroupManager.handleRoom(
                        room,
                        publicKey: publicKey,
                        for: roomToken,
                        on: server
                    ) {
                        seal.fulfill(())
                    }
                }
                .catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                    seal.reject(error)
                }
        }
        
        return promise
    }

    public func delete(_ openGroup: OpenGroup, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        let storage = SNMessagingKitConfiguration.shared.storage
        
        // Stop the poller if needed
        let openGroups = storage.getAllOpenGroups().values.filter { $0.server == openGroup.server }
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
        let _ = OpenGroupAPI.legacyDeleteAuthToken(for: openGroup.room, on: openGroup.server)
        Storage.shared.removeOpenGroupSequenceNumber(for: openGroup.room, on: openGroup.server, using: transaction)
        
        thread.removeAllThreadInteractions(with: transaction)
        thread.remove(with: transaction)
        Storage.shared.removeOpenGroup(for: thread.uniqueId!, using: transaction)
        
        // Only remove the open group public key if the user isn't in any other rooms 
        if openGroups.count <= 1 {
            Storage.shared.removeOpenGroupPublicKey(for: openGroup.server, using: transaction)
        }
    }
    
    // MARK: - Response Processing
    
    internal static func handleCapabilities(
        _ capabilities: OpenGroupAPI.Capabilities,
        on server: String,
        using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()
    ) {
        dependencies.storage.write { transaction in
            let updatedServer: OpenGroupAPI.Server = OpenGroupAPI.Server(
                name: server,
                capabilities: capabilities
            )
            
            dependencies.storage.storeOpenGroupServer(updatedServer, using: transaction)
        }
    }
    
    internal static func handleMessages(
        _ messages: [OpenGroupAPI.Message],
        for roomToken: String,
        on server: String,
        isBackgroundPoll: Bool,
        using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()
    ) {
        // Sorting the messages by server ID before importing them fixes an issue where messages
        // that quote older messages can't find those older messages
        let openGroupID = "\(server).\(roomToken)"
        let sortedMessages: [OpenGroupAPI.Message] = messages
            .sorted { lhs, rhs in lhs.id < rhs.id }
        let seqNo: Int64 = (sortedMessages.map { $0.seqNo }.max() ?? 0)
        
        dependencies.storage.write { transaction in
            var messageServerIDsToRemove: [UInt64] = []
            
            // Update the 'openGroupSequenceNumber' value (Note: SOGS V4 uses the 'seqNo' instead of the 'serverId')
            dependencies.storage.setOpenGroupSequenceNumber(for: roomToken, on: server, to: seqNo, using: transaction)
            
            // Process the messages
            sortedMessages.forEach { message in
                guard let base64EncodedString: String = message.base64EncodedData, let data = Data(base64Encoded: base64EncodedString), let sender: String = message.sender else {
                    // A message with no data has been deleted so add it to the list to remove
                    messageServerIDsToRemove.append(UInt64(message.id))
                    return
                }
                
                // Note: The `posted` value is in seconds but all messages in the database use milliseconds for timestamps
                let envelope = SNProtoEnvelope.builder(type: .sessionMessage, timestamp: UInt64(floor(message.posted * 1000)))
                envelope.setContent(data)
                envelope.setSource(sender)
                
                do {
                    let data = try envelope.buildSerializedData()
                    let (message, proto) = try MessageReceiver.parse(data, openGroupMessageServerID: UInt64(message.id), isRetry: false, using: transaction)
                    try MessageReceiver.handle(message, associatedWithProto: proto, openGroupID: openGroupID, isBackgroundPoll: isBackgroundPoll, using: transaction)
                }
                catch {
                    SNLog("Couldn't receive open group message due to error: \(error).")
                }
            }

            // Handle any deletions that are needed
            guard !messageServerIDsToRemove.isEmpty else { return }
            guard let transaction: YapDatabaseReadWriteTransaction = transaction as? YapDatabaseReadWriteTransaction else { return }
            guard let threadID = dependencies.storage.getThreadID(for: openGroupID), let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction) else {
                return
            }
            
            var messagesToRemove: [TSMessage] = []
            
            thread.enumerateInteractions(with: transaction) { interaction, stop in
                guard let message: TSMessage = interaction as? TSMessage, messageServerIDsToRemove.contains(message.openGroupServerMessageID) else {
                    return
                }
                messagesToRemove.append(message)
            }
            
            messagesToRemove.forEach { $0.remove(with: transaction) }
        }
    }
    
    internal static func handleRoom(
        _ room: OpenGroupAPI.Room,
        publicKey: String,
        for roomToken: String,
        on server: String,
        using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies(),
        completion: (() -> ())? = nil
    ) {
        OpenGroupManager.handlePollInfo(
            OpenGroupAPI.RoomPollInfo(room: room),
            publicKey: publicKey,
            for: roomToken,
            on: server,
            using: dependencies,
            completion: completion
        )
    }
    
    internal static func handlePollInfo(
        _ pollInfo: OpenGroupAPI.RoomPollInfo,
        publicKey maybePublicKey: String?,
        for roomToken: String,
        on server: String,
        using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies(),
        completion: (() -> ())? = nil
    ) {
        // Create the open group model and get or create the thread
        let groupId: Data = LKGroupUtilities.getEncodedOpenGroupIDAsData("\(server).\(roomToken)")
        let userPublicKey: String = getUserHexEncodedPublicKey()
        let initialModel: TSGroupModel = TSGroupModel(
            title: (pollInfo.details?.name ?? ""),
            memberIds: [ userPublicKey ],
            image: nil,
            groupId: groupId,
            groupType: .openGroup,
            adminIds: (pollInfo.details?.admins ?? []),
            moderatorIds: (pollInfo.details?.moderators ?? [])
        )
        var maybeUpdatedModel: TSGroupModel? = nil
        
        // Store/Update everything
        dependencies.storage.write(
            with: { transaction in
                let transaction = transaction as! YapDatabaseReadWriteTransaction
                let thread = TSGroupThread.getOrCreateThread(with: initialModel, transaction: transaction)
                let existingOpenGroup: OpenGroup? = thread.uniqueId.flatMap { uniqueId -> OpenGroup? in
                    dependencies.storage.getOpenGroup(for: uniqueId)
                }

                guard let threadUniqueId: String = thread.uniqueId else { return }
                guard let publicKey: String = (maybePublicKey ?? existingOpenGroup?.publicKey) else { return }
                
                let updatedModel: TSGroupModel = TSGroupModel(
                    title: (pollInfo.details?.name ?? thread.groupModel.groupName),
                    memberIds: Array(Set(thread.groupModel.groupMemberIds).inserting(userPublicKey)),
                    image: thread.groupModel.groupImage,
                    groupId: groupId,
                    groupType: .openGroup,
                    adminIds: (pollInfo.details?.admins ?? thread.groupModel.groupAdminIds),
                    moderatorIds: (pollInfo.details?.moderators ?? thread.groupModel.groupModeratorIds)
                )
                maybeUpdatedModel = updatedModel
                let updatedOpenGroup: OpenGroup = OpenGroup(
                    server: server,
                    room: (pollInfo.token ?? roomToken),
                    publicKey: publicKey,
                    name: (pollInfo.details?.name ?? thread.name()),
                    groupDescription: (pollInfo.details?.description ?? existingOpenGroup?.description),
                    imageID: (pollInfo.details?.imageId.map { "\($0)" } ?? existingOpenGroup?.imageID),
                    infoUpdates: ((pollInfo.details?.infoUpdates ?? existingOpenGroup?.infoUpdates) ?? 0)
                )
                
                // - Thread changes
                thread.shouldBeVisible = true
                thread.groupModel = updatedModel
                thread.save(with: transaction)
                
                // - Open Group changes
                dependencies.storage.setOpenGroup(updatedOpenGroup, for: threadUniqueId, using: transaction)
                
                // - User Count
                dependencies.storage.setUserCount(
                    to: UInt64(pollInfo.activeUsers),
                    forOpenGroupWithID: updatedOpenGroup.id,
                    using: transaction
                )
            },
            completion: {
                // Start the poller if needed
                if OpenGroupManager.shared.pollers[server] == nil {
                    OpenGroupManager.shared.pollers[server] = OpenGroupAPI.Poller(for: server)
                    OpenGroupManager.shared.pollers[server]?.startIfNeeded()
                }
                
                // - Moderators
                if let moderators: [String] = (pollInfo.details?.moderators ?? maybeUpdatedModel?.groupModeratorIds) {
                    OpenGroupManager.moderators[server] = (OpenGroupManager.moderators[server] ?? [:])
                        .setting(roomToken, Set(moderators))
                }
                
                // - Admins
                if let admins: [String] = (pollInfo.details?.admins ?? maybeUpdatedModel?.groupAdminIds) {
                    OpenGroupManager.admins[server] = (OpenGroupManager.admins[server] ?? [:])
                        .setting(roomToken, Set(admins))
                }

                // - Room image (if there is one)
                if let imageId: Int64 = pollInfo.details?.imageId {
                    OpenGroupManager.roomImage(imageId, for: roomToken, on: server)
                        .done(on: DispatchQueue.global(qos: .userInitiated)) { data in
                            dependencies.storage.write { transaction in
                                // Update the thread
                                let transaction = transaction as! YapDatabaseReadWriteTransaction
                                let thread = TSGroupThread.getOrCreateThread(with: initialModel, transaction: transaction)
                                thread.groupModel.groupImage = UIImage(data: data)
                                thread.save(with: transaction)
                            }
                        }
                        .retainUntilComplete()
                }

                // Finish
                completion?()
            }
        )
    }
    
    internal static func handleInbox(
        _ messages: [OpenGroupAPI.DirectMessage],
        on server: String,
        isBackgroundPoll: Bool,
        using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()
    ) {
        // Don't need to do anything if we have no messages (it's a valid case)
        guard !messages.isEmpty else { return }
        guard let serverPublicKey: String = dependencies.storage.getOpenGroupPublicKey(for: server) else {
            SNLog("Couldn't receive inbox message.")
            return
        }
        
        // Sorting the messages by server ID before importing them fixes an issue where messages
        // that quote older messages can't find those older messages
        let sortedMessages: [OpenGroupAPI.DirectMessage] = messages
            .sorted { lhs, rhs in lhs.id < rhs.id }
        let latestMessageId: Int64 = (sortedMessages.last?.id ?? 0)
        
        dependencies.storage.write { transaction in
            // Update the 'latestMessageId' value
            dependencies.storage.setOpenGroupInboxLatestMessageId(for: server, to: latestMessageId, using: transaction)

            // Process the messages
            sortedMessages.forEach { message in
                guard let messageData = Data(base64Encoded: message.base64EncodedMessage) else {
                    SNLog("Couldn't receive inbox message.")
                    return
                }

                // Note: The `posted` value is in seconds but all messages in the database use milliseconds for timestamps
                let envelope = SNProtoEnvelope.builder(type: .sessionMessage, timestamp: UInt64(floor(message.posted * 1000)))
                envelope.setContent(messageData)
                envelope.setSource(message.sender)

                do {
                    let data = try envelope.buildSerializedData()
                    let (message, proto) = try MessageReceiver.parse(data, openGroupMessageServerID: nil, openGroupServerPublicKey: serverPublicKey, isRetry: false, using: transaction)
                    try MessageReceiver.handle(message, associatedWithProto: proto, openGroupID: nil, isBackgroundPoll: isBackgroundPoll, using: transaction)
                }
                catch let error {
                    SNLog("Couldn't receive inbox message due to error: \(error).")
                }
            }
        }
    }
    
    // MARK: - Convenience
    
    /// This method specifies if the given publicKey is a moderator or an admin within a specified Open Group
    @objc(isUserModeratorOrAdmin:forRoom:onServer:)
    public static func isUserModeratorOrAdmin(_ publicKey: String, for room: String, on server: String) -> Bool {
        return isUserModeratorOrAdmin(publicKey, for: room, on: server, using: OpenGroupAPI.Dependencies())
    }
    
    public static func isUserModeratorOrAdmin(_ publicKey: String, for room: String, on server: String, using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()) -> Bool {
        var targetKeys: [String] = [publicKey]
        
        // If we are checking for the current users public key then check for the blinded one as well
        if publicKey == getUserHexEncodedPublicKey() {
            guard let userEdKeyPair: Box.KeyPair = dependencies.storage.getUserED25519KeyPair() else { return false }
            guard let serverPublicKey: String = dependencies.storage.getOpenGroupPublicKey(for: server) else {
                return false
            }
            
            // Add the unblinded key as an option
            targetKeys.append(SessionId(.unblinded, publicKey: userEdKeyPair.publicKey).hexString)
            
            let server: OpenGroupAPI.Server? = dependencies.storage.getOpenGroupServer(name: server)
            
            // Check if the server supports blinded keys, if so then sign using the blinded key
            if server?.capabilities.capabilities.contains(.blind) == true {
                guard let blindedKeyPair: Box.KeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: serverPublicKey, edKeyPair: userEdKeyPair, genericHash: dependencies.genericHash) else {
                    return false
                }
    
                // Add the blinded key as an option
                targetKeys.append(SessionId(.blinded, publicKey: blindedKeyPair.publicKey).hexString)
            }
        }
        
        return (
            (OpenGroupManager.moderators[server]?[room]?.contains(where: { key in targetKeys.contains(key) }) ?? false) ||
            (OpenGroupManager.admins[server]?[room]?.contains(where: { key in targetKeys.contains(key) }) ?? false)
        )
    }
    
    public static func getDefaultRoomsIfNeeded(using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()) {
        // Note: If we already have a 'defaultRoomsPromise' then there is no need to get it again
        guard OpenGroupManager.defaultRoomsPromise == nil else { return }
        
        dependencies.storage.write(
            with: { transaction in
                dependencies.storage.setOpenGroupPublicKey(
                    for: OpenGroupAPI.defaultServer,
                    to: OpenGroupAPI.defaultServerPublicKey,
                    using: transaction
                )
            },
            completion: {
                OpenGroupManager.defaultRoomsPromise = attempt(maxRetryCount: 8, recoveringOn: DispatchQueue.main) {
                    OpenGroupAPI.rooms(for: OpenGroupAPI.defaultServer, using: dependencies)
                        .map { _, data in data }
                }
                OpenGroupManager.defaultRoomsPromise?
                    .done(on: OpenGroupAPI.workQueue) { items in
                        items
                            .compactMap { room -> (Int64, String)? in
                                guard let imageId: Int64 = room.imageId else { return nil}
                                
                                return (imageId, room.token)
                            }
                            .forEach { imageId, roomToken in
                                roomImage(imageId, for: roomToken, on: OpenGroupAPI.defaultServer, using: dependencies)
                                    .retainUntilComplete()
                            }
                    }
                    .catch(on: OpenGroupAPI.workQueue) { _ in
                        OpenGroupManager.defaultRoomsPromise = nil
                    }
            }
        )
    }
    
    public static func roomImage(
        _ fileId: Int64,
        for roomToken: String,
        on server: String,
        using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()
    ) -> Promise<Data> {
        // Normally the image for a given group is stored with the group thread, so it's only
        // fetched once. However, on the join open group screen we show images for groups the
        // user * hasn't * joined yet. We don't want to re-fetch these images every time the
        // user opens the app because that could slow the app down or be data-intensive. So
        // instead we assume that these images don't change that often and just fetch them once
        // a week. We also assume that they're all fetched at the same time as well, so that
        // we only need to maintain one date in user defaults. On top of all of this we also
        // don't double up on fetch requests by storing the existing request as a promise if
        // there is one.
        let lastOpenGroupImageUpdate: Date? = UserDefaults.standard[.lastOpenGroupImageUpdate]
        let now: Date = dependencies.date
        let timeSinceLastUpdate: TimeInterval = (lastOpenGroupImageUpdate.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude)
        let updateInterval: TimeInterval = (7 * 24 * 60 * 60)
        
        if let data = dependencies.storage.getOpenGroupImage(for: roomToken, on: server), server == OpenGroupAPI.defaultServer, timeSinceLastUpdate < updateInterval {
            return Promise.value(data)
        }
        
        if let promise = OpenGroupManager.groupImagePromises["\(server).\(roomToken)"] {
            return promise
        }
        
        let promise: Promise<Data> = OpenGroupAPI
            .downloadFile(fileId, from: roomToken, on: server, using: dependencies)
            .map { _, data in data }
        _ = promise.done(on: OpenGroupAPI.workQueue) { imageData in
            if server == OpenGroupAPI.defaultServer {
                dependencies.storage.write { transaction in
                    dependencies.storage.setOpenGroupImage(to: imageData, for: roomToken, on: server, using: transaction)
                }
                UserDefaults.standard[.lastOpenGroupImageUpdate] = now
            }
        }
        OpenGroupManager.groupImagePromises["\(server).\(roomToken)"] = promise
        
        return promise
    }
    
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

extension OpenGroupManager {
    @objc(getDefaultRoomsIfNeeded)
    public static func objc_getDefaultRoomsIfNeeded() {
        return getDefaultRoomsIfNeeded()
    }
}
