import PromiseKit
import SessionSnodeKit

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
        
        public func startIfNeeded(using dependencies: Dependencies = Dependencies()) {
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
        public func poll(using dependencies: Dependencies = Dependencies()) -> Promise<Void> {
            return poll(isBackgroundPoll: false, using: dependencies)
        }

        @discardableResult
        public func poll(isBackgroundPoll: Bool, using dependencies: Dependencies = Dependencies()) -> Promise<Void> {
            guard !self.isPolling else { return Promise.value(()) }
            
            self.isPolling = true
            let server: String = self.server
            let (promise, seal) = Promise<Void>.pending()
            promise.retainUntilComplete()
            
            Threading.pollerQueue.async {
                OpenGroupAPI
                    .poll(
                        server,
                        hasPerformedInitialPoll: OpenGroupManager.shared.cache.hasPerformedInitialPoll[server] == true,
                        timeSinceLastPoll: (
                            OpenGroupManager.shared.cache.timeSinceLastPoll[server] ??
                            OpenGroupManager.shared.cache.getTimeSinceLastOpen(using: dependencies)
                        ),
                        using: dependencies
                    )
                    .done(on: OpenGroupAPI.workQueue) { [weak self] response in
                        self?.isPolling = false
                        self?.handlePollResponse(response, isBackgroundPoll: isBackgroundPoll, using: dependencies)
                        
                        OpenGroupManager.shared.mutableCache.mutate { cache in
                            cache.hasPerformedInitialPoll[server] = true
                            cache.timeSinceLastPoll[server] = Date().timeIntervalSince1970
                            UserDefaults.standard[.lastOpen] = Date()
                        }
                        seal.fulfill(())
                    }
                    .catch(on: OpenGroupAPI.workQueue) { [weak self] error in
                        SNLog("Open group polling failed due to error: \(error).")
                        self?.isPolling = false
                        seal.fulfill(()) // The promise is just used to keep track of when we're done
                    }
            }
            
            return promise
        }
        
        private func handlePollResponse(_ response: [OpenGroupAPI.Endpoint: (info: OnionRequestResponseInfoType, data: Codable?)], isBackgroundPoll: Bool, using dependencies: Dependencies = Dependencies()) {
            let server: String = self.server
            
            dependencies.storage.write { anyTransaction in
                guard let transaction: YapDatabaseReadWriteTransaction = anyTransaction as? YapDatabaseReadWriteTransaction else {
                    SNLog("Open group polling failed due to invalid database transaction.")
                    return
                }
                
                response.forEach { endpoint, endpointResponse in
                    switch endpoint {
                        case .capabilities:
                            guard let responseData: BatchSubResponse<Capabilities> = endpointResponse.data as? BatchSubResponse<Capabilities>, let responseBody: Capabilities = responseData.body else {
                                SNLog("Open group polling failed due to invalid data.")
                                return
                            }
                            
                            OpenGroupManager.handleCapabilities(
                                responseBody,
                                on: server,
                                using: transaction,
                                dependencies: dependencies
                            )
                            
                        case .roomMessagesRecent(let roomToken), .roomMessagesBefore(let roomToken, _), .roomMessagesSince(let roomToken, _):
                            guard let responseData: BatchSubResponse<[Failable<Message>]> = endpointResponse.data as? BatchSubResponse<[Failable<Message>]>, let responseBody: [Failable<Message>] = responseData.body else {
                                SNLog("Open group polling failed due to invalid data.")
                                return
                            }
                            let successfulMessages: [Message] = responseBody.compactMap { $0.value }
                            
                            if successfulMessages.count != responseBody.count {
                                let droppedCount: Int = (responseBody.count - successfulMessages.count)
                                
                                SNLog("Dropped \(droppedCount) invalid open group message\(droppedCount == 1 ? "" : "s").")
                            }
                            
                            OpenGroupManager.handleMessages(
                                successfulMessages,
                                for: roomToken,
                                on: server,
                                isBackgroundPoll: isBackgroundPoll,
                                using: transaction,
                                dependencies: dependencies
                            )
                            
                        case .roomPollInfo(let roomToken, _):
                            guard let responseData: BatchSubResponse<RoomPollInfo> = endpointResponse.data as? BatchSubResponse<RoomPollInfo>, let responseBody: RoomPollInfo = responseData.body else {
                                SNLog("Open group polling failed due to invalid data.")
                                return
                            }
                            
                            OpenGroupManager.handlePollInfo(
                                responseBody,
                                publicKey: nil,
                                for: roomToken,
                                on: server,
                                using: transaction,
                                dependencies: dependencies
                            )
                            
                        case .inbox, .inboxSince, .outbox, .outboxSince:
                            guard let responseData: BatchSubResponse<[DirectMessage]?> = endpointResponse.data as? BatchSubResponse<[DirectMessage]?>, !responseData.failedToParseBody else {
                                SNLog("Open group polling failed due to invalid data.")
                                return
                            }
                            
                            let fromOutbox: Bool = {
                                switch endpoint {
                                    case .outbox, .outboxSince: return true
                                    default: return false
                                }
                            }()
                            
                            OpenGroupManager.handleDirectMessages(
                                ((responseData.body ?? []) ?? []),  // Double optional because the server can return a `304` with an empty body
                                fromOutbox: fromOutbox,
                                on: server,
                                isBackgroundPoll: isBackgroundPoll,
                                using: transaction,
                                dependencies: dependencies
                            )
                            
                        default: break // No custom handling needed
                    }
                }
            }
        }
    }
}

extension OpenGroupAPI.Poller {
    @objc(startIfNeeded)
    public func objc_startIfNeeded() {
        startIfNeeded()
    }
}
