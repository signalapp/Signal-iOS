// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

extension OpenGroupAPI {
    public final class Poller {
        typealias PollResponse = [OpenGroupAPI.Endpoint: (info: OnionRequestResponseInfoType, data: Codable?)]
        
        private let server: String
        private var timer: Timer? = nil
        private var hasStarted = false
        private var isPolling = false

        // MARK: - Settings
        
        private static let minPollInterval: TimeInterval = 3
        private static let maxPollInterval: Double = (60 * 60)
        internal static let maxInactivityPeriod: Double = (14 * 24 * 60 * 60)
        
        // MARK: - Lifecycle
        
        public init(for server: String) {
            self.server = server
        }
        
        public func startIfNeeded(using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()) {
            guard !hasStarted else { return }
            
            hasStarted = true
            pollRecursively(using: dependencies)
        }

        @objc public func stop() {
            timer?.invalidate()
            hasStarted = false
        }

        // MARK: - Polling
        
        private func pollRecursively(using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()) {
            guard hasStarted else { return }
            
            let minPollFailureCount: TimeInterval = Storage.shared
                .read { db in
                    try OpenGroup
                        .filter(OpenGroup.Columns.server == server)
                        .select(min(OpenGroup.Columns.pollFailureCount))
                        .asRequest(of: TimeInterval.self)
                        .fetchOne(db)
                }
                .defaulting(to: 0)
            let nextPollInterval: TimeInterval = getInterval(for: minPollFailureCount, minInterval: Poller.minPollInterval, maxInterval: Poller.maxPollInterval)
            
            poll(using: dependencies).retainUntilComplete()
            timer = Timer.scheduledTimerOnMainThread(withTimeInterval: nextPollInterval, repeats: false) { [weak self] timer in
                timer.invalidate()
                
                Threading.pollerQueue.async {
                    self?.pollRecursively(using: dependencies)
                }
            }
        }
        
        @discardableResult
        public func poll(using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()) -> Promise<Void> {
            return poll(calledFromBackgroundPoller: false, isPostCapabilitiesRetry: false, using: dependencies)
        }

        @discardableResult
        public func poll(
            calledFromBackgroundPoller: Bool,
            isBackgroundPollerValid: @escaping (() -> Bool) = { true },
            isPostCapabilitiesRetry: Bool,
            using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()
        ) -> Promise<Void> {
            guard !self.isPolling else { return Promise.value(()) }
            
            self.isPolling = true
            let server: String = self.server
            let (promise, seal) = Promise<Void>.pending()
            promise.retainUntilComplete()
            
            let pollingLogic: () -> Void = {
                dependencies.storage
                    .read { db -> Promise<(Int64, PollResponse)> in
                        let failureCount: Int64 = (try? OpenGroup
                            .select(max(OpenGroup.Columns.pollFailureCount))
                            .asRequest(of: Int64.self)
                            .fetchOne(db))
                            .defaulting(to: 0)
                        
                        return OpenGroupAPI
                            .poll(
                                db,
                                server: server,
                                hasPerformedInitialPoll: dependencies.cache.hasPerformedInitialPoll[server] == true,
                                timeSinceLastPoll: (
                                    dependencies.cache.timeSinceLastPoll[server] ??
                                    dependencies.cache.getTimeSinceLastOpen(using: dependencies)
                                ),
                                using: dependencies
                            )
                            .map(on: OpenGroupAPI.workQueue) { (failureCount, $0) }
                    }
                    .done(on: OpenGroupAPI.workQueue) { [weak self] failureCount, response in
                        guard !calledFromBackgroundPoller || isBackgroundPollerValid() else {
                            // If this was a background poll and the background poll is no longer valid
                            // then just stop
                            self?.isPolling = false
                            seal.fulfill(())
                            return
                        }
                        
                        self?.isPolling = false
                        self?.handlePollResponse(
                            response,
                            failureCount: failureCount,
                            using: dependencies
                        )
                        
                        dependencies.mutableCache.mutate { cache in
                            cache.hasPerformedInitialPoll[server] = true
                            cache.timeSinceLastPoll[server] = Date().timeIntervalSince1970
                            UserDefaults.standard[.lastOpen] = Date()
                        }
                        
                        SNLog("Open group polling finished for \(server).")
                        seal.fulfill(())
                    }
                    .catch(on: OpenGroupAPI.workQueue) { [weak self] error in
                        guard !calledFromBackgroundPoller || isBackgroundPollerValid() else {
                            // If this was a background poll and the background poll is no longer valid
                            // then just stop
                            self?.isPolling = false
                            seal.fulfill(())
                            return
                        }
                        
                        // If we are retrying then the error is being handled so no need to continue (this
                        // method will always resolve)
                        self?.updateCapabilitiesAndRetryIfNeeded(
                            server: server,
                            calledFromBackgroundPoller: calledFromBackgroundPoller,
                            isBackgroundPollerValid: isBackgroundPollerValid,
                            isPostCapabilitiesRetry: isPostCapabilitiesRetry,
                            error: error
                        )
                        .done(on: OpenGroupAPI.workQueue) { [weak self] didHandleError in
                            if !didHandleError && isBackgroundPollerValid() {
                                // Increase the failure count
                                let pollFailureCount: Int64 = Storage.shared
                                    .read { db in
                                        try OpenGroup
                                            .filter(OpenGroup.Columns.server == server)
                                            .select(max(OpenGroup.Columns.pollFailureCount))
                                            .asRequest(of: Int64.self)
                                            .fetchOne(db)
                                    }
                                    .defaulting(to: 0)
                                
                                Storage.shared.writeAsync { db in
                                    try OpenGroup
                                        .filter(OpenGroup.Columns.server == server)
                                        .updateAll(
                                            db,
                                            OpenGroup.Columns.pollFailureCount.set(to: (pollFailureCount + 1))
                                        )
                                }
                                
                                SNLog("Open group polling failed due to error: \(error). Setting failure count to \(pollFailureCount).")
                            }
                            
                            self?.isPolling = false
                            seal.fulfill(()) // The promise is just used to keep track of when we're done
                        }
                        .retainUntilComplete()
                    }
            }
            
            // If this was run via the background poller then don't run on the pollerQueue
            if calledFromBackgroundPoller {
                pollingLogic()
            }
            else {
                Threading.pollerQueue.async { pollingLogic() }
            }
            
            return promise
        }
        
        private func updateCapabilitiesAndRetryIfNeeded(
            server: String,
            calledFromBackgroundPoller: Bool,
            isBackgroundPollerValid: @escaping (() -> Bool) = { true },
            isPostCapabilitiesRetry: Bool,
            error: Error,
            using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()
        ) -> Promise<Bool> {
            /// We want to custom handle a '400' error code due to not having blinded auth as it likely means that we join the
            /// OpenGroup before blinding was enabled and need to update it's capabilities
            ///
            /// **Note:** To prevent an infinite loop caused by a server-side bug we want to prevent this capabilities request from
            /// happening multiple times in a row
            guard
                !isPostCapabilitiesRetry,
                let error: OnionRequestAPIError = error as? OnionRequestAPIError,
                case .httpRequestFailedAtDestination(let statusCode, let data, _) = error,
                statusCode == 400,
                let dataString: String = String(data: data, encoding: .utf8),
                dataString.contains("Invalid authentication: this server requires the use of blinded ids")
            else { return Promise.value(false) }
            
            let (promise, seal) = Promise<Bool>.pending()
            
            dependencies.storage
                .read { db in
                    OpenGroupAPI.capabilities(
                        db,
                        server: server,
                        forceBlinded: true,
                        using: dependencies
                    )
                }
                .then(on: OpenGroupAPI.workQueue) { [weak self] _, responseBody -> Promise<Void> in
                    guard let strongSelf = self, isBackgroundPollerValid() else { return Promise.value(()) }
                    
                    // Handle the updated capabilities and re-trigger the poll
                    strongSelf.isPolling = false
                    
                    dependencies.storage.write { db in
                        OpenGroupManager.handleCapabilities(
                            db,
                            capabilities: responseBody,
                            on: server
                        )
                    }
                    
                    // Regardless of the outcome we can just resolve this
                    // immediately as it'll handle it's own response
                    return strongSelf.poll(
                        calledFromBackgroundPoller: calledFromBackgroundPoller,
                        isBackgroundPollerValid: isBackgroundPollerValid,
                        isPostCapabilitiesRetry: true,
                        using: dependencies
                    )
                    .ensure { seal.fulfill(true) }
                }
                .catch(on: OpenGroupAPI.workQueue) { error in
                    SNLog("Open group updating capabilities failed due to error: \(error).")
                    seal.fulfill(true)
                }
                .retainUntilComplete()
            
            return promise
        }
        
        private func handlePollResponse(
            _ response: PollResponse,
            failureCount: Int64,
            using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()
        ) {
            let server: String = self.server
            let validResponses: PollResponse = response
                .filter { endpoint, endpointResponse in
                    switch endpoint {
                        case .capabilities:
                            guard (endpointResponse.data as? BatchSubResponse<Capabilities>)?.body != nil else {
                                SNLog("Open group polling failed due to invalid capability data.")
                                return false
                            }
                            
                            return true
                            
                        case .roomPollInfo(let roomToken, _):
                            guard (endpointResponse.data as? BatchSubResponse<RoomPollInfo>)?.body != nil else {
                                switch (endpointResponse.data as? BatchSubResponse<RoomPollInfo>)?.code {
                                    case 404: SNLog("Open group polling failed to retrieve info for unknown room '\(roomToken)'.")
                                    default: SNLog("Open group polling failed due to invalid room info data.")
                                }
                                return false
                            }
                            
                            return true
                            
                        case .roomMessagesRecent(let roomToken), .roomMessagesBefore(let roomToken, _), .roomMessagesSince(let roomToken, _):
                            guard
                                let responseData: BatchSubResponse<[Failable<Message>]> = endpointResponse.data as? BatchSubResponse<[Failable<Message>]>,
                                let responseBody: [Failable<Message>] = responseData.body
                            else {
                                switch (endpointResponse.data as? BatchSubResponse<[Failable<Message>]>)?.code {
                                    case 404: SNLog("Open group polling failed to retrieve messages for unknown room '\(roomToken)'.")
                                    default: SNLog("Open group polling failed due to invalid messages data.")
                                }
                                return false
                            }
                            
                            let successfulMessages: [Message] = responseBody.compactMap { $0.value }
                            
                            if successfulMessages.count != responseBody.count {
                                let droppedCount: Int = (responseBody.count - successfulMessages.count)
                                
                                SNLog("Dropped \(droppedCount) invalid open group message\(droppedCount == 1 ? "" : "s").")
                            }
                            
                            return !successfulMessages.isEmpty
                            
                        case .inbox, .inboxSince, .outbox, .outboxSince:
                            guard
                                let responseData: BatchSubResponse<[DirectMessage]?> = endpointResponse.data as? BatchSubResponse<[DirectMessage]?>,
                                !responseData.failedToParseBody
                            else {
                                SNLog("Open group polling failed due to invalid inbox/outbox data.")
                                return false
                            }
                            
                            // Double optional because the server can return a `304` with an empty body
                            let messages: [OpenGroupAPI.DirectMessage] = ((responseData.body ?? []) ?? [])
                            
                            return !messages.isEmpty
                            
                        default: return false // No custom handling needed
                    }
                }
            
            // If there are no remaining 'validResponses' and there hasn't been a failure then there is
            // no need to do anything else
            guard !validResponses.isEmpty || failureCount != 0 else { return }
            
            // Retrieve the current capability & group info to check if anything changed
            let rooms: [String] = validResponses
                .keys
                .compactMap { endpoint -> String? in
                    switch endpoint {
                        case .roomPollInfo(let roomToken, _): return roomToken
                        default: return nil
                    }
                }
            let currentInfo: (capabilities: Capabilities, groups: [OpenGroup])? = dependencies.storage.read { db in
                let allCapabilities: [Capability] = try Capability
                    .filter(Capability.Columns.openGroupServer == server)
                    .fetchAll(db)
                let capabilities: Capabilities = Capabilities(
                    capabilities: allCapabilities
                        .filter { !$0.isMissing }
                        .map { $0.variant },
                    missing: {
                        let missingCapabilities: [Capability.Variant] = allCapabilities
                            .filter { $0.isMissing }
                            .map { $0.variant }
                        
                        return (missingCapabilities.isEmpty ? nil : missingCapabilities)
                    }()
                )
                let openGroupIds: [String] = rooms
                    .map { OpenGroup.idFor(roomToken: $0, server: server) }
                let groups: [OpenGroup] = try OpenGroup
                    .filter(ids: openGroupIds)
                    .fetchAll(db)
                
                return (capabilities, groups)
            }
            let changedResponses: PollResponse = validResponses
                .filter { endpoint, endpointResponse in
                    switch endpoint {
                        case .capabilities:
                            guard
                                let responseData: BatchSubResponse<Capabilities> = endpointResponse.data as? BatchSubResponse<Capabilities>,
                                let responseBody: Capabilities = responseData.body
                            else { return false }
                            
                            return (responseBody != currentInfo?.capabilities)
                            
                        case .roomPollInfo(let roomToken, _):
                            guard
                                let responseData: BatchSubResponse<RoomPollInfo> = endpointResponse.data as? BatchSubResponse<RoomPollInfo>,
                                let responseBody: RoomPollInfo = responseData.body
                            else { return false }
                            guard let existingOpenGroup: OpenGroup = currentInfo?.groups.first(where: { $0.roomToken == roomToken }) else {
                                return true
                            }
                            
                            // Note: This might need to be updated in the future when we start tracking
                            // user permissions if changes to permissions don't trigger a change to
                            // the 'infoUpdates'
                            return (
                                responseBody.activeUsers != existingOpenGroup.userCount || (
                                    responseBody.details != nil &&
                                    responseBody.details?.infoUpdates != existingOpenGroup.infoUpdates
                                )
                            )
                        
                        default: return true
                    }
                }
            
            // If there are no 'changedResponses' and there hasn't been a failure then there is
            // no need to do anything else
            guard !changedResponses.isEmpty || failureCount != 0 else { return }
            
            dependencies.storage.write { db in
                // Reset the failure count
                if failureCount > 0 {
                    try OpenGroup
                        .filter(OpenGroup.Columns.server == server)
                        .updateAll(db, OpenGroup.Columns.pollFailureCount.set(to: 0))
                }
                
                try changedResponses.forEach { endpoint, endpointResponse in
                    switch endpoint {
                        case .capabilities:
                            guard
                                let responseData: BatchSubResponse<Capabilities> = endpointResponse.data as? BatchSubResponse<Capabilities>,
                                let responseBody: Capabilities = responseData.body
                            else { return }
                            
                            OpenGroupManager.handleCapabilities(
                                db,
                                capabilities: responseBody,
                                on: server
                            )
                            
                        case .roomPollInfo(let roomToken, _):
                            guard
                                let responseData: BatchSubResponse<RoomPollInfo> = endpointResponse.data as? BatchSubResponse<RoomPollInfo>,
                                let responseBody: RoomPollInfo = responseData.body
                            else { return }
                            
                            try OpenGroupManager.handlePollInfo(
                                db,
                                pollInfo: responseBody,
                                publicKey: nil,
                                for: roomToken,
                                on: server,
                                dependencies: dependencies
                            )
                            
                        case .roomMessagesRecent(let roomToken), .roomMessagesBefore(let roomToken, _), .roomMessagesSince(let roomToken, _):
                            guard
                                let responseData: BatchSubResponse<[Failable<Message>]> = endpointResponse.data as? BatchSubResponse<[Failable<Message>]>,
                                let responseBody: [Failable<Message>] = responseData.body
                            else { return }
                            
                            OpenGroupManager.handleMessages(
                                db,
                                messages: responseBody.compactMap { $0.value },
                                for: roomToken,
                                on: server,
                                dependencies: dependencies
                            )
                            
                        case .inbox, .inboxSince, .outbox, .outboxSince:
                            guard
                                let responseData: BatchSubResponse<[DirectMessage]?> = endpointResponse.data as? BatchSubResponse<[DirectMessage]?>,
                                !responseData.failedToParseBody
                            else { return }
                            
                            // Double optional because the server can return a `304` with an empty body
                            let messages: [OpenGroupAPI.DirectMessage] = ((responseData.body ?? []) ?? [])
                            let fromOutbox: Bool = {
                                switch endpoint {
                                    case .outbox, .outboxSince: return true
                                    default: return false
                                }
                            }()
                            
                            OpenGroupManager.handleDirectMessages(
                                db,
                                messages: messages,
                                fromOutbox: fromOutbox,
                                on: server,
                                dependencies: dependencies
                            )
                            
                        default: break // No custom handling needed
                    }
                }
            }
        }
    }
    
    // MARK: - Convenience

    fileprivate static func getInterval(for failureCount: TimeInterval, minInterval: TimeInterval, maxInterval: TimeInterval) -> TimeInterval {
        // Arbitrary backoff factor...
        return min(maxInterval, minInterval + pow(2, failureCount))
    }
}
