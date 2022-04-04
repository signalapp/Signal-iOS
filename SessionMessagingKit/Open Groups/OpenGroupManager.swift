import PromiseKit
import Sodium
import SessionUtilitiesKit
import SessionSnodeKit

// MARK: - OGMCacheType

public protocol OGMCacheType {
    var defaultRoomsPromise: Promise<[OpenGroupAPI.Room]>? { get set }
    var groupImagePromises: [String: Promise<Data>] { get set }
    
    var pollers: [String: OpenGroupAPI.Poller] { get set }
    var isPolling: Bool { get set }
    
    var moderators: [String: [String: Set<String>]] { get set }
    var admins: [String: [String: Set<String>]] { get set }
    
    var hasPerformedInitialPoll: [String: Bool] { get set }
    var timeSinceLastPoll: [String: TimeInterval] { get set }
    
    func getTimeSinceLastOpen(using dependencies: Dependencies) -> TimeInterval
}

// MARK: - OpenGroupManager

@objc(SNOpenGroupManager)
public final class OpenGroupManager: NSObject {
    // MARK: - Cache
    
    public class Cache: OGMCacheType {
        public var defaultRoomsPromise: Promise<[OpenGroupAPI.Room]>?
        public var groupImagePromises: [String: Promise<Data>] = [:]
        
        public var pollers: [String: OpenGroupAPI.Poller] = [:] // One for each server
        public var isPolling: Bool = false
        
        /// Server URL to room ID to set of user IDs
        public var moderators: [String: [String: Set<String>]] = [:]
        public var admins: [String: [String: Set<String>]] = [:]
        
        /// Server URL to value
        public var hasPerformedInitialPoll: [String: Bool] = [:]
        public var timeSinceLastPoll: [String: TimeInterval] = [:]

        fileprivate var _timeSinceLastOpen: TimeInterval?
        public func getTimeSinceLastOpen(using dependencies: Dependencies) -> TimeInterval {
            if let storedTimeSinceLastOpen: TimeInterval = _timeSinceLastOpen {
                return storedTimeSinceLastOpen
            }
            
            guard let lastOpen: Date = dependencies.standardUserDefaults[.lastOpen] else {
                _timeSinceLastOpen = .greatestFiniteMagnitude
                return .greatestFiniteMagnitude
            }
            
            _timeSinceLastOpen = dependencies.date.timeIntervalSince(lastOpen)
            return dependencies.date.timeIntervalSince(lastOpen)
        }
    }
    
    // MARK: - Variables
    
    @objc public static let shared: OpenGroupManager = OpenGroupManager()
    
    /// Note: This should not be accessed directly but rather via the 'OGMDependencies' type
    fileprivate let mutableCache: Atomic<OGMCacheType> = Atomic(Cache())
    
    // MARK: - Polling

    public func startPolling(using dependencies: OGMDependencies = OGMDependencies()) {
        guard !dependencies.cache.isPolling else { return }
        
        dependencies.mutableCache.mutate { cache in
            cache.isPolling = true
            cache.pollers = Set(dependencies.storage.getAllOpenGroups().values.map { openGroup in openGroup.server })
                .reduce(into: [:]) { prev, server in
                    cache.pollers[server]?.stop() // Should never occur
                    
                    let poller = OpenGroupAPI.Poller(for: server)
                    poller.startIfNeeded(using: dependencies)
                    
                    prev[server] = poller
                }
        }
    }

    public func stopPolling(using dependencies: OGMDependencies = OGMDependencies()) {
        dependencies.mutableCache.mutate {
            $0.pollers.forEach { (_, openGroupPoller) in openGroupPoller.stop() }
            $0.pollers.removeAll()
            $0.isPolling = false
        }
    }

    // MARK: - Adding & Removing
    
    public func hasExistingOpenGroup(roomToken: String, server: String, publicKey: String, using transaction: YapDatabaseReadWriteTransaction, dependencies: OGMDependencies = OGMDependencies()) -> Bool {
        guard let serverUrl: URL = URL(string: server) else { return false }
        
        let serverHost: String = (serverUrl.host ?? server)
        let serverPort: String = (serverUrl.port.map { ":\($0)" } ?? "")
        let defaultServerHost: String = OpenGroupAPI.defaultServer.substring(from: "http://".count)
        var serverOptions: Set<String> = Set([
            server,
            "\(serverHost)\(serverPort)",
            "http://\(serverHost)\(serverPort)",
            "https://\(serverHost)\(serverPort)"
        ])
        
        if serverHost == OpenGroupAPI.legacyDefaultServerDNS {
            let defaultServerOptions: Set<String> = Set([
                defaultServerHost,
                OpenGroupAPI.defaultServer,
                "https://\(defaultServerHost)"
            ])
            serverOptions = serverOptions.union(defaultServerOptions)
        }
        else if serverHost == defaultServerHost {
            let legacyServerOptions: Set<String> = Set([
                OpenGroupAPI.legacyDefaultServerDNS,
                "http://\(OpenGroupAPI.legacyDefaultServerDNS)",
                "https://\(OpenGroupAPI.legacyDefaultServerDNS)"
            ])
            serverOptions = serverOptions.union(legacyServerOptions)
        }
        
        // First check if there is no poller for the specified server
        if serverOptions.first(where: { dependencies.cache.pollers[$0] != nil }) == nil {
            return false
        }
        
        // Then check if there is an existing open group thread
        let hasExistingThread: Bool = serverOptions.contains(where: { serverName in
            let groupId: Data = LKGroupUtilities.getEncodedOpenGroupIDAsData("\(serverName).\(roomToken)")
            
            return (TSGroupThread.fetch(groupId: groupId, transaction: transaction) != nil)
        })
                                                                  
        return hasExistingThread
    }
    
    public func add(roomToken: String, server: String, publicKey: String, isConfigMessage: Bool, using transaction: YapDatabaseReadWriteTransaction, dependencies: OGMDependencies = OGMDependencies()) -> Promise<Void> {
        // If we are currently polling for this server and already have a TSGroupThread for this room the do nothing
        if hasExistingOpenGroup(roomToken: roomToken, server: server, publicKey: publicKey, using: transaction, dependencies: dependencies) {
            SNLog("Ignoring join open group attempt (already joined), user initiated: \(!isConfigMessage)")
            return Promise.value(())
        }
        
        // Clear any existing data if needed
        dependencies.storage.removeOpenGroupSequenceNumber(for: roomToken, on: server, using: transaction)
        
        // Store the public key
        dependencies.storage.setOpenGroupPublicKey(for: server, to: publicKey, using: transaction)
        
        let (promise, seal) = Promise<Void>.pending()
        
        transaction.addCompletionQueue(DispatchQueue.global(qos: .userInitiated)) {
            OpenGroupAPI.capabilitiesAndRoom(for: roomToken, on: server, using: dependencies)
                .done(on: DispatchQueue.global(qos: .userInitiated)) { response in
                    dependencies.storage.write { anyTransaction in
                        guard let transaction: YapDatabaseReadWriteTransaction = anyTransaction as? YapDatabaseReadWriteTransaction else { return }
                        
                        // Store the capabilities first
                        OpenGroupManager.handleCapabilities(
                            response.capabilities.data,
                            on: server,
                            using: transaction,
                            dependencies: dependencies
                        )
                        
                        // Then the room
                        OpenGroupManager.handlePollInfo(
                            OpenGroupAPI.RoomPollInfo(room: response.room.data),
                            publicKey: publicKey,
                            for: roomToken,
                            on: server,
                            using: transaction,
                            dependencies: dependencies
                        ) {
                            seal.fulfill(())
                        }
                    }
                }
                .catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                    SNLog("Failed to join open group.")
                    seal.reject(error)
                }
        }
        
        return promise
    }

    public func delete(_ openGroup: OpenGroup, associatedWith thread: TSThread, using transaction: YapDatabaseReadWriteTransaction, dependencies: OGMDependencies = OGMDependencies()) {
        // Stop the poller if needed
        let openGroups = dependencies.storage.getAllOpenGroups().values.filter { $0.server == openGroup.server }
        if openGroups.count == 1 && openGroups.last == openGroup {
            let poller = dependencies.cache.pollers[openGroup.server]
            poller?.stop()
            dependencies.mutableCache.mutate { $0.pollers[openGroup.server] = nil }
        }
        
        // Remove all data
        var messageIDs: Set<String> = []
        var messageTimestamps: Set<UInt64> = []
        thread.enumerateInteractions(with: transaction) { interaction, _ in
            messageIDs.insert(interaction.uniqueId!)
            messageTimestamps.insert(interaction.timestamp)
        }
        dependencies.storage.removeReceivedMessageTimestamps(messageTimestamps, using: transaction)
        dependencies.storage.removeOpenGroupSequenceNumber(for: openGroup.room, on: openGroup.server, using: transaction)
        
        thread.removeAllThreadInteractions(with: transaction)
        thread.remove(with: transaction)
        dependencies.storage.removeOpenGroup(for: thread.uniqueId!, using: transaction)
        
        // Only remove the open group public key and server info if the user isn't in any other rooms
        if openGroups.count <= 1 {
            dependencies.storage.removeOpenGroupServer(name: openGroup.server, using: transaction)
            dependencies.storage.removeOpenGroupPublicKey(for: openGroup.server, using: transaction)
        }
    }
    
    // MARK: - Response Processing
    
    internal static func handleCapabilities(
        _ capabilities: OpenGroupAPI.Capabilities,
        on server: String,
        using transaction: YapDatabaseReadWriteTransaction,
        dependencies: OGMDependencies = OGMDependencies()
    ) {
        let updatedServer: OpenGroupAPI.Server = OpenGroupAPI.Server(
            name: server,
            capabilities: capabilities
        )
        
        dependencies.storage.setOpenGroupServer(updatedServer, using: transaction)
    }
    
    internal static func handlePollInfo(
        _ pollInfo: OpenGroupAPI.RoomPollInfo,
        publicKey maybePublicKey: String?,
        for roomToken: String,
        on server: String,
        using transaction: YapDatabaseReadWriteTransaction,
        dependencies: OGMDependencies = OGMDependencies(),
        completion: (() -> ())? = nil
    ) {
        // Create the open group model and get or create the thread
        let groupId: Data = LKGroupUtilities.getEncodedOpenGroupIDAsData("\(server).\(roomToken)")
        let userPublicKey: String = getUserHexEncodedPublicKey(using: dependencies)
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
            room: pollInfo.token,
            publicKey: publicKey,
            name: (pollInfo.details?.name ?? thread.name()),
            groupDescription: (pollInfo.details?.roomDescription ?? existingOpenGroup?.groupDescription),
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
        
        transaction.addCompletionQueue(DispatchQueue.global(qos: .userInitiated)) {
            // Start the poller if needed
            if dependencies.cache.pollers[server] == nil {
                dependencies.mutableCache.mutate {
                    $0.pollers[server] = OpenGroupAPI.Poller(for: server)
                    $0.pollers[server]?.startIfNeeded(using: dependencies)
                }
            }
            
            // - Moderators
            if let moderators: [String] = (pollInfo.details?.moderators ?? maybeUpdatedModel?.groupModeratorIds) {
                dependencies.mutableCache.mutate { cache in
                    cache.moderators[server] = (cache.moderators[server] ?? [:]).setting(roomToken, Set(moderators))
                }
            }
            
            // - Admins
            if let admins: [String] = (pollInfo.details?.admins ?? maybeUpdatedModel?.groupAdminIds) {
                dependencies.mutableCache.mutate { cache in
                    cache.admins[server] = (cache.admins[server] ?? [:]).setting(roomToken, Set(admins))
                }
            }

            // - Room image (if there is one and it's different from the existing one, or we don't have the existing one)
            if let imageId: UInt64 = UInt64(updatedOpenGroup.imageID ?? ""), (updatedModel.groupImage == nil || updatedOpenGroup.imageID != existingOpenGroup?.imageID) {
                OpenGroupManager.roomImage(imageId, for: roomToken, on: server, using: dependencies)
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
    }
    
    internal static func handleMessages(
        _ messages: [OpenGroupAPI.Message],
        for roomToken: String,
        on server: String,
        isBackgroundPoll: Bool,
        using transaction: YapDatabaseReadWriteTransaction,
        dependencies: OGMDependencies = OGMDependencies()
    ) {
        // Sorting the messages by server ID before importing them fixes an issue where messages
        // that quote older messages can't find those older messages
        let openGroupID = "\(server).\(roomToken)"
        let sortedMessages: [OpenGroupAPI.Message] = messages
            .sorted { lhs, rhs in lhs.id < rhs.id }
        let seqNo: Int64? = sortedMessages.map { $0.seqNo }.max()
        var messageServerIDsToRemove: [UInt64] = []
        
        // Update the 'openGroupSequenceNumber' value (Note: SOGS V4 uses the 'seqNo' instead of the 'serverId')
        if let seqNo: Int64 = seqNo {
            dependencies.storage.setOpenGroupSequenceNumber(for: roomToken, on: server, to: seqNo, using: transaction)
        }
        
        // Process the messages
        sortedMessages.forEach { message in
            guard let base64EncodedString: String = message.base64EncodedData, let data = Data(base64Encoded: base64EncodedString) else {
                // A message with no data has been deleted so add it to the list to remove
                messageServerIDsToRemove.append(UInt64(message.id))
                return
            }
            guard let sender: String = message.sender else { return }   // Need a sender in order to process the message
            
            // Note: The `posted` value is in seconds but all messages in the database use milliseconds for timestamps
            let envelope = SNProtoEnvelope.builder(type: .sessionMessage, timestamp: UInt64(floor(message.posted * 1000)))
            envelope.setContent(data)
            envelope.setSource(sender)
            
            do {
                let data = try envelope.buildSerializedData()
                let (message, proto) = try MessageReceiver.parse(data, openGroupMessageServerID: UInt64(message.id), isRetry: false, using: transaction, dependencies: dependencies)
                try MessageReceiver.handle(message, associatedWithProto: proto, openGroupID: openGroupID, isBackgroundPoll: isBackgroundPoll, using: transaction, dependencies: dependencies)
            }
            catch {
                SNLog("Couldn't receive open group message due to error: \(error).")
            }
        }

        // Handle any deletions that are needed
        guard !messageServerIDsToRemove.isEmpty else { return }
        
        dependencies.storage.write { transaction in
            guard let transaction: YapDatabaseReadWriteTransaction = transaction as? YapDatabaseReadWriteTransaction else {
                return
            }
            
            messageServerIDsToRemove.forEach { openGroupServerMessageId in
                guard let messageLookup: OpenGroupServerIdLookup = dependencies.storage.getOpenGroupServerIdLookup(openGroupServerMessageId, in: roomToken, on: server, using: transaction) else {
                    return
                }
                guard let tsMessage: TSMessage = TSMessage.fetch(uniqueId: messageLookup.tsMessageId, transaction: transaction) else {
                    return
                }
                
                tsMessage.remove(with: transaction)
                dependencies.storage.removeOpenGroupServerIdLookup(openGroupServerMessageId, in: roomToken, on: server, using: transaction)
            }
        }
    }
    
    internal static func handleDirectMessages(
        _ messages: [OpenGroupAPI.DirectMessage],
        fromOutbox: Bool,
        on server: String,
        isBackgroundPoll: Bool,
        using transaction: YapDatabaseReadWriteTransaction,
        dependencies: OGMDependencies = OGMDependencies()
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
        let latestMessageId: Int64 = sortedMessages[sortedMessages.count - 1].id
        var mappingCache: [String: BlindedIdMapping] = [:]  // Only want this cache to exist for the current loop
        
        // Update the 'latestMessageId' value
        if fromOutbox {
            dependencies.storage.setOpenGroupOutboxLatestMessageId(for: server, to: latestMessageId, using: transaction)
        }
        else {
            dependencies.storage.setOpenGroupInboxLatestMessageId(for: server, to: latestMessageId, using: transaction)
        }

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
                let (receivedMessage, proto) = try MessageReceiver.parse(
                    data,
                    openGroupMessageServerID: nil,
                    openGroupServerPublicKey: serverPublicKey,
                    isOutgoing: fromOutbox,
                    otherBlindedPublicKey: (fromOutbox ? message.recipient : message.sender),
                    isRetry: false,
                    using: transaction,
                    dependencies: dependencies
                )
                
                // If the message was an outgoing message then attempt to unblind the recipient (this will help put
                // messages in the correct thread in case of message request approval race conditions as well as
                // during device sync'ing and restoration)
                if fromOutbox {
                    // Attempt to un-blind the 'message.recipient'
                    let mapping: BlindedIdMapping
                    
                    // Minor optimisation to avoid processing the same sender multiple times in the same
                    // 'handleMessages' call (since the 'mapping' call is done within a transaction we
                    // will never have a mapping come through part-way through processing these messages)
                    if let result: BlindedIdMapping = mappingCache[message.recipient] {
                        mapping = result
                    }
                    else if let result: BlindedIdMapping = ContactUtilities.mapping(for: message.recipient, serverPublicKey: serverPublicKey, using: transaction, dependencies: dependencies) {
                        mapping = result
                    }
                    else {
                        // Cache an "invalid" mapping that has the 'sessionId' set to the recipient so we don't
                        // re-process this recipient if there is another message from them
                        mapping = BlindedIdMapping(
                            blindedId: "",
                            sessionId: message.recipient,
                            serverPublicKey: ""
                        )
                    }
                    
                    switch receivedMessage {
                        case let receivedMessage as VisibleMessage: receivedMessage.syncTarget = mapping.sessionId
                        case let receivedMessage as ExpirationTimerUpdate: receivedMessage.syncTarget = mapping.sessionId
                        default: break
                    }
                    
                    mappingCache[message.recipient] = mapping
                }
                
                try MessageReceiver.handle(receivedMessage, associatedWithProto: proto, openGroupID: nil, isBackgroundPoll: isBackgroundPoll, using: transaction, dependencies: dependencies)
                
                // If this message is from the outbox then we should add the open group details back to the
                // thread just in case this is from a restore (otherwise the user won't be able to send a new
                // message to the target inbox if they are still blinded)
                if fromOutbox, let contactThread: TSContactThread = TSContactThread.fetch(uniqueId: TSContactThread.threadID(fromContactSessionID: message.recipient), transaction: transaction) {
                    contactThread.originalOpenGroupServer = server
                    contactThread.originalOpenGroupPublicKey = serverPublicKey
                    contactThread.save(with: transaction)
                }
            }
            catch let error {
                SNLog("Couldn't receive inbox message due to error: \(error).")
            }
        }
    }
    
    // MARK: - Convenience
    
    /// This method specifies if the given publicKey is a moderator or an admin within a specified Open Group
    public static func isUserModeratorOrAdmin(_ publicKey: String, for room: String, on server: String, using dependencies: OGMDependencies = OGMDependencies()) -> Bool {
        let modAndAdminKeys: Set<String> = (dependencies.cache.moderators[server]?[room] ?? Set())
            .union(dependencies.cache.admins[server]?[room] ?? Set())

        // If the publicKey is in the set then return immediately, otherwise only continue if it's the
        // current user
        guard !modAndAdminKeys.contains(publicKey) else { return true }
        guard let sessionId: SessionId = SessionId(from: publicKey) else { return false }
        
        // Conveniently the logic for these different cases works in order so we can fallthrough each
        // case with only minor efficiency losses
        switch sessionId.prefix {
            case .standard:
                guard publicKey == getUserHexEncodedPublicKey(using: dependencies) else { return false }
                fallthrough
                
            case .unblinded:
                guard let userEdKeyPair: Box.KeyPair = dependencies.storage.getUserED25519KeyPair() else { return false }
                guard sessionId.prefix != .unblinded || publicKey == SessionId(.unblinded, publicKey: userEdKeyPair.publicKey).hexString else {
                    return false
                }
                fallthrough
                
            case .blinded:
                guard let userEdKeyPair: Box.KeyPair = dependencies.storage.getUserED25519KeyPair() else { return false }
                guard let serverPublicKey: String = dependencies.storage.getOpenGroupPublicKey(for: server) else {
                    return false
                }
                guard let blindedKeyPair: Box.KeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: serverPublicKey, edKeyPair: userEdKeyPair, genericHash: dependencies.genericHash) else {
                    return false
                }
                guard sessionId.prefix != .blinded || publicKey == SessionId(.blinded, publicKey: blindedKeyPair.publicKey).hexString else {
                    return false
                }
                
                // If we got to here that means that the 'publicKey' value matches one of the current
                // users 'standard', 'unblinded' or 'blinded' keys and as such we should check if any
                // of them exist in the `modsAndAminKeys` Set
                let possibleKeys: Set<String> = Set([
                    getUserHexEncodedPublicKey(using: dependencies),
                    SessionId(.unblinded, publicKey: userEdKeyPair.publicKey).hexString,
                    SessionId(.blinded, publicKey: blindedKeyPair.publicKey).hexString
                ])
                
                return !modAndAdminKeys.intersection(possibleKeys).isEmpty
        }
    }
    
    @discardableResult public static func getDefaultRoomsIfNeeded(using dependencies: OGMDependencies = OGMDependencies()) -> Promise<[OpenGroupAPI.Room]> {
        // Note: If we already have a 'defaultRoomsPromise' then there is no need to get it again
        if let existingPromise: Promise<[OpenGroupAPI.Room]> = dependencies.cache.defaultRoomsPromise {
            return existingPromise
        }
        
        let (promise, seal) = Promise<[OpenGroupAPI.Room]>.pending()

        dependencies.storage.write(
            with: { transaction in
                dependencies.storage.setOpenGroupPublicKey(
                    for: OpenGroupAPI.defaultServer,
                    to: OpenGroupAPI.defaultServerPublicKey,
                    using: transaction
                )
            },
            completion: {
                let internalPromise: Promise<[OpenGroupAPI.Room]> = attempt(maxRetryCount: 8, recoveringOn: DispatchQueue.main) {
                    OpenGroupAPI.rooms(for: OpenGroupAPI.defaultServer, using: dependencies)
                        .map { _, data in data }
                }
                internalPromise
                    .done(on: OpenGroupAPI.workQueue) { items in
                        items
                            .compactMap { room -> (UInt64, String)? in
                                guard let imageId: UInt64 = room.imageId else { return nil}
                                
                                return (imageId, room.token)
                            }
                            .forEach { imageId, roomToken in
                                roomImage(imageId, for: roomToken, on: OpenGroupAPI.defaultServer, using: dependencies)
                                    .retainUntilComplete()
                            }
                        seal.fulfill(items)
                    }
                    .retainUntilComplete()
                
                internalPromise
                    .catch(on: OpenGroupAPI.workQueue) { error in
                        dependencies.mutableCache.mutate { cache in
                            cache.defaultRoomsPromise = nil
                        }
                        seal.reject(error)
                    }
            }
        )
        
        dependencies.mutableCache.mutate { cache in
            cache.defaultRoomsPromise = promise
        }
        
        return promise
    }
    
    public static func roomImage(
        _ fileId: UInt64,
        for roomToken: String,
        on server: String,
        using dependencies: OGMDependencies = OGMDependencies()
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
        let lastOpenGroupImageUpdate: Date? = dependencies.standardUserDefaults[.lastOpenGroupImageUpdate]
        let now: Date = dependencies.date
        let timeSinceLastUpdate: TimeInterval = (lastOpenGroupImageUpdate.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude)
        let updateInterval: TimeInterval = (7 * 24 * 60 * 60)
        
        if let data = dependencies.storage.getOpenGroupImage(for: roomToken, on: server), server == OpenGroupAPI.defaultServer, timeSinceLastUpdate < updateInterval {
            return Promise.value(data)
        }
        
        if let promise = dependencies.cache.groupImagePromises["\(server).\(roomToken)"] {
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
                dependencies.standardUserDefaults[.lastOpenGroupImageUpdate] = now
            }
        }
        dependencies.mutableCache.mutate { cache in
            cache.groupImagePromises["\(server).\(roomToken)"] = promise
        }
        
        return promise
    }
    
    public static func parseOpenGroup(from string: String) -> (room: String, server: String, publicKey: String)? {
        guard let url = URL(string: string), let host = url.host ?? given(string.split(separator: "/").first, { String($0) }), let query = url.query else { return nil }
        // Inputs that should work:
        // https://sessionopengroup.co/r/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // https://sessionopengroup.co/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // http://sessionopengroup.co/r/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // http://sessionopengroup.co/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // sessionopengroup.co/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c (does NOT go to HTTPS)
        // sessionopengroup.co/r/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c (does NOT go to HTTPS)
        // https://143.198.213.225:443/r/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // https://143.198.213.225:443/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // 143.198.213.255:80/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
        // 143.198.213.255:80/r/main?public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c
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

// MARK: - Objective C Methods

extension OpenGroupManager {
    @objc(startPolling)
    public func objc_startPolling() {
        startPolling()
    }
    
    @objc(stopPolling)
    public func objc_stopPolling() {
        stopPolling()
    }
    
    @objc(getDefaultRoomsIfNeeded)
    public static func objc_getDefaultRoomsIfNeeded() {
        getDefaultRoomsIfNeeded()
    }
    
    @objc(isUserModeratorOrAdmin:forRoom:onServer:)
    public static func isUserModeratorOrAdmin(_ publicKey: String, for room: String, on server: String) -> Bool {
        return isUserModeratorOrAdmin(publicKey, for: room, on: server, using: OGMDependencies())
    }
}


// MARK: - OGMDependencies

extension OpenGroupManager {
    public class OGMDependencies: Dependencies {
        internal var _mutableCache: Atomic<OGMCacheType>?
        public var mutableCache: Atomic<OGMCacheType> {
            get { Dependencies.getValueSettingIfNull(&_mutableCache) { OpenGroupManager.shared.mutableCache } }
            set { _mutableCache = newValue }
        }
        
        public var cache: OGMCacheType { return mutableCache.wrappedValue }
        
        public init(
            cache: Atomic<OGMCacheType>? = nil,
            onionApi: OnionRequestAPIType.Type? = nil,
            identityManager: IdentityManagerProtocol? = nil,
            generalCache: Atomic<GeneralCacheType>? = nil,
            storage: SessionMessagingKitStorageProtocol? = nil,
            sodium: SodiumType? = nil,
            box: BoxType? = nil,
            genericHash: GenericHashType? = nil,
            sign: SignType? = nil,
            aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
            ed25519: Ed25519Type? = nil,
            nonceGenerator16: NonceGenerator16ByteType? = nil,
            nonceGenerator24: NonceGenerator24ByteType? = nil,
            standardUserDefaults: UserDefaultsType? = nil,
            date: Date? = nil
        ) {
            _mutableCache = cache
            
            super.init(
                onionApi: onionApi,
                identityManager: identityManager,
                generalCache: generalCache,
                storage: storage,
                sodium: sodium,
                box: box,
                genericHash: genericHash,
                sign: sign,
                aeadXChaCha20Poly1305Ietf: aeadXChaCha20Poly1305Ietf,
                ed25519: ed25519,
                nonceGenerator16: nonceGenerator16,
                nonceGenerator24: nonceGenerator24,
                standardUserDefaults: standardUserDefaults,
                date: date
            )
        }
    }
}
