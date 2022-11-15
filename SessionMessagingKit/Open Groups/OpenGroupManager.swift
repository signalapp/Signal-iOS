// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
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
    
    var hasPerformedInitialPoll: [String: Bool] { get set }
    var timeSinceLastPoll: [String: TimeInterval] { get set }
    
    var pendingChanges: [OpenGroupAPI.PendingChange] { get set }
    
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
        
        public var pendingChanges: [OpenGroupAPI.PendingChange] = []
    }
    
    // MARK: - Variables
    
    @objc public static let shared: OpenGroupManager = OpenGroupManager()
    
    /// Note: This should not be accessed directly but rather via the 'OGMDependencies' type
    fileprivate let mutableCache: Atomic<OGMCacheType> = Atomic(Cache())
    
    // MARK: - Polling

    public func startPolling(using dependencies: OGMDependencies = OGMDependencies()) {
        guard !dependencies.cache.isPolling else { return }
        
        let servers: Set<String> = dependencies.storage
            .read { db in
                // The default room promise creates an OpenGroup with an empty `roomToken` value,
                // we don't want to start a poller for this as the user hasn't actually joined a room
                try OpenGroup
                    .select(.server)
                    .filter(OpenGroup.Columns.isActive == true)
                    .filter(OpenGroup.Columns.roomToken != "")
                    .distinct()
                    .asRequest(of: String.self)
                    .fetchSet(db)
            }
            .defaulting(to: [])
        
        dependencies.mutableCache.mutate { cache in
            cache.isPolling = true
            cache.pollers = servers
                .reduce(into: [:]) { result, server in
                    result[server.lowercased()]?.stop() // Should never occur
                    result[server.lowercased()] = OpenGroupAPI.Poller(for: server.lowercased())
                }
            
            // Note: We loop separately here because when the cache is mocked-out for tests it
            // doesn't actually store the value (meaning the pollers won't be started), but if
            // we do it in the 'reduce' function, the 'reduce' result will actually store the
            // poller value resulting in a bunch of OpenGroup pollers running in a way that can't
            // be stopped during unit tests
            cache.pollers.forEach { _, poller in poller.startIfNeeded(using: dependencies) }
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
    
    private static func port(for server: String, serverUrl: URL) -> String {
        if let port: Int = serverUrl.port {
            return ":\(port)"
        }
        
        let components: [String] = server.components(separatedBy: ":")
        
        guard
            let port: String = components.last,
            (
                port != components.first &&
                !port.starts(with: "//")
            )
        else { return "" }
        
        return ":\(port)"
    }
    
    public static func isSessionRunOpenGroup(server: String) -> Bool {
        guard let serverUrl: URL = URL(string: server.lowercased()) else { return false }
        
        let serverPort: String = OpenGroupManager.port(for: server, serverUrl: serverUrl)
        let serverHost: String = serverUrl.host
            .defaulting(
                to: server
                    .lowercased()
                    .replacingOccurrences(of: serverPort, with: "")
            )
        let options: Set<String> = Set([
            OpenGroupAPI.legacyDefaultServerIP,
            OpenGroupAPI.defaultServer
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
        ])
        
        return options.contains(serverHost)
    }
    
    public func hasExistingOpenGroup(_ db: Database, roomToken: String, server: String, publicKey: String, dependencies: OGMDependencies = OGMDependencies()) -> Bool {
        guard let serverUrl: URL = URL(string: server.lowercased()) else { return false }
        
        let serverPort: String = OpenGroupManager.port(for: server, serverUrl: serverUrl)
        let serverHost: String = serverUrl.host
            .defaulting(
                to: server
                    .lowercased()
                    .replacingOccurrences(of: serverPort, with: "")
            )
        let defaultServerHost: String = OpenGroupAPI.defaultServer
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        var serverOptions: Set<String> = Set([
            server.lowercased(),
            "\(serverHost)\(serverPort)",
            "http://\(serverHost)\(serverPort)",
            "https://\(serverHost)\(serverPort)"
        ])
        
        // If the server is run by Session then include all configurations in case one of the alternate configurations
        // was used
        if OpenGroupManager.isSessionRunOpenGroup(server: server) {
            serverOptions.insert(defaultServerHost)
            serverOptions.insert("http://\(defaultServerHost)")
            serverOptions.insert("https://\(defaultServerHost)")
            serverOptions.insert(OpenGroupAPI.legacyDefaultServerIP)
            serverOptions.insert("http://\(OpenGroupAPI.legacyDefaultServerIP)")
            serverOptions.insert("https://\(OpenGroupAPI.legacyDefaultServerIP)")
        }
        
        // First check if there is no poller for the specified server
        if serverOptions.first(where: { dependencies.cache.pollers[$0] != nil }) == nil {
            return false
        }
        
        // Then check if there is an existing open group thread
        let hasExistingThread: Bool = serverOptions.contains(where: { serverName in
            (try? SessionThread
                .exists(
                    db,
                    id: OpenGroup.idFor(roomToken: roomToken, server: serverName)
                ))
                .defaulting(to: false)
        })
                                                                  
        return hasExistingThread
    }
    
    public func add(_ db: Database, roomToken: String, server: String, publicKey: String, isConfigMessage: Bool, dependencies: OGMDependencies = OGMDependencies()) -> Promise<Void> {
        // If we are currently polling for this server and already have a TSGroupThread for this room the do nothing
        if hasExistingOpenGroup(db, roomToken: roomToken, server: server, publicKey: publicKey, dependencies: dependencies) {
            SNLog("Ignoring join open group attempt (already joined), user initiated: \(!isConfigMessage)")
            return Promise.value(())
        }
        
        // Store the open group information
        let targetServer: String = {
            guard OpenGroupManager.isSessionRunOpenGroup(server: server) else {
                return server.lowercased()
            }
            
            return OpenGroupAPI.defaultServer
        }()
        let threadId: String = OpenGroup.idFor(roomToken: roomToken, server: targetServer)
        
        // Optionally try to insert a new version of the OpenGroup (it will fail if there is already an
        // inactive one but that won't matter as we then activate it
        _ = try? SessionThread.fetchOrCreate(db, id: threadId, variant: .openGroup)
        _ = try? SessionThread.filter(id: threadId).updateAll(db, SessionThread.Columns.shouldBeVisible.set(to: true))
        
        if (try? OpenGroup.exists(db, id: threadId)) == false {
            try? OpenGroup
                .fetchOrCreate(db, server: targetServer, roomToken: roomToken, publicKey: publicKey)
                .save(db)
        }
        
        // Set the group to active and reset the sequenceNumber (handle groups which have
        // been deactivated)
        _ = try? OpenGroup
            .filter(id: OpenGroup.idFor(roomToken: roomToken, server: targetServer))
            .updateAll(
                db,
                OpenGroup.Columns.isActive.set(to: true),
                OpenGroup.Columns.sequenceNumber.set(to: 0)
            )
        
        let (promise, seal) = Promise<Void>.pending()
        
        // Note: We don't do this after the db commit as it can fail (resulting in endless loading)
        OpenGroupAPI.workQueue.async {
            dependencies.storage
                .writeAsync { db in
                    // Note: The initial request for room info and it's capabilities should NOT be
                    // authenticated (this is because if the server requires blinding and the auth
                    // headers aren't blinded it will error - these endpoints do support unauthenticated
                    // retrieval so doing so prevents the error)
                    OpenGroupAPI
                        .capabilitiesAndRoom(
                            db,
                            for: roomToken,
                            on: targetServer,
                            using: dependencies
                        )
                }
                .done(on: OpenGroupAPI.workQueue) { response in
                    dependencies.storage.write { db in
                        // Store the capabilities first
                        OpenGroupManager.handleCapabilities(
                            db,
                            capabilities: response.capabilities.data,
                            on: targetServer
                        )
                        
                        // Then the room
                        try OpenGroupManager.handlePollInfo(
                            db,
                            pollInfo: OpenGroupAPI.RoomPollInfo(room: response.room.data),
                            publicKey: publicKey,
                            for: roomToken,
                            on: targetServer,
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
                .retainUntilComplete()
        }
        
        return promise
    }

    public func delete(_ db: Database, openGroupId: String, dependencies: OGMDependencies = OGMDependencies()) {
        let server: String? = try? OpenGroup
            .select(.server)
            .filter(id: openGroupId)
            .asRequest(of: String.self)
            .fetchOne(db)
        
        // Stop the poller if needed
        //
        // Note: The default room promise creates an OpenGroup with an empty `roomToken` value,
        // we don't want to start a poller for this as the user hasn't actually joined a room
        let numActiveRooms: Int = (try? OpenGroup
            .filter(OpenGroup.Columns.server == server?.lowercased())
            .filter(OpenGroup.Columns.roomToken != "")
            .filter(OpenGroup.Columns.isActive)
            .fetchCount(db))
            .defaulting(to: 1)
        
        if numActiveRooms == 1, let server: String = server?.lowercased() {
            let poller = dependencies.cache.pollers[server]
            poller?.stop()
            dependencies.mutableCache.mutate { $0.pollers[server] = nil }
        }
        
        // Remove all the data (everything should cascade delete)
        _ = try? SessionThread
            .filter(id: openGroupId)
            .deleteAll(db)
        
        // Remove the open group (no foreign key to the thread so it won't auto-delete)
        if server?.lowercased() != OpenGroupAPI.defaultServer.lowercased() {
            _ = try? OpenGroup
                .filter(id: openGroupId)
                .deleteAll(db)
        }
        else {
            // If it's a session-run room then just set it to inactive
            _ = try? OpenGroup
                .filter(id: openGroupId)
                .updateAll(db, OpenGroup.Columns.isActive.set(to: false))
        }
        
        // Remove the thread and associated data
        _ = try? SessionThread
            .filter(id: openGroupId)
            .deleteAll(db)
    }
    
    // MARK: - Response Processing
    
    internal static func handleCapabilities(
        _ db: Database,
        capabilities: OpenGroupAPI.Capabilities,
        on server: String
    ) {
        // Remove old capabilities first
        _ = try? Capability
            .filter(Capability.Columns.openGroupServer == server.lowercased())
            .deleteAll(db)
        
        // Then insert the new capabilities (both present and missing)
        capabilities.capabilities.forEach { capability in
            _ = try? Capability(
                openGroupServer: server.lowercased(),
                variant: capability,
                isMissing: false
            )
            .saved(db)
        }
        capabilities.missing?.forEach { capability in
            _ = try? Capability(
                openGroupServer: server.lowercased(),
                variant: capability,
                isMissing: true
            )
            .saved(db)
        }
    }
    
    internal static func handlePollInfo(
        _ db: Database,
        pollInfo: OpenGroupAPI.RoomPollInfo,
        publicKey maybePublicKey: String?,
        for roomToken: String,
        on server: String,
        waitForImageToComplete: Bool = false,
        dependencies: OGMDependencies = OGMDependencies(),
        completion: (() -> ())? = nil
    ) throws {
        // Create the open group model and get or create the thread
        let threadId: String = OpenGroup.idFor(roomToken: roomToken, server: server)
        
        guard let openGroup: OpenGroup = try OpenGroup.fetchOne(db, id: threadId) else { return }
        
        // Only update the database columns which have changed (this is to prevent the UI from triggering
        // updates due to changing database columns to the existing value)
        let permissions = OpenGroup.Permissions(roomInfo: pollInfo)

        try OpenGroup
            .filter(id: openGroup.id)
            .updateAll(
                db,
                [
                    (openGroup.publicKey != maybePublicKey ?
                        maybePublicKey.map { OpenGroup.Columns.publicKey.set(to: $0) } :
                        nil
                    ),
                    (openGroup.name != pollInfo.details?.name ?
                        (pollInfo.details?.name).map { OpenGroup.Columns.name.set(to: $0) } :
                        nil
                    ),
                    (openGroup.roomDescription != pollInfo.details?.roomDescription ?
                        (pollInfo.details?.roomDescription).map { OpenGroup.Columns.roomDescription.set(to: $0) } :
                        nil
                    ),
                    (openGroup.imageId != pollInfo.details?.imageId.map { "\($0)" } ?
                        (pollInfo.details?.imageId).map { OpenGroup.Columns.imageId.set(to: "\($0)") } :
                        nil
                    ),
                    (openGroup.userCount != pollInfo.activeUsers ?
                        OpenGroup.Columns.userCount.set(to: pollInfo.activeUsers) :
                        nil
                    ),
                    (openGroup.infoUpdates != pollInfo.details?.infoUpdates ?
                        (pollInfo.details?.infoUpdates).map { OpenGroup.Columns.infoUpdates.set(to: $0) } :
                        nil
                    ),
                    (openGroup.permissions != permissions ?
                        OpenGroup.Columns.permissions.set(to: permissions) :
                        nil
                    )
                ].compactMap { $0 }
            )
        
        // Update the admin/moderator group members
        if let roomDetails: OpenGroupAPI.Room = pollInfo.details {
            _ = try? GroupMember
                .filter(GroupMember.Columns.groupId == threadId)
                .deleteAll(db)
            
            try roomDetails.admins.forEach { adminId in
                _ = try GroupMember(
                    groupId: threadId,
                    profileId: adminId,
                    role: .admin,
                    isHidden: false
                ).saved(db)
            }
            
            try roomDetails.hiddenAdmins
                .defaulting(to: [])
                .forEach { adminId in
                    _ = try GroupMember(
                        groupId: threadId,
                        profileId: adminId,
                        role: .admin,
                        isHidden: true
                    ).saved(db)
                }
            
            try roomDetails.moderators.forEach { moderatorId in
                _ = try GroupMember(
                    groupId: threadId,
                    profileId: moderatorId,
                    role: .moderator,
                    isHidden: false
                ).saved(db)
            }
            
            try roomDetails.hiddenModerators
                .defaulting(to: [])
                .forEach { moderatorId in
                    _ = try GroupMember(
                        groupId: threadId,
                        profileId: moderatorId,
                        role: .moderator,
                        isHidden: true
                    ).saved(db)
                }
        }
        
        db.afterNextTransaction { db in
            // Start the poller if needed
            if dependencies.cache.pollers[server.lowercased()] == nil {
                dependencies.mutableCache.mutate {
                    $0.pollers[server.lowercased()] = OpenGroupAPI.Poller(for: server.lowercased())
                    $0.pollers[server.lowercased()]?.startIfNeeded(using: dependencies)
                }
            }
            
            /// Start downloading the room image (if we don't have one or it's been updated)
            if
                let imageId: String = pollInfo.details?.imageId,
                (
                    openGroup.imageData == nil ||
                    openGroup.imageId != imageId
                )
            {
                OpenGroupManager.roomImage(db, fileId: imageId, for: roomToken, on: server, using: dependencies)
                    .done { data in
                        dependencies.storage.write { db in
                            _ = try OpenGroup
                                .filter(id: threadId)
                                .updateAll(db, OpenGroup.Columns.imageData.set(to: data))
                            
                            if waitForImageToComplete {
                                completion?()
                            }
                        }
                    }
                    .catch { _ in
                        if waitForImageToComplete {
                            completion?()
                        }
                    }
                    .retainUntilComplete()
            }
            else if waitForImageToComplete {
                completion?()
            }
            
            // If we want to wait for the image to complete then don't call the completion here
            guard !waitForImageToComplete else { return }

            // Finish
            completion?()
        }
    }
    
    internal static func handleMessages(
        _ db: Database,
        messages: [OpenGroupAPI.Message],
        for roomToken: String,
        on server: String,
        dependencies: OGMDependencies = OGMDependencies()
    ) {
        // Sorting the messages by server ID before importing them fixes an issue where messages
        // that quote older messages can't find those older messages
        guard let openGroup: OpenGroup = try? OpenGroup.fetchOne(db, id: OpenGroup.idFor(roomToken: roomToken, server: server)) else {
            SNLog("Couldn't handle open group messages.")
            return
        }
        
        let seqNo: Int64? = messages.map { $0.seqNo }.max()
        let sortedMessages: [OpenGroupAPI.Message] = messages
            .filter { $0.deleted != true }
            .sorted { lhs, rhs in lhs.id < rhs.id }
        var messageServerIdsToRemove: [Int64] = messages
            .filter { $0.deleted == true }
            .map { $0.id }
        
        if let seqNo: Int64 = seqNo {
            // Update the 'openGroupSequenceNumber' value (Note: SOGS V4 uses the 'seqNo' instead of the 'serverId')
            _ = try? OpenGroup
                .filter(id: openGroup.id)
                .updateAll(db, OpenGroup.Columns.sequenceNumber.set(to: seqNo))
            
            // Update pendingChange cache
            dependencies.mutableCache.mutate {
                $0.pendingChanges = $0.pendingChanges
                    .filter { $0.seqNo == nil || $0.seqNo! > seqNo }
            }
        }
        
        // Process the messages
        sortedMessages.forEach { message in
            if message.base64EncodedData == nil && message.reactions == nil {
                messageServerIdsToRemove.append(Int64(message.id))
                return
            }
            
            // Handle messages
            if let base64EncodedString: String = message.base64EncodedData,
               let data = Data(base64Encoded: base64EncodedString)
            {
                do {
                    let processedMessage: ProcessedMessage? = try Message.processReceivedOpenGroupMessage(
                        db,
                        openGroupId: openGroup.id,
                        openGroupServerPublicKey: openGroup.publicKey,
                        message: message,
                        data: data,
                        dependencies: dependencies
                    )
                    
                    if let messageInfo: MessageReceiveJob.Details.MessageInfo = processedMessage?.messageInfo {
                        try MessageReceiver.handle(
                            db,
                            message: messageInfo.message,
                            associatedWithProto: try SNProtoContent.parseData(messageInfo.serializedProtoData),
                            openGroupId: openGroup.id,
                            dependencies: dependencies
                        )
                    }
                }
                catch {
                    switch error {
                        // Ignore duplicate & selfSend message errors (and don't bother logging
                        // them as there will be a lot since we each service node duplicates messages)
                        case DatabaseError.SQLITE_CONSTRAINT_UNIQUE,
                            MessageReceiverError.duplicateMessage,
                            MessageReceiverError.duplicateControlMessage,
                            MessageReceiverError.selfSend:
                            break
                        
                        default: SNLog("Couldn't receive open group message due to error: \(error).")
                    }
                }
            }
            
            // Handle reactions
            if message.reactions != nil {
                do {
                    let reactions: [Reaction] = Message.processRawReceivedReactions(
                        db,
                        openGroupId: openGroup.id,
                        message: message,
                        associatedPendingChanges: dependencies.cache.pendingChanges
                            .filter {
                                guard $0.server == server && $0.room == roomToken && $0.changeType == .reaction else {
                                    return false
                                }
                                
                                if case .reaction(let messageId, _, _) = $0.metadata {
                                    return messageId == message.id
                                }
                                return false
                            },
                        dependencies: dependencies
                    )
                    
                    try MessageReceiver.handleOpenGroupReactions(
                        db,
                        threadId: openGroup.threadId,
                        openGroupMessageServerId: message.id,
                        openGroupReactions: reactions
                    )
                }
                catch {
                    SNLog("Couldn't handle open group reactions due to error: \(error).")
                }
            }
        }

        // Handle any deletions that are needed
        guard !messageServerIdsToRemove.isEmpty else { return }
        
        _ = try? Interaction
            .filter(Interaction.Columns.threadId == openGroup.threadId)
            .filter(messageServerIdsToRemove.contains(Interaction.Columns.openGroupServerMessageId))
            .deleteAll(db)
    }
    
    internal static func handleDirectMessages(
        _ db: Database,
        messages: [OpenGroupAPI.DirectMessage],
        fromOutbox: Bool,
        on server: String,
        dependencies: OGMDependencies = OGMDependencies()
    ) {
        // Don't need to do anything if we have no messages (it's a valid case)
        guard !messages.isEmpty else { return }
        guard let openGroup: OpenGroup = try? OpenGroup.filter(OpenGroup.Columns.server == server.lowercased()).fetchOne(db) else {
            SNLog("Couldn't receive inbox message.")
            return
        }
        
        // Sorting the messages by server ID before importing them fixes an issue where messages
        // that quote older messages can't find those older messages
        let sortedMessages: [OpenGroupAPI.DirectMessage] = messages
            .sorted { lhs, rhs in lhs.id < rhs.id }
        let latestMessageId: Int64 = sortedMessages[sortedMessages.count - 1].id
        var lookupCache: [String: BlindedIdLookup] = [:]  // Only want this cache to exist for the current loop
        
        // Update the 'latestMessageId' value
        if fromOutbox {
            _ = try? OpenGroup
                .filter(OpenGroup.Columns.server == server.lowercased())
                .updateAll(db, OpenGroup.Columns.outboxLatestMessageId.set(to: latestMessageId))
        }
        else {
            _ = try? OpenGroup
                .filter(OpenGroup.Columns.server == server.lowercased())
                .updateAll(db, OpenGroup.Columns.inboxLatestMessageId.set(to: latestMessageId))
        }

        // Process the messages
        sortedMessages.forEach { message in
            guard let messageData = Data(base64Encoded: message.base64EncodedMessage) else {
                SNLog("Couldn't receive inbox message.")
                return
            }

            do {
                let processedMessage: ProcessedMessage? = try Message.processReceivedOpenGroupDirectMessage(
                    db,
                    openGroupServerPublicKey: openGroup.publicKey,
                    message: message,
                    data: messageData,
                    isOutgoing: fromOutbox,
                    otherBlindedPublicKey: (fromOutbox ? message.recipient : message.sender),
                    dependencies: dependencies
                )
                
                // We want to update the BlindedIdLookup cache with the message info so we can avoid using the
                // "expensive" lookup when possible
                let lookup: BlindedIdLookup = try {
                    // Minor optimisation to avoid processing the same sender multiple times in the same
                    // 'handleMessages' call (since the 'mapping' call is done within a transaction we
                    // will never have a mapping come through part-way through processing these messages)
                    if let result: BlindedIdLookup = lookupCache[message.recipient] {
                        return result
                    }
                    
                    return try BlindedIdLookup.fetchOrCreate(
                        db,
                        blindedId: (fromOutbox ?
                            message.recipient :
                            message.sender
                        ),
                        sessionId: (fromOutbox ?
                            nil :
                            processedMessage?.threadId
                        ),
                        openGroupServer: server.lowercased(),
                        openGroupPublicKey: openGroup.publicKey,
                        isCheckingForOutbox: fromOutbox,
                        dependencies: dependencies
                    )
                }()
                lookupCache[message.recipient] = lookup
                    
                // We also need to set the 'syncTarget' for outgoing messages to be consistent with
                // standard messages
                if fromOutbox {
                    let syncTarget: String = (lookup.sessionId ?? message.recipient)
                    
                    switch processedMessage?.messageInfo.variant {
                        case .visibleMessage:
                            (processedMessage?.messageInfo.message as? VisibleMessage)?.syncTarget = syncTarget
                            
                        case .expirationTimerUpdate:
                            (processedMessage?.messageInfo.message as? ExpirationTimerUpdate)?.syncTarget = syncTarget
                            
                        default: break
                    }
                }
                
                if let messageInfo: MessageReceiveJob.Details.MessageInfo = processedMessage?.messageInfo {
                    try MessageReceiver.handle(
                        db,
                        message: messageInfo.message,
                        associatedWithProto: try SNProtoContent.parseData(messageInfo.serializedProtoData),
                        openGroupId: nil,   // Intentionally nil as they are technically not open group messages
                        dependencies: dependencies
                    )
                }
            }
            catch {
                switch error {
                    // Ignore duplicate and self-send errors (we will always receive a duplicate message back
                    // whenever we send a message so this ends up being spam otherwise)
                    case DatabaseError.SQLITE_CONSTRAINT_UNIQUE,
                        MessageReceiverError.duplicateMessage,
                        MessageReceiverError.duplicateControlMessage,
                        MessageReceiverError.selfSend:
                        break
                        
                    default:
                        SNLog("Couldn't receive inbox message due to error: \(error).")
                }
            }
        }
    }
    
    // MARK: - Convenience
    
    public static func addPendingReaction(
        emoji: String,
        id: Int64,
        in roomToken: String,
        on server: String,
        type: OpenGroupAPI.PendingChange.ReactAction,
        using dependencies: OGMDependencies = OGMDependencies()
    ) -> OpenGroupAPI.PendingChange {
        let pendingChange = OpenGroupAPI.PendingChange(
            server: server,
            room: roomToken,
            changeType: .reaction,
            metadata: .reaction(
                messageId: id,
                emoji: emoji,
                action: type
            )
        )
        
        dependencies.mutableCache.mutate {
            $0.pendingChanges.append(pendingChange)
        }
        
        return pendingChange
    }
    
    public static func updatePendingChange(
        _ pendingChange: OpenGroupAPI.PendingChange,
        seqNo: Int64?,
        using dependencies: OGMDependencies = OGMDependencies()
    ) {
        dependencies.mutableCache.mutate {
            if let index = $0.pendingChanges.firstIndex(of: pendingChange) {
                $0.pendingChanges[index].seqNo = seqNo
            }
        }
    }
    
    public static func removePendingChange(
        _ pendingChange: OpenGroupAPI.PendingChange,
        using dependencies: OGMDependencies = OGMDependencies()
    ) {
        dependencies.mutableCache.mutate {
            if let index = $0.pendingChanges.firstIndex(of: pendingChange) {
                $0.pendingChanges.remove(at: index)
            }
        }
    }
    
    /// This method specifies if the given capability is supported on a specified Open Group
    public static func isOpenGroupSupport(
        _ capability: Capability.Variant,
        on server: String?,
        using dependencies: OGMDependencies = OGMDependencies()
    ) -> Bool {
        guard let server: String = server else { return false }
        
        return dependencies.storage
            .read { db in
                let capabilities: [Capability.Variant] = (try? Capability
                    .select(.variant)
                    .filter(Capability.Columns.openGroupServer == server)
                    .filter(Capability.Columns.isMissing == false)
                    .asRequest(of: Capability.Variant.self)
                    .fetchAll(db))
                    .defaulting(to: [])

                return capabilities.contains(capability)
            }
            .defaulting(to: false)
    }
    
    /// This method specifies if the given publicKey is a moderator or an admin within a specified Open Group
    public static func isUserModeratorOrAdmin(
        _ publicKey: String,
        for roomToken: String?,
        on server: String?,
        using dependencies: OGMDependencies = OGMDependencies()
    ) -> Bool {
        guard let roomToken: String = roomToken, let server: String = server else { return false }

        let groupId: String = OpenGroup.idFor(roomToken: roomToken, server: server)
        let targetRoles: [GroupMember.Role] = [.moderator, .admin]
        
        return dependencies.storage
            .read { db in
                let isDirectModOrAdmin: Bool = (try? GroupMember
                    .filter(GroupMember.Columns.groupId == groupId)
                    .filter(GroupMember.Columns.profileId == publicKey)
                    .filter(targetRoles.contains(GroupMember.Columns.role))
                    .isNotEmpty(db))
                    .defaulting(to: false)
                
                // If the publicKey provided matches a mod or admin directly then just return immediately
                if isDirectModOrAdmin { return true }
                
                // Otherwise we need to check if it's a variant of the current users key and if so we want
                // to check if any of those have mod/admin entries
                guard let sessionId: SessionId = SessionId(from: publicKey) else { return false }
                
                // Conveniently the logic for these different cases works in order so we can fallthrough each
                // case with only minor efficiency losses
                let userPublicKey: String = getUserHexEncodedPublicKey(db, dependencies: dependencies)
                
                switch sessionId.prefix {
                    case .standard:
                        guard publicKey == userPublicKey else { return false }
                        fallthrough
                        
                    case .unblinded:
                        guard let userEdKeyPair: Box.KeyPair = Identity.fetchUserEd25519KeyPair(db) else {
                            return false
                        }
                        guard sessionId.prefix != .unblinded || publicKey == SessionId(.unblinded, publicKey: userEdKeyPair.publicKey).hexString else {
                            return false
                        }
                        fallthrough
                        
                    case .blinded:
                        guard
                            let userEdKeyPair: Box.KeyPair = Identity.fetchUserEd25519KeyPair(db),
                            let openGroupPublicKey: String = try? OpenGroup
                                .select(.publicKey)
                                .filter(id: groupId)
                                .asRequest(of: String.self)
                                .fetchOne(db),
                            let blindedKeyPair: Box.KeyPair = dependencies.sodium.blindedKeyPair(
                                serverPublicKey: openGroupPublicKey,
                                edKeyPair: userEdKeyPair,
                                genericHash: dependencies.genericHash
                            )
                        else { return false }
                        guard sessionId.prefix != .blinded || publicKey == SessionId(.blinded, publicKey: blindedKeyPair.publicKey).hexString else {
                            return false
                        }
                        
                        // If we got to here that means that the 'publicKey' value matches one of the current
                        // users 'standard', 'unblinded' or 'blinded' keys and as such we should check if any
                        // of them exist in the `modsAndAminKeys` Set
                        let possibleKeys: Set<String> = Set([
                            userPublicKey,
                            SessionId(.unblinded, publicKey: userEdKeyPair.publicKey).hexString,
                            SessionId(.blinded, publicKey: blindedKeyPair.publicKey).hexString
                        ])
                        
                        return (try? GroupMember
                            .filter(GroupMember.Columns.groupId == groupId)
                            .filter(possibleKeys.contains(GroupMember.Columns.profileId))
                            .filter(targetRoles.contains(GroupMember.Columns.role))
                            .isNotEmpty(db))
                            .defaulting(to: false)
                }
            }
            .defaulting(to: false)
    }
    
    @discardableResult public static func getDefaultRoomsIfNeeded(using dependencies: OGMDependencies = OGMDependencies()) -> Promise<[OpenGroupAPI.Room]> {
        // Note: If we already have a 'defaultRoomsPromise' then there is no need to get it again
        if let existingPromise: Promise<[OpenGroupAPI.Room]> = dependencies.cache.defaultRoomsPromise {
            return existingPromise
        }
        
        let (promise, seal) = Promise<[OpenGroupAPI.Room]>.pending()
        
        // Try to retrieve the default rooms 8 times
        attempt(maxRetryCount: 8, recoveringOn: OpenGroupAPI.workQueue) {
            dependencies.storage.read { db in
                OpenGroupAPI.capabilitiesAndRooms(
                    db,
                    on: OpenGroupAPI.defaultServer,
                    using: dependencies
                )
            }
        }
        .done(on: OpenGroupAPI.workQueue) { response in
            dependencies.storage.writeAsync { db in
                // Store the capabilities first
                OpenGroupManager.handleCapabilities(
                    db,
                    capabilities: response.capabilities.data,
                    on: OpenGroupAPI.defaultServer
                )
                    
                // Then the rooms
                response.rooms.data
                    .compactMap { room -> (String, String)? in
                        // Try to insert an inactive version of the OpenGroup (use 'insert' rather than 'save'
                        // as we want it to fail if the room already exists)
                        do {
                            _ = try OpenGroup(
                                server: OpenGroupAPI.defaultServer,
                                roomToken: room.token,
                                publicKey: OpenGroupAPI.defaultServerPublicKey,
                                isActive: false,
                                name: room.name,
                                roomDescription: room.roomDescription,
                                imageId: room.imageId,
                                imageData: nil,
                                userCount: room.activeUsers,
                                infoUpdates: room.infoUpdates,
                                sequenceNumber: 0,
                                inboxLatestMessageId: 0,
                                outboxLatestMessageId: 0
                            )
                            .inserted(db)
                        }
                        catch {}
                        
                        guard let imageId: String = room.imageId else { return nil }
                        
                        return (imageId, room.token)
                    }
                    .forEach { imageId, roomToken in
                        roomImage(
                            db,
                            fileId: imageId,
                            for: roomToken,
                            on: OpenGroupAPI.defaultServer,
                            using: dependencies
                        )
                        .retainUntilComplete()
                    }
            }
            
            seal.fulfill(response.rooms.data)
        }
        .catch(on: OpenGroupAPI.workQueue) { error in
            dependencies.mutableCache.mutate { cache in
                cache.defaultRoomsPromise = nil
            }
            
            seal.reject(error)
        }
        .retainUntilComplete()
        
        dependencies.mutableCache.mutate { cache in
            cache.defaultRoomsPromise = promise
        }
        
        return promise
    }
    
    public static func roomImage(
        _ db: Database,
        fileId: String,
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
        let threadId: String = OpenGroup.idFor(roomToken: roomToken, server: server)
        let lastOpenGroupImageUpdate: Date? = dependencies.standardUserDefaults[.lastOpenGroupImageUpdate]
        let now: Date = dependencies.date
        let timeSinceLastUpdate: TimeInterval = (lastOpenGroupImageUpdate.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude)
        let updateInterval: TimeInterval = (7 * 24 * 60 * 60)
        
        if
            server.lowercased() == OpenGroupAPI.defaultServer,
            timeSinceLastUpdate < updateInterval,
            let data = try? OpenGroup
                .select(.imageData)
                .filter(id: threadId)
                .asRequest(of: Data.self)
                .fetchOne(db)
        { return Promise.value(data) }
        
        if let promise = dependencies.cache.groupImagePromises[threadId] {
            return promise
        }
        
        let (promise, seal) = Promise<Data>.pending()
        
        // Trigger the download on a background queue
        DispatchQueue.global(qos: .background).async {
            dependencies.storage
                .read { db in
                    OpenGroupAPI
                        .downloadFile(
                            db,
                            fileId: fileId,
                            from: roomToken,
                            on: server,
                            using: dependencies
                        )
                }
                .done { _, imageData in
                    if server.lowercased() == OpenGroupAPI.defaultServer {
                        dependencies.storage.write { db in
                            _ = try OpenGroup
                                .filter(id: threadId)
                                .updateAll(db, OpenGroup.Columns.imageData.set(to: imageData))
                        }
                        dependencies.standardUserDefaults[.lastOpenGroupImageUpdate] = now
                    }
                    
                    seal.fulfill(imageData)
                }
                .catch { seal.reject($0) }
                .retainUntilComplete()
        }
        
        dependencies.mutableCache.mutate { cache in
            cache.groupImagePromises[threadId] = promise
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


// MARK: - OGMDependencies

extension OpenGroupManager {
    public class OGMDependencies: SMKDependencies {
        internal var _mutableCache: Atomic<Atomic<OGMCacheType>?>
        public var mutableCache: Atomic<OGMCacheType> {
            get { Dependencies.getValueSettingIfNull(&_mutableCache) { OpenGroupManager.shared.mutableCache } }
            set { _mutableCache.mutate { $0 = newValue } }
        }
        
        public var cache: OGMCacheType { return mutableCache.wrappedValue }
        
        public init(
            cache: Atomic<OGMCacheType>? = nil,
            onionApi: OnionRequestAPIType.Type? = nil,
            generalCache: Atomic<GeneralCacheType>? = nil,
            storage: Storage? = nil,
            scheduler: ValueObservationScheduler? = nil,
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
            _mutableCache = Atomic(cache)
            
            super.init(
                onionApi: onionApi,
                generalCache: generalCache,
                storage: storage,
                scheduler: scheduler,
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
