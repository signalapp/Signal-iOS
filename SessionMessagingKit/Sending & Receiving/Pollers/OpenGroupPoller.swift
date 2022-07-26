// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

extension OpenGroupAPI {
    public final class Poller {
        private let server: String
        private var timer: Timer? = nil
        private var hasStarted = false
        private var isPolling = false

        // MARK: - Settings
        
        private static let pollInterval: TimeInterval = 4
        internal static let maxInactivityPeriod: Double = (14 * 24 * 60 * 60)
        
        // MARK: - Lifecycle
        
        public init(for server: String) {
            self.server = server
        }
        
        public func startIfNeeded(using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()) {
            guard !hasStarted else { return }
            
            hasStarted = true
            timer = Timer.scheduledTimerOnMainThread(withTimeInterval: Poller.pollInterval, repeats: true) { _ in
                self.poll(using: dependencies).retainUntilComplete()
            }
            poll(using: dependencies).retainUntilComplete()
        }

        @objc public func stop() {
            timer?.invalidate()
            hasStarted = false
        }

        // MARK: - Polling
        
        @discardableResult
        public func poll(using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()) -> Promise<Void> {
            return poll(isBackgroundPoll: false, isPostCapabilitiesRetry: false, using: dependencies)
        }

        @discardableResult
        public func poll(
            isBackgroundPoll: Bool,
            isPostCapabilitiesRetry: Bool,
            using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()
        ) -> Promise<Void> {
            guard !self.isPolling else { return Promise.value(()) }
            
            self.isPolling = true
            let server: String = self.server
            let (promise, seal) = Promise<Void>.pending()
            promise.retainUntilComplete()
            
            Threading.pollerQueue.async {
                dependencies.storage
                    .read { db in
                        OpenGroupAPI
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
                    }
                    .done(on: OpenGroupAPI.workQueue) { [weak self] response in
                        self?.isPolling = false
                        self?.handlePollResponse(response, isBackgroundPoll: isBackgroundPoll, using: dependencies)
                        
                        dependencies.mutableCache.mutate { cache in
                            cache.hasPerformedInitialPoll[server] = true
                            cache.timeSinceLastPoll[server] = Date().timeIntervalSince1970
                            UserDefaults.standard[.lastOpen] = Date()
                        }
                        SNLog("Open group polling finished for \(server).")
                        seal.fulfill(())
                    }
                    .catch(on: OpenGroupAPI.workQueue) { [weak self] error in
                        // If we are retrying then the error is being handled so no need to continue (this
                        // method will always resolve)
                        self?.updateCapabilitiesAndRetryIfNeeded(
                            server: server,
                            isBackgroundPoll: isBackgroundPoll,
                            isPostCapabilitiesRetry: isPostCapabilitiesRetry,
                            error: error
                        )
                        .done(on: OpenGroupAPI.workQueue) { [weak self] didHandleError in
                            if !didHandleError {
                                SNLog("Open group polling failed due to error: \(error).")
                            }
                            
                            self?.isPolling = false
                            seal.fulfill(()) // The promise is just used to keep track of when we're done
                        }
                        .retainUntilComplete()
                    }
            }
            
            return promise
        }
        
        private func updateCapabilitiesAndRetryIfNeeded(
            server: String,
            isBackgroundPoll: Bool,
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
                dataString.contains("Invalid authentication: this server requires the use of blinded idse")
            else { return Promise.value(false) }
            
            let (promise, seal) = Promise<Bool>.pending()
            
            dependencies.storage
                .read { db in
                    OpenGroupAPI.capabilities(
                        db,
                        server: server,
                        authenticated: false,
                        using: dependencies
                    )
                }
                .then(on: OpenGroupAPI.workQueue) { [weak self] _, responseBody -> Promise<Void> in
                    guard let strongSelf = self else { return Promise.value(()) }
                    
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
                        isBackgroundPoll: isBackgroundPoll,
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
        
        private func handlePollResponse(_ response: [OpenGroupAPI.Endpoint: (info: OnionRequestResponseInfoType, data: Codable?)], isBackgroundPoll: Bool, using dependencies: OpenGroupManager.OGMDependencies = OpenGroupManager.OGMDependencies()) {
            let server: String = self.server
            
            dependencies.storage.write { db in
                try response.forEach { endpoint, endpointResponse in
                    switch endpoint {
                        case .capabilities:
                            guard let responseData: BatchSubResponse<Capabilities> = endpointResponse.data as? BatchSubResponse<Capabilities>, let responseBody: Capabilities = responseData.body else {
                                SNLog("Open group polling failed due to invalid capability data.")
                                return
                            }
                            
                            OpenGroupManager.handleCapabilities(
                                db,
                                capabilities: responseBody,
                                on: server
                            )
                            
                        case .roomPollInfo(let roomToken, _):
                            guard let responseData: BatchSubResponse<RoomPollInfo> = endpointResponse.data as? BatchSubResponse<RoomPollInfo>, let responseBody: RoomPollInfo = responseData.body else {
                                SNLog("Open group polling failed due to invalid room info data.")
                                return
                            }
                            
                            try OpenGroupManager.handlePollInfo(
                                db,
                                pollInfo: responseBody,
                                publicKey: nil,
                                for: roomToken,
                                on: server,
                                dependencies: dependencies
                            )
                            
                        case .roomMessagesRecent(let roomToken), .roomMessagesBefore(let roomToken, _), .roomMessagesSince(let roomToken, _):
                            guard let responseData: BatchSubResponse<[Failable<Message>]> = endpointResponse.data as? BatchSubResponse<[Failable<Message>]>, let responseBody: [Failable<Message>] = responseData.body else {
                                SNLog("Open group polling failed due to invalid messages data.")
                                return
                            }
                            let successfulMessages: [Message] = responseBody.compactMap { $0.value }
                            
                            if successfulMessages.count != responseBody.count {
                                let droppedCount: Int = (responseBody.count - successfulMessages.count)
                                
                                SNLog("Dropped \(droppedCount) invalid open group message\(droppedCount == 1 ? "" : "s").")
                            }
                            
                            OpenGroupManager.handleMessages(
                                db,
                                messages: successfulMessages,
                                for: roomToken,
                                on: server,
                                isBackgroundPoll: isBackgroundPoll,
                                dependencies: dependencies
                            )
                            
                        case .inbox, .inboxSince, .outbox, .outboxSince:
                            guard let responseData: BatchSubResponse<[DirectMessage]?> = endpointResponse.data as? BatchSubResponse<[DirectMessage]?>, !responseData.failedToParseBody else {
                                SNLog("Open group polling failed due to invalid inbox/outbox data.")
                                return
                            }
                            
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
                                isBackgroundPoll: isBackgroundPoll,
                                dependencies: dependencies
                            )
                            
                        default: break // No custom handling needed
                    }
                }
            }
        }
    }
}
