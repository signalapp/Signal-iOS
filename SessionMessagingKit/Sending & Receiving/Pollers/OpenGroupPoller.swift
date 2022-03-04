import PromiseKit
import SessionSnodeKit

extension OpenGroupAPI {
    public final class Poller {
        private let server: String
        private var timer: Timer? = nil
        private var hasStarted = false
        private var isPolling = false

        // MARK: - Settings
        
        internal static let maxInactivityPeriod: Double = (14 * 24 * 60 * 60)
        private static let pollInterval: TimeInterval = 4
        
        // MARK: - Lifecycle
        
        public init(for server: String) {
            self.server = server
        }

        @objc public func startIfNeeded() {
            guard !hasStarted else { return }
            
            DispatchQueue.main.async { [weak self] in // Timers don't do well on background queues
                self?.hasStarted = true
                self?.timer = Timer.scheduledTimer(withTimeInterval: Poller.pollInterval, repeats: true) { _ in
                    DispatchQueue.global().async {
                        self?.poll().retainUntilComplete()
                    }
                }
                DispatchQueue.global().async {
                    self?.poll().retainUntilComplete()
                }
            }
        }

        @objc public func stop() {
            timer?.invalidate()
            hasStarted = false
        }

        // MARK: - Polling
        
        @discardableResult
        public func poll() -> Promise<Void> {
            return poll(isBackgroundPoll: false)
        }

        @discardableResult
        public func poll(isBackgroundPoll: Bool) -> Promise<Void> {
            guard !self.isPolling else { return Promise.value(()) }
            
            self.isPolling = true
            let (promise, seal) = Promise<Void>.pending()
            promise.retainUntilComplete()
            
            OpenGroupAPI.poll(server)
                .done(on: OpenGroupAPI.workQueue) { [weak self] response in
                    self?.isPolling = false
                    self?.handlePollResponse(response, isBackgroundPoll: isBackgroundPoll)
                    seal.fulfill(())
                }
                .catch(on: OpenGroupAPI.workQueue) { [weak self] error in
                    SNLog("Open group polling failed due to error: \(error).")
                    self?.isPolling = false
                    seal.fulfill(()) // The promise is just used to keep track of when we're done
                }
            
            return promise
        }
        
        private func handlePollResponse(_ response: [OpenGroupAPI.Endpoint: (info: OnionRequestResponseInfoType, data: Codable?)], isBackgroundPoll: Bool) {
            let server: String = self.server
            
            Storage.shared.write { anyTransaction in
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
                                using: transaction
                            )
                            
                        case .roomMessagesRecent(let roomToken), .roomMessagesBefore(let roomToken, _), .roomMessagesSince(let roomToken, _):
                            guard let responseData: BatchSubResponse<[Message]> = endpointResponse.data as? BatchSubResponse<[Message]>, let responseBody: [Message] = responseData.body else {
                                SNLog("Open group polling failed due to invalid data.")
                                return
                            }
                            
                            OpenGroupManager.handleMessages(
                                responseBody,
                                for: roomToken,
                                on: server,
                                isBackgroundPoll: isBackgroundPoll,
                                using: transaction
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
                                using: transaction
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
                                using: transaction
                            )
                            
                        default: break // No custom handling needed
                    }
                }
            }
        }
    }
}
