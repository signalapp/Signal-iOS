// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import Sodium
import Curve25519Kit
import SessionSnodeKit
import SessionUtilitiesKit

public enum OpenGroupAPI {
    // MARK: - Settings
    
    public static let legacyDefaultServerIP = "116.203.70.33"
    public static let defaultServer = "https://open.getsession.org"
    public static let defaultServerPublicKey = "a03c383cf63c3c4efe67acc52112a6dd734b3a946b9545f488aaa93da7991238"

    public static let workQueue = DispatchQueue(label: "OpenGroupAPI.workQueue", qos: .userInitiated) // It's important that this is a serial queue

    // MARK: - Batching & Polling
    
    /// This is a convenience method which calls `/batch` with a pre-defined set of requests used to update an Open
    /// Group, currently this will retrieve:
    /// - Capabilities for the server
    /// - For each room:
    ///    - Poll Info
    ///    - Messages (includes additions and deletions)
    /// - Inbox for the server
    /// - Outbox for the server
    public static func poll(
        _ db: Database,
        server: String,
        hasPerformedInitialPoll: Bool,
        timeSinceLastPoll: TimeInterval,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<[Endpoint: (OnionRequestResponseInfoType, Codable?)]> {
        let lastInboxMessageId: Int64 = (try? OpenGroup
            .select(.inboxLatestMessageId)
            .filter(OpenGroup.Columns.server == server)
            .asRequest(of: Int64.self)
            .fetchOne(db))
            .defaulting(to: 0)
        let lastOutboxMessageId: Int64 = (try? OpenGroup
            .select(.outboxLatestMessageId)
            .filter(OpenGroup.Columns.server == server)
            .asRequest(of: Int64.self)
            .fetchOne(db))
            .defaulting(to: 0)
        let capabilities: Set<Capability.Variant> = (try? Capability
            .select(.variant)
            .filter(Capability.Columns.openGroupServer == server)
            .asRequest(of: Capability.Variant.self)
            .fetchSet(db))
            .defaulting(to: [])

        // Generate the requests
        let requestResponseType: [BatchRequestInfoType] = [
            BatchRequestInfo(
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .capabilities
                ),
                responseType: Capabilities.self
            )
        ]
        .appending(
            // Per-room requests
            contentsOf: (try? OpenGroup
                .filter(OpenGroup.Columns.server == server.lowercased()) // Note: The `OpenGroup` type converts to lowercase in init
                .filter(OpenGroup.Columns.isActive == true)
                .filter(OpenGroup.Columns.roomToken != "")
                .fetchAll(db))
                .defaulting(to: [])
                .flatMap { openGroup -> [BatchRequestInfoType] in
                    let shouldRetrieveRecentMessages: Bool = (
                        openGroup.sequenceNumber == 0 || (
                            // If it's the first poll for this launch and it's been longer than
                            // 'maxInactivityPeriod' then just retrieve recent messages instead
                            // of trying to get all messages since the last one retrieved
                            !hasPerformedInitialPoll &&
                            timeSinceLastPoll > OpenGroupAPI.Poller.maxInactivityPeriod
                        )
                    )
                    
                    return [
                        BatchRequestInfo(
                            request: Request<NoBody, Endpoint>(
                                server: server,
                                endpoint: .roomPollInfo(openGroup.roomToken, openGroup.infoUpdates)
                            ),
                            responseType: RoomPollInfo.self
                        ),
                        BatchRequestInfo(
                            request: Request<NoBody, Endpoint>(
                                server: server,
                                endpoint: (shouldRetrieveRecentMessages ?
                                    .roomMessagesRecent(openGroup.roomToken) :
                                    .roomMessagesSince(openGroup.roomToken, seqNo: openGroup.sequenceNumber)
                                ),
                                queryParameters: [
                                    .updateTypes: UpdateTypes.reaction.rawValue,
                                    .reactors: "5"
                                ]
                            ),
                            responseType: [Failable<Message>].self
                        )
                    ]
                }
        )
        .appending(
            contentsOf: (
                // The 'inbox' and 'outbox' only work with blinded keys so don't bother polling them if not blinded
                !capabilities.contains(.blind) ? [] :
                [
                    // Inbox
                    BatchRequestInfo(
                        request: Request<NoBody, Endpoint>(
                            server: server,
                            endpoint: (lastInboxMessageId == 0 ?
                                .inbox :
                                .inboxSince(id: lastInboxMessageId)
                           )
                        ),
                        responseType: [DirectMessage]?.self // 'inboxSince' will return a `304` with an empty response if no messages
                    ),
                    
                    // Outbox
                    BatchRequestInfo(
                        request: Request<NoBody, Endpoint>(
                            server: server,
                            endpoint: (lastOutboxMessageId == 0 ?
                                .outbox :
                                .outboxSince(id: lastOutboxMessageId)
                           )
                        ),
                        responseType: [DirectMessage]?.self // 'outboxSince' will return a `304` with an empty response if no messages
                    )
                ]
            )
        )
        
        return OpenGroupAPI.batch(db, server: server, requests: requestResponseType, using: dependencies)
    }
    
    /// Submits multiple requests wrapped up in a single request, runs them all, then returns the result of each one
    ///
    /// Requests are performed independently, that is, if one fails the others will still be attempted - there is no guarantee on the order in which requests will be
    /// carried out (for sequential, related requests invoke via `/sequence` instead)
    ///
    /// For contained subrequests that specify a body (i.e. POST or PUT requests) exactly one of `json`, `b64`, or `bytes` must be provided with the request body.
    private static func batch(
        _ db: Database,
        server: String,
        requests: [BatchRequestInfoType],
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<[Endpoint: (OnionRequestResponseInfoType, Codable?)]> {
        let requestBody: BatchRequest = requests.map { $0.toSubRequest() }
        let responseTypes = requests.map { $0.responseType }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.batch,
                    body: requestBody
                ),
                using: dependencies
            )
            .decoded(as: responseTypes, on: OpenGroupAPI.workQueue, using: dependencies)
            .map { result in
                result.enumerated()
                    .reduce(into: [:]) { prev, next in
                        prev[requests[next.offset].endpoint] = next.element
                    }
            }
    }
    
    /// This is like `/batch`, except that it guarantees to perform requests sequentially in the order provided and will stop processing requests if the previous request
    /// returned a non-`2xx` response
    ///
    /// For example, this can be used to ban and delete all of a user's messages by sequencing the ban followed by the `delete_all`: if the ban fails (e.g. because
    /// permission is denied) then the `delete_all` will not occur. The batch body and response are identical to the `/batch` endpoint; requests that are not
    /// carried out because of an earlier failure will have a response code of `412` (Precondition Failed)."
    ///
    /// Like `/batch`, responses are returned in the same order as requests, but unlike `/batch` there may be fewer elements in the response list (if requests were
    /// stopped because of a non-2xx response) - In such a case, the final, non-2xx response is still included as the final response value
    private static func sequence(
        _ db: Database,
        server: String,
        requests: [BatchRequestInfoType],
        authenticated: Bool = true,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<[Endpoint: (OnionRequestResponseInfoType, Codable?)]> {
        let requestBody: BatchRequest = requests.map { $0.toSubRequest() }
        let responseTypes = requests.map { $0.responseType }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.sequence,
                    body: requestBody
                ),
                authenticated: authenticated,
                using: dependencies
            )
            .decoded(as: responseTypes, on: OpenGroupAPI.workQueue, using: dependencies)
            .map { result in
                result.enumerated()
                    .reduce(into: [:]) { prev, next in
                        prev[requests[next.offset].endpoint] = next.element
                    }
            }
    }
    
    // MARK: - Capabilities
    
    /// Return the list of server features/capabilities
    ///
    /// Optionally takes a `required` parameter containing a comma-separated list of capabilites; if any are not satisfied a 412 (Precondition Failed) response
    /// will be returned with missing requested capabilities in the `missing` key
    ///
    /// Eg. `GET /capabilities` could return `{"capabilities": ["sogs", "batch"]}` `GET /capabilities?required=magic,batch`
    /// could return: `{"capabilities": ["sogs", "batch"], "missing": ["magic"]}`
    public static func capabilities(
        _ db: Database,
        server: String,
        authenticated: Bool = true,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Capabilities)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .capabilities
                ),
                authenticated: authenticated,
                using: dependencies
            )
            .decoded(as: Capabilities.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    // MARK: - Room
    
    /// Returns a list of available rooms on the server
    ///
    /// Rooms to which the user does not have access (e.g. because they are banned, or the room has restricted access permissions) are not included
    public static func rooms(
        _ db: Database,
        server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [Room])> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .rooms
                ),
                using: dependencies
            )
            .decoded(as: [Room].self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Returns the details of a single room
    ///
    /// **Note:** This is the direct request to retrieve a room so should only be called from either the `poll()` or `joinRoom()` methods, in order to call
    /// this directly remove the `@available` line and make sure to route the response of this method to the `OpenGroupManager.handlePollInfo`
    /// method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func room(
        _ db: Database,
        for roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Room)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .room(roomToken)
                ),
                using: dependencies
            )
            .decoded(as: Room.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Polls a room for metadata updates
    ///
    /// The endpoint polls room metadata for this room, always including the instantaneous room details (such as the user's permission and current
    /// number of active users), and including the full room metadata if the room's info_updated counter has changed from the provided value
    ///
    /// **Note:** This is the direct request to retrieve room updates so should be retrieved automatically from the `poll()` method, in order to call
    /// this directly remove the `@available` line and make sure to route the response of this method to the `OpenGroupManager.handlePollInfo`
    /// method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func roomPollInfo(
        _ db: Database,
        lastUpdated: Int64,
        for roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, RoomPollInfo)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .roomPollInfo(roomToken, lastUpdated)
                ),
                using: dependencies
            )
            .decoded(as: RoomPollInfo.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// This is a convenience method which constructs a `/sequence` of the `capabilities` and `room`  requests, refer to those
    /// methods for the documented behaviour of each method
    public static func capabilitiesAndRoom(
        _ db: Database,
        for roomToken: String,
        on server: String,
        authenticated: Bool = true,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(capabilities: (info: OnionRequestResponseInfoType, data: Capabilities), room: (info: OnionRequestResponseInfoType, data: Room))> {
        let requestResponseType: [BatchRequestInfoType] = [
            // Get the latest capabilities for the server (in case it's a new server or the cached ones are stale)
            BatchRequestInfo(
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .capabilities
                ),
                responseType: Capabilities.self
            ),
            
            // And the room info
            BatchRequestInfo(
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .room(roomToken)
                ),
                responseType: Room.self
            )
        ]
        
        return OpenGroupAPI
            .sequence(
                db,
                server: server,
                requests: requestResponseType,
                authenticated: authenticated,
                using: dependencies
            )
            .map { (response: [Endpoint: (OnionRequestResponseInfoType, Codable?)]) -> (capabilities: (OnionRequestResponseInfoType, Capabilities), room: (OnionRequestResponseInfoType, Room)) in
                let maybeCapabilities: (info: OnionRequestResponseInfoType, data: Capabilities?)? = response[.capabilities]
                    .map { info, data in (info, (data as? BatchSubResponse<Capabilities>)?.body) }
                let maybeRoomResponse: (OnionRequestResponseInfoType, Codable?)? = response
                    .first(where: { key, _ in
                        switch key {
                            case .room: return true
                            default: return false
                        }
                    })
                    .map { _, value in value }
                let maybeRoom: (info: OnionRequestResponseInfoType, data: Room?)? = maybeRoomResponse
                    .map { info, data in (info, (data as? BatchSubResponse<Room>)?.body) }
                
                guard
                    let capabilitiesInfo: OnionRequestResponseInfoType = maybeCapabilities?.info,
                    let capabilities: Capabilities = maybeCapabilities?.data,
                    let roomInfo: OnionRequestResponseInfoType = maybeRoom?.info,
                    let room: Room = maybeRoom?.data
                else {
                    throw HTTP.Error.parsingFailed
                }
                
                return (
                    (capabilitiesInfo, capabilities),
                    (roomInfo, room)
                )
            }
    }
    
    /// This is a convenience method which constructs a `/sequence` of the `capabilities` and `rooms`  requests, refer to those
    /// methods for the documented behaviour of each method
    public static func capabilitiesAndRooms(
        _ db: Database,
        on server: String,
        authenticated: Bool = true,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(capabilities: (info: OnionRequestResponseInfoType, data: Capabilities), rooms: (info: OnionRequestResponseInfoType, data: [Room]))> {
        let requestResponseType: [BatchRequestInfoType] = [
            // Get the latest capabilities for the server (in case it's a new server or the cached ones are stale)
            BatchRequestInfo(
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .capabilities
                ),
                responseType: Capabilities.self
            ),
            
            // And the room info
            BatchRequestInfo(
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .rooms
                ),
                responseType: [Room].self
            )
        ]
        
        return OpenGroupAPI
            .sequence(
                db,
                server: server,
                requests: requestResponseType,
                authenticated: authenticated,
                using: dependencies
            )
            .map { (response: [Endpoint: (OnionRequestResponseInfoType, Codable?)]) -> (capabilities: (OnionRequestResponseInfoType, Capabilities), rooms: (OnionRequestResponseInfoType, [Room])) in
                let maybeCapabilities: (info: OnionRequestResponseInfoType, data: Capabilities?)? = response[.capabilities]
                    .map { info, data in (info, (data as? BatchSubResponse<Capabilities>)?.body) }
                let maybeRoomResponse: (OnionRequestResponseInfoType, Codable?)? = response
                    .first(where: { key, _ in
                        switch key {
                            case .rooms: return true
                            default: return false
                        }
                    })
                    .map { _, value in value }
                let maybeRooms: (info: OnionRequestResponseInfoType, data: [Room]?)? = maybeRoomResponse
                    .map { info, data in (info, (data as? BatchSubResponse<[Room]>)?.body) }
                
                guard
                    let capabilitiesInfo: OnionRequestResponseInfoType = maybeCapabilities?.info,
                    let capabilities: Capabilities = maybeCapabilities?.data,
                    let roomsInfo: OnionRequestResponseInfoType = maybeRooms?.info,
                    let rooms: [Room] = maybeRooms?.data
                else {
                    throw HTTP.Error.parsingFailed
                }
                
                return (
                    (capabilitiesInfo, capabilities),
                    (roomsInfo, rooms)
                )
            }
    }
    
    // MARK: - Messages
    
    /// Posts a new message to a room
    public static func send(
        _ db: Database,
        plaintext: Data,
        to roomToken: String,
        on server: String,
        whisperTo: String?,
        whisperMods: Bool,
        fileIds: [String]?,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Message)> {
        guard let signResult: (publicKey: String, signature: Bytes) = sign(db, messageBytes: plaintext.bytes, for: server, fallbackSigningType: .standard, using: dependencies) else {
            return Promise(error: OpenGroupAPIError.signingFailed)
        }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.roomMessage(roomToken),
                    body: SendMessageRequest(
                        data: plaintext,
                        signature: Data(signResult.signature),
                        whisperTo: whisperTo,
                        whisperMods: whisperMods,
                        fileIds: fileIds
                    )
                ),
                using: dependencies
            )
            .decoded(as: Message.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Returns a single message by ID
    public static func message(
        _ db: Database,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Message)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .roomMessageIndividual(roomToken, id: id)
                ),
                using: dependencies
            )
            .decoded(as: Message.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Edits a message, replacing its existing content with new content and a new signature
    ///
    /// **Note:** This edit may only be initiated by the creator of the post, and the poster must currently have write permissions in the room
    public static func messageUpdate(
        _ db: Database,
        id: Int64,
        plaintext: Data,
        fileIds: [Int64]?,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        guard let signResult: (publicKey: String, signature: Bytes) = sign(db, messageBytes: plaintext.bytes, for: server, fallbackSigningType: .standard, using: dependencies) else {
            return Promise(error: OpenGroupAPIError.signingFailed)
        }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .put,
                    server: server,
                    endpoint: Endpoint.roomMessageIndividual(roomToken, id: id),
                    body: UpdateMessageRequest(
                        data: plaintext,
                        signature: Data(signResult.signature),
                        fileIds: fileIds
                    )
                ),
                using: dependencies
            )
    }
    
    public static func messageDelete(
        _ db: Database,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .delete,
                    server: server,
                    endpoint: .roomMessageIndividual(roomToken, id: id)
                ),
                using: dependencies
            )
    }
    
    /// **Note:** This is the direct request to retrieve recent messages so should be retrieved automatically from the `poll()` method, in order to call
    /// this directly remove the `@available` line and make sure to route the response of this method to the `OpenGroupManager.handleMessages`
    /// method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func recentMessages(
        _ db: Database,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [Message])> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .roomMessagesRecent(roomToken)
                ),
                using: dependencies
            )
            .decoded(as: [Message].self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// **Note:** This is the direct request to retrieve recent messages before a given message  and is currently unused, in order to call this directly
    /// remove the `@available` line and make sure to route the response of this method to the `OpenGroupManager.handleMessages`
    /// method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func messagesBefore(
        _ db: Database,
        messageId: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [Message])> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .roomMessagesBefore(roomToken, id: messageId)
                ),
                using: dependencies
            )
            .decoded(as: [Message].self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// **Note:** This is the direct request to retrieve messages since a given message `seqNo` so should be retrieved automatically from the
    /// `poll()` method, in order to call this directly remove the `@available` line and make sure to route the response of this method to the
    /// `OpenGroupManager.handleMessages` method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func messagesSince(
        _ db: Database,
        seqNo: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [Message])> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .roomMessagesSince(roomToken, seqNo: seqNo),
                    queryParameters: [
                        .updateTypes: UpdateTypes.reaction.rawValue,
                        .reactors: "20"
                    ]
                ),
                using: dependencies
            )
            .decoded(as: [Message].self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Deletes all messages from a given sessionId within the provided rooms (or globally) on a server
    ///
    /// - Parameters:
    ///   - sessionId: The sessionId (either standard or blinded) of the user whose messages should be deleted
    ///
    ///   - roomToken: The room token from which the messages should be deleted
    ///
    ///     The invoking user **must** be a moderator of the given room or an admin if trying to delete the messages
    ///     of another admin.
    ///
    ///   - server: The server to delete messages from
    ///
    ///   - dependencies: Injected dependencies (used for unit testing)
    public static func messagesDeleteAll(
        _ db: Database,
        sessionId: String,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .delete,
                    server: server,
                    endpoint: Endpoint.roomDeleteMessages(roomToken, sessionId: sessionId)
                ),
                using: dependencies
            )
    }
    
    // MARK: - Reactions
    
    public static func reactors(
        _ db: Database,
        emoji: String,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<OnionRequestResponseInfoType> {
        /// URL(String:) won't convert raw emojis, so need to do a little encoding here.
        /// The raw emoji will come back when calling url.path
        guard let encodedEmoji: String = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return Promise(error: OpenGroupAPIError.invalidEmoji)
        }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .get,
                    server: server,
                    endpoint: .reactors(roomToken, id: id, emoji: encodedEmoji)
                ),
                using: dependencies
            )
            .map { responseInfo, _ in responseInfo }
    }
    
    public static func reactionAdd(
        _ db: Database,
        emoji: String,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, ReactionAddResponse)> {
        /// URL(String:) won't convert raw emojis, so need to do a little encoding here.
        /// The raw emoji will come back when calling url.path
        guard let encodedEmoji: String = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return Promise(error: OpenGroupAPIError.invalidEmoji)
        }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .put,
                    server: server,
                    endpoint: .reaction(roomToken, id: id, emoji: encodedEmoji)
                ),
                using: dependencies
            )
            .decoded(as: ReactionAddResponse.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    public static func reactionDelete(
        _ db: Database,
        emoji: String,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, ReactionRemoveResponse)> {
        /// URL(String:) won't convert raw emojis, so need to do a little encoding here.
        /// The raw emoji will come back when calling url.path
        guard let encodedEmoji: String = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return Promise(error: OpenGroupAPIError.invalidEmoji)
        }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .delete,
                    server: server,
                    endpoint: .reaction(roomToken, id: id, emoji: encodedEmoji)
                ),
                using: dependencies
            )
            .decoded(as: ReactionRemoveResponse.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    public static func reactionDeleteAll(
        _ db: Database,
        emoji: String,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, ReactionRemoveAllResponse)> {
        /// URL(String:) won't convert raw emojis, so need to do a little encoding here.
        /// The raw emoji will come back when calling url.path
        guard let encodedEmoji: String = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return Promise(error: OpenGroupAPIError.invalidEmoji)
        }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .delete,
                    server: server,
                    endpoint: .reactionDelete(roomToken, id: id, emoji: encodedEmoji)
                ),
                using: dependencies
            )
            .decoded(as: ReactionRemoveAllResponse.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    // MARK: - Pinning
    
    /// Adds a pinned message to this room
    ///
    /// **Note:** Existing pinned messages are not removed: the new message is added to the pinned message list (If you want to remove existing
    /// pins then build a sequence request that first calls .../unpin/all)
    ///
    /// The user must have admin (not just moderator) permissions in the room in order to pin messages
    ///
    /// Pinned messages that are already pinned will be re-pinned (that is, their pin timestamp and pinning admin user will be updated) - because pinned
    /// messages are returned in pinning-order this allows admins to order multiple pinned messages in a room by re-pinning (via this endpoint) in the
    /// order in which pinned messages should be displayed
    public static func pinMessage(
        _ db: Database,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<OnionRequestResponseInfoType> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .post,
                    server: server,
                    endpoint: .roomPinMessage(roomToken, id: id)
                ),
                using: dependencies
            )
            .map { responseInfo, _ in responseInfo }
    }
    
    /// Remove a message from this room's pinned message list
    ///
    /// The user must have `admin` (not just `moderator`) permissions in the room
    public static func unpinMessage(
        _ db: Database,
        id: Int64,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<OnionRequestResponseInfoType> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .post,
                    server: server,
                    endpoint: .roomUnpinMessage(roomToken, id: id)
                ),
                using: dependencies
            )
            .map { responseInfo, _ in responseInfo }
    }

    /// Removes _all_ pinned messages from this room
    ///
    /// The user must have `admin` (not just `moderator`) permissions in the room
    public static func unpinAll(
        _ db: Database,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<OnionRequestResponseInfoType> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    method: .post,
                    server: server,
                    endpoint: .roomUnpinAll(roomToken)
                ),
                using: dependencies
            )
            .map { responseInfo, _ in responseInfo }
    }
    
    // MARK: - Files
    
    public static func uploadFile(
        _ db: Database,
        bytes: [UInt8],
        fileName: String? = nil,
        to roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, FileUploadResponse)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.roomFile(roomToken),
                    headers: [
                        .contentDisposition: [ "attachment", fileName.map { "filename=\"\($0)\"" } ]
                            .compactMap{ $0 }
                            .joined(separator: "; "),
                        .contentType: "application/octet-stream"
                    ],
                    body: bytes
                ),
                using: dependencies
            )
            .decoded(as: FileUploadResponse.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    public static func downloadFile(
        _ db: Database,
        fileId: String,
        from roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .roomFileIndividual(roomToken, fileId)
                ),
                using: dependencies
            )
            .map { responseInfo, maybeData in
                guard let data: Data = maybeData else { throw HTTP.Error.parsingFailed }
                
                return (responseInfo, data)
            }
    }
    
    // MARK: - Inbox/Outbox (Message Requests)

    /// Retrieves all of the user's current DMs (up to limit)
    ///
    /// **Note:** This is the direct request to retrieve DMs for a specific Open Group so should be retrieved automatically from the `poll()`
    /// method, in order to call this directly remove the `@available` line and make sure to route the response of this method to the
    /// `OpenGroupManager.handleDirectMessages` method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func inbox(
        _ db: Database,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [DirectMessage]?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .inbox
                ),
                using: dependencies
            )
            .decoded(as: [DirectMessage]?.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Polls for any DMs received since the given id, this method will return a `304` with an empty response if there are no messages
    ///
    /// **Note:** This is the direct request to retrieve messages requests for a specific Open Group since a given messages so should be retrieved
    /// automatically from the `poll()` method, in order to call this directly remove the `@available` line and make sure to route the response
    /// of this method to the `OpenGroupManager.handleDirectMessages` method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func inboxSince(
        _ db: Database,
        id: Int64,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [DirectMessage]?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .inboxSince(id: id)
                ),
                using: dependencies
            )
            .decoded(as: [DirectMessage]?.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Delivers a direct message to a user via their blinded Session ID
    ///
    /// The body of this request is a JSON object containing a message key with a value of the encrypted-then-base64-encoded message to deliver
    public static func send(
        _ db: Database,
        ciphertext: Data,
        toInboxFor blindedSessionId: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, SendDirectMessageResponse)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.inboxFor(sessionId: blindedSessionId),
                    body: SendDirectMessageRequest(
                        message: ciphertext
                    )
                ),
                using: dependencies
            )
            .decoded(as: SendDirectMessageResponse.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Retrieves all of the user's sent DMs (up to limit)
    ///
    /// **Note:** This is the direct request to retrieve DMs sent by the user for a specific Open Group so should be retrieved automatically
    /// from the `poll()` method, in order to call this directly remove the `@available` line and make sure to route the response of
    /// this method to the `OpenGroupManager.handleDirectMessages` method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func outbox(
        _ db: Database,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [DirectMessage]?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .outbox
                ),
                using: dependencies
            )
            .decoded(as: [DirectMessage]?.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    /// Polls for any DMs sent since the given id, this method will return a `304` with an empty response if there are no messages
    ///
    /// **Note:** This is the direct request to retrieve messages requests sent by the user for a specific Open Group since a given messages so
    /// should be retrieved automatically from the `poll()` method, in order to call this directly remove the `@available` line and make sure
    /// to route the response of this method to the `OpenGroupManager.handleDirectMessages` method to ensure things are processed correctly
    @available(*, unavailable, message: "Avoid using this directly, use the pre-built `poll()` method instead")
    public static func outboxSince(
        _ db: Database,
        id: Int64,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, [DirectMessage]?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request<NoBody, Endpoint>(
                    server: server,
                    endpoint: .outboxSince(id: id)
                ),
                using: dependencies
            )
            .decoded(as: [DirectMessage]?.self, on: OpenGroupAPI.workQueue, using: dependencies)
    }
    
    // MARK: - Users
    
    /// Applies a ban of a user from specific rooms, or from the server globally
    ///
    /// The invoking user must have `moderator` (or `admin`) permission in all given rooms when specifying rooms, and must be a
    /// `globalModerator` (or `globalAdmin`) if using the global parameter
    ///
    /// **Note:** The user's messages are not deleted by this request - In order to ban and delete all messages use the `/sequence` endpoint to
    /// bundle a `/user/.../ban` with a `/user/.../deleteMessages` request
    ///
    /// - Parameters:
    ///   - sessionId: The sessionId (either standard or blinded) of the user whose messages should be deleted
    ///
    ///   - timeout: Value specifying a time limit on the ban, in seconds
    ///
    ///     The applied ban will expire and be removed after the given interval - If omitted (or `null`) then the ban is permanent
    ///
    ///     If this endpoint is called multiple times then the timeout of the last call takes effect (eg. a permanent ban can be replaced
    ///     with a time-limited ban by calling the endpoint again with a timeout value, and vice versa)
    ///
    ///   - roomTokens: List of one or more room tokens from which the user should be banned from
    ///
    ///     The invoking user **must** be a moderator of all of the given rooms.
    ///
    ///     This may be set to the single-element list `["*"]` to ban the user from all rooms in which the current user has moderator
    ///     permissions (the call will succeed if the calling user is a moderator in at least one channel)
    ///
    ///     **Note:** You can ban from all rooms on a server by providing a `nil` value for this parameter (the invoking user must be a
    ///     global moderator in order to add a global ban)
    ///
    ///   - server: The server to delete messages from
    ///
    ///   - dependencies: Injected dependencies (used for unit testing)
    public static func userBan(
        _ db: Database,
        sessionId: String,
        for timeout: TimeInterval? = nil,
        from roomTokens: [String]? = nil,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.userBan(sessionId),
                    body: UserBanRequest(
                        rooms: roomTokens,
                        global: (roomTokens == nil ? true : nil),
                        timeout: timeout
                    )
                ),
                using: dependencies
            )
    }
    
    /// Removes a user ban from specific rooms, or from the server globally
    ///
    /// The invoking user must have `moderator` (or `admin`) permission in all given rooms when specifying rooms, and must be a global server `moderator`
    /// (or `admin`) if using the `global` parameter
    ///
    /// **Note:** Room and global bans are independent: if a user is banned globally and has a room-specific ban then removing the global ban does not remove
    /// the room specific ban, and removing the room-specific ban does not remove the global ban (to fully unban a user globally and from all rooms, submit a
    /// `/sequence` request with a global unban followed by a "rooms": ["*"] unban)
    ///
    /// - Parameters:
    ///   - sessionId: The sessionId (either standard or blinded) of the user whose messages should be deleted
    ///
    ///   - roomTokens: List of one or more room tokens from which the user should be unbanned from
    ///
    ///     The invoking user **must** be a moderator of all of the given rooms.
    ///
    ///     This may be set to the single-element list `["*"]` to unban the user from all rooms in which the current user has moderator
    ///     permissions (the call will succeed if the calling user is a moderator in at least one channel)
    ///
    ///     **Note:** You can ban from all rooms on a server by providing a `nil` value for this parameter
    ///
    ///   - server: The server to delete messages from
    ///
    ///   - dependencies: Injected dependencies (used for unit testing)
    public static func userUnban(
        _ db: Database,
        sessionId: String,
        from roomTokens: [String]?,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.userUnban(sessionId),
                    body: UserUnbanRequest(
                        rooms: roomTokens,
                        global: (roomTokens == nil ? true : nil)
                    )
                ),
                using: dependencies
            )
    }
    
    /// Appoints or removes a moderator or admin
    ///
    /// This endpoint is used to appoint or remove moderator/admin permissions either for specific rooms or for server-wide global moderator permissions
    ///
    /// Admins/moderators of rooms can only be appointed or removed by a user who has admin permissions in the room (including global admins)
    ///
    /// Global admins/moderators may only be appointed by a global admin
    ///
    /// The admin/moderator paramters interact as follows:
    /// - **admin=true, moderator omitted:** This adds admin permissions, which automatically also implies moderator permissions
    /// - **admin=true, moderator=true:** Exactly the same as above
    /// - **admin=false, moderator=true:** Removes any existing admin permissions from the rooms (or globally), if present, and adds
    /// moderator permissions to the rooms/globally (if not already present)
    /// - **admin=false, moderator omitted:** This removes admin permissions but leaves moderator permissions, if present (this
    /// effectively "downgrades" an admin to a moderator).  Unlike the above this does **not** add moderator permissions to matching rooms
    /// if not already present
    /// - **moderator=true, admin omitted:** Adds moderator permissions to the given rooms (or globally), if not already present.  If
    /// the user already has admin permissions this does nothing (that is, admin permission is *not* removed, unlike the above)
    /// - **moderator=false, admin omitted:** This removes moderator **and** admin permissions from all given rooms (or globally)
    /// - **moderator=false, admin=false:** Exactly the same as above
    /// - **moderator=false, admin=true:** This combination is **not permitted** (because admin permissions imply moderator
    /// permissions) and will result in Bad Request error if given
    ///
    /// - Parameters:
    ///   - sessionId: The sessionId (either standard or blinded) of the user to modify the permissions of
    ///
    ///   - moderator: Value indicating that this user should have moderator permissions added (true), removed (false), or left alone (null)
    ///
    ///   - admin: Value indicating that this user should have admin permissions added (true), removed (false), or left alone (null)
    ///
    ///     Granting admin permission automatically includes granting moderator permission (and thus it is an error to use admin=true with
    ///     moderator=false)
    ///
    ///   - visible: Value indicating whether the moderator/admin should be made publicly visible as a moderator/admin of the room(s)
    ///   (if true) or hidden (false)
    ///
    ///     Hidden moderators/admins still have all the same permissions as visible moderators/admins, but are visible only to other
    ///     moderators/admins; regular users in the room will not know their moderator status
    ///
    ///   - roomTokens: List of one or more room tokens to which the permission changes should be applied
    ///
    ///     The invoking user **must** be an admin of all of the given rooms.
    ///
    ///     This may be set to the single-element list `["*"]` to add or remove the moderator from all rooms in which the current user has admin
    ///     permissions (the call will succeed if the calling user is an admin in at least one channel)
    ///
    ///     **Note:** You can specify a change to global permisisons by providing a `nil` value for this parameter
    ///
    ///   - server: The server to perform the permission changes on
    ///
    ///   - dependencies: Injected dependencies (used for unit testing)
    public static func userModeratorUpdate(
        _ db: Database,
        sessionId: String,
        moderator: Bool? = nil,
        admin: Bool? = nil,
        visible: Bool,
        for roomTokens: [String]?,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        guard (moderator != nil && admin == nil) || (moderator == nil && admin != nil) else {
            return Promise(error: HTTP.Error.generic)
        }
        
        return OpenGroupAPI
            .send(
                db,
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: Endpoint.userModerator(sessionId),
                    body: UserModeratorRequest(
                        rooms: roomTokens,
                        global: (roomTokens == nil ? true : nil),
                        moderator: moderator,
                        admin: admin,
                        visible: visible
                    )
                ),
                using: dependencies
            )
    }
    
    /// This is a convenience method which constructs a `/sequence` of the `userBan` and `userDeleteMessages`  requests, refer to those
    /// methods for the documented behaviour of each method
    public static func userBanAndDeleteAllMessages(
        _ db: Database,
        sessionId: String,
        in roomToken: String,
        on server: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<[OnionRequestResponseInfoType]> {
        let banRequestBody: UserBanRequest = UserBanRequest(
            rooms: [roomToken],
            global: nil,
            timeout: nil
        )
        
        // Generate the requests
        let requestResponseType: [BatchRequestInfoType] = [
            BatchRequestInfo(
                request: Request(
                    method: .post,
                    server: server,
                    endpoint: .userBan(sessionId),
                    body: banRequestBody
                )
            ),
            BatchRequestInfo(
                request: Request<NoBody, Endpoint>(
                    method: .delete,
                    server: server,
                    endpoint: Endpoint.roomDeleteMessages(roomToken, sessionId: sessionId)
                )
            )
        ]
        
        return OpenGroupAPI
            .sequence(
                db,
                server: server,
                requests: requestResponseType,
                using: dependencies
            )
            .map { $0.values.map { responseInfo, _ in responseInfo } }
    }
    
    // MARK: - Authentication
    
    /// Sign a message to be sent to SOGS (handles both un-blinded and blinded signing based on the server capabilities)
    private static func sign(
        _ db: Database,
        messageBytes: Bytes,
        for serverName: String,
        fallbackSigningType signingType: SessionId.Prefix,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> (publicKey: String, signature: Bytes)? {
        guard
            let userEdKeyPair: Box.KeyPair = Identity.fetchUserEd25519KeyPair(db),
            let serverPublicKey: String = try? OpenGroup
                .select(.publicKey)
                .filter(OpenGroup.Columns.server == serverName.lowercased())
                .asRequest(of: String.self)
                .fetchOne(db)
        else { return nil }
        
        let capabilities: Set<Capability.Variant> = (try? Capability
            .select(.variant)
            .filter(Capability.Columns.openGroupServer == serverName.lowercased())
            .asRequest(of: Capability.Variant.self)
            .fetchSet(db))
            .defaulting(to: [])

        // Check if the server supports blinded keys, if so then sign using the blinded key
        if capabilities.contains(.blind) {
            guard let blindedKeyPair: Box.KeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: serverPublicKey, edKeyPair: userEdKeyPair, genericHash: dependencies.genericHash) else {
                return nil
            }
            
            guard let signatureResult: Bytes = dependencies.sodium.sogsSignature(message: messageBytes, secretKey: userEdKeyPair.secretKey, blindedSecretKey: blindedKeyPair.secretKey, blindedPublicKey: blindedKeyPair.publicKey) else {
                return nil
            }
            
            return (
                publicKey: SessionId(.blinded, publicKey: blindedKeyPair.publicKey).hexString,
                signature: signatureResult
            )
        }
        
        // Otherwise sign using the fallback type
        switch signingType {
            case .unblinded:
                guard let signatureResult: Bytes = dependencies.sign.signature(message: messageBytes, secretKey: userEdKeyPair.secretKey) else {
                    return nil
                }
                
                return (
                    publicKey: SessionId(.unblinded, publicKey: userEdKeyPair.publicKey).hexString,
                    signature: signatureResult
                )
                
            // Default to using the 'standard' key
            default:
                guard let userKeyPair: Box.KeyPair = Identity.fetchUserKeyPair(db) else { return nil }
                guard let signatureResult: Bytes = try? dependencies.ed25519.sign(data: messageBytes, keyPair: userKeyPair) else {
                    return nil
                }
                
                return (
                    publicKey: SessionId(.standard, publicKey: userKeyPair.publicKey).hexString,
                    signature: signatureResult
                )
        }
    }
    
    /// Sign a request to be sent to SOGS (handles both un-blinded and blinded signing based on the server capabilities)
    private static func sign(
        _ db: Database,
        request: URLRequest,
        for serverName: String,
        with serverPublicKey: String,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> URLRequest? {
        guard let url: URL = request.url else { return nil }
        
        var updatedRequest: URLRequest = request
        let path: String = url.path
            .appending(url.query.map { value in "?\(value)" })
        let method: String = (request.httpMethod ?? "GET")
        let timestamp: Int = Int(floor(dependencies.date.timeIntervalSince1970))
        let nonce: Data = Data(dependencies.nonceGenerator16.nonce())
        
        guard let serverPublicKeyData: Data = serverPublicKey.dataFromHex() else { return nil }
        guard let timestampBytes: Bytes = "\(timestamp)".data(using: .ascii)?.bytes else { return nil }
        
        /// Get a hash of any body content
        let bodyHash: Bytes? = {
            guard let body: Data = request.httpBody else { return nil }
            
            return dependencies.genericHash.hash(message: body.bytes, outputLength: 64)
        }()
        
        /// Generate the signature message
        /// "ServerPubkey || Nonce || Timestamp || Method || Path || Blake2b Hash(Body)
        ///     `ServerPubkey`
        ///     `Nonce`
        ///     `Timestamp` is the bytes of an ascii decimal string
        ///     `Method`
        ///     `Path`
        ///     `Body` is a Blake2b hash of the data (if there is a body)
        let messageBytes: Bytes = serverPublicKeyData.bytes
            .appending(contentsOf: nonce.bytes)
            .appending(contentsOf: timestampBytes)
            .appending(contentsOf: method.bytes)
            .appending(contentsOf: path.bytes)
            .appending(contentsOf: bodyHash ?? [])
        
        /// Sign the above message
        guard let signResult: (publicKey: String, signature: Bytes) = sign(db, messageBytes: messageBytes, for: serverName, fallbackSigningType: .unblinded, using: dependencies) else {
            return nil
        }
        
        updatedRequest.allHTTPHeaderFields = (request.allHTTPHeaderFields ?? [:])
            .updated(with: [
                Header.sogsPubKey.rawValue: signResult.publicKey,
                Header.sogsTimestamp.rawValue: "\(timestamp)",
                Header.sogsNonce.rawValue: nonce.base64EncodedString(),
                Header.sogsSignature.rawValue: signResult.signature.toBase64()
            ])
        
        return updatedRequest
    }
    
    // MARK: - Convenience
    
    private static func send<T: Encodable>(
        _ db: Database,
        request: Request<T, Endpoint>,
        authenticated: Bool = true,
        using dependencies: SMKDependencies = SMKDependencies()
    ) -> Promise<(OnionRequestResponseInfoType, Data?)> {
        let urlRequest: URLRequest
        
        do {
            urlRequest = try request.generateUrlRequest()
        }
        catch {
            return Promise(error: error)
        }
        
        let maybePublicKey: String? = try? OpenGroup
            .select(.publicKey)
            .filter(OpenGroup.Columns.server == request.server.lowercased())
            .asRequest(of: String.self)
            .fetchOne(db)
        
        guard let publicKey: String = maybePublicKey else { return Promise(error: OpenGroupAPIError.noPublicKey) }
        
        // If we don't want to authenticate the request then send it immediately
        guard authenticated else {
            return dependencies.onionApi.sendOnionRequest(urlRequest, to: request.server, with: publicKey)
        }
        
        // Attempt to sign the request with the new auth
        guard let signedRequest: URLRequest = sign(db, request: urlRequest, for: request.server, with: publicKey, using: dependencies) else {
            return Promise(error: OpenGroupAPIError.signingFailed)
        }
        
        return dependencies.onionApi.sendOnionRequest(signedRequest, to: request.server, with: publicKey)
    }
}
