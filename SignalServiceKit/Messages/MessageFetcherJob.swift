//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: -

public class MessageFetcherJob: NSObject {

    private let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        super.init()

        SwiftSingletons.register(self)

        if CurrentAppContext().shouldProcessIncomingMessages && CurrentAppContext().isMainApp {
            appReadiness.runNowOrWhenAppDidBecomeReadySync {
                // Fetch messages as soon as possible after launching. In particular, when
                // launching from the background, without this, we end up waiting some extra
                // seconds before receiving an actionable push notification.
                if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
                    firstly(on: DispatchQueue.main) {
                        self.run()
                    }.catch(on: DispatchQueue.global()) { error in
                        owsFailDebugUnlessNetworkFailure(error)
                    }
                }
            }
        }
    }

    private static let didChangeStateNotificationName = Notification.Name("MessageFetcherJob.didChangeStateNotificationName")

    // MARK: -

    private var isFetching = false
    private var pendingFetch: (Promise<Void>, Future<Void>)?

    public func run() -> Promise<Void> {
        AssertIsOnMainThread()
        if let (fetchPromise, _) = self.pendingFetch {
            return fetchPromise
        }
        let (fetchPromise, fetchFuture) = Promise<Void>.pending()
        self.pendingFetch = (fetchPromise, fetchFuture)
        self.startFetchingIfNeeded()
        return fetchPromise
    }

    private func startFetchingIfNeeded() {
        AssertIsOnMainThread()

        if self.isFetching {
            return
        }

        guard let (_, fetchFuture) = self.pendingFetch else {
            return
        }
        self.pendingFetch = nil

        self.isFetching = true
        Task { @MainActor in
            defer {
                self.isFetching = false
                self.startFetchingIfNeeded()
            }
            do {
                try await self.pendingAcksPromise().awaitable()
                try await self.fetchMessages()
                fetchFuture.resolve()
            } catch {
                fetchFuture.reject(error)
            }
        }
    }

    private var shouldUseWebSocket: Bool {
        return OWSChatConnection.canAppUseSocketsToMakeRequests
    }

    public var hasCompletedInitialFetch: Bool {
        if shouldUseWebSocket {
            return (
                DependenciesBridge.shared.chatConnectionManager.identifiedConnectionState == .open &&
                DependenciesBridge.shared.chatConnectionManager.hasEmptiedInitialQueue
            )
        } else {
            return self.didFinishFetchingViaREST.get()
        }
    }

    public func waitForFetchingComplete() -> Guarantee<Void> {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            return Guarantee.value(())
        }
        if hasCompletedInitialFetch {
            return Guarantee.value(())
        }
        if shouldUseWebSocket {
            return NotificationCenter.default.observe(
                once: OWSChatConnection.chatConnectionStateDidChange
            ).then { _ in
                self.waitForFetchingComplete()
            }.asVoid()
        } else {
            return NotificationCenter.default.observe(
                once: Self.didChangeStateNotificationName
            ).then { _ in
                self.waitForFetchingComplete()
            }.asVoid()
        }
    }

    // MARK: -

    private func fetchMessages() async throws {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            throw OWSAssertionError("This extension should not fetch messages.")
        }

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            assert(appReadiness.isAppReady)
            Logger.warn("Not registered.")
            return
        }

        if shouldUseWebSocket {
            DependenciesBridge.shared.chatConnectionManager.didReceivePush()
            // Should we wait to resolve the future until we know the WebSocket is open? Wait until it empties?
        } else {
            try await fetchMessagesViaRestWhenReady()
        }
    }

    // MARK: -

    // We want to have multiple ACKs in flight at a time.
    private let ackOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageFetcherJob-ACKs"
        operationQueue.maxConcurrentOperationCount = 5
        return operationQueue
    }()

    private let pendingAcks = PendingTasks(label: "Acks")

    private func acknowledgeDelivery(envelopeInfo: EnvelopeInfo) {
        guard let ackOperation = MessageAckOperation(envelopeInfo: envelopeInfo,
                                                     pendingAcks: pendingAcks) else {
            return
        }
        ackOperationQueue.addOperation(ackOperation)
    }

    public func pendingAcksPromise() -> Promise<Void> {
        // This promise blocks on all operations already in the queue,
        // but will not block on new operations added after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingAcks.pendingTasksPromise()
    }

    // MARK: -

    private struct EnvelopeJob {
        let encryptedEnvelope: SSKProtoEnvelope
        let completion: (Error?) -> Void
    }

    private let didFinishFetchingViaREST = AtomicBool(false, lock: .init())

    public func prepareToFetchViaREST() {
        self.didFinishFetchingViaREST.set(false)
    }

    private func fetchMessagesViaRest() async throws {
        let batch = try await fetchBatchViaRest()

        let envelopeJobs: [EnvelopeJob] = batch.envelopes.map { envelope in
            let envelopeInfo = Self.buildEnvelopeInfo(envelope: envelope)
            return EnvelopeJob(encryptedEnvelope: envelope) { error in
                let ackBehavior = MessageProcessor.handleMessageProcessingOutcome(error: error)
                switch ackBehavior {
                case .shouldAck:
                    Self.messageFetcherJob.acknowledgeDelivery(envelopeInfo: envelopeInfo)
                case .shouldNotAck(let error):
                    Logger.info("Skipping ack of message with timestamp \(envelopeInfo.timestamp) because of error: \(error)")
                }
            }
        }

        for job in envelopeJobs {
            messageProcessor.processReceivedEnvelope(
                job.encryptedEnvelope,
                serverDeliveryTimestamp: batch.serverDeliveryTimestamp,
                envelopeSource: .rest,
                completion: job.completion
            )
        }

        if batch.hasMore {
            Logger.info("fetching more messages.")
            try await fetchMessagesViaRestWhenReady()
        } else {
            self.didFinishFetchingViaREST.set(true)
            NotificationCenter.default.postNotificationNameAsync(MessageFetcherJob.didChangeStateNotificationName, object: nil)
        }
    }

    private func fetchMessagesViaRestWhenReady() async throws {
        try await Promise<Void>.waitUntil { self.isReadyToFetchMessagesViaRest }.awaitable()
        try await fetchMessagesViaRest()
    }

    private var isReadyToFetchMessagesViaRest: Bool {
        owsPrecondition(CurrentAppContext().isNSE)

        // The NSE has tight memory constraints.
        // For perf reasons, MessageProcessor keeps its queue in memory.
        // It is not safe for the NSE to fetch more messages
        // and cause this queue to grow in an unbounded way.
        // Therefore, the NSE should wait to fetch more messages if
        // the queue has "some/enough" content.
        // However, the NSE needs to process messages with high
        // throughput.
        // Therefore we need to identify a constant N small enough to
        // place an acceptable upper bound on memory usage of the processor
        // (N + next fetched batch size, fetch size in practice is 100),
        // large enough to avoid introducing latency (e.g. the next fetch
        // will complete before the queue is empty).
        // This is tricky since there are multiple variables (e.g. network
        // perf affects fetch, CPU perf affects processing).
        let queuedContentCount = messageProcessor.queuedContentCount
        let pendingAcksCount = MessageAckOperation.pendingAcksCount
        let incompleteEnvelopeCount = queuedContentCount + pendingAcksCount
        let maxIncompleteEnvelopeCount: Int = 20
        return incompleteEnvelopeCount < maxIncompleteEnvelopeCount
    }

    // MARK: -

    private class func parseMessagesResponse(responseObject: Any?) -> (envelopes: [SSKProtoEnvelope], more: Bool)? {
        guard let responseObject = responseObject else {
            Logger.error("response object was unexpectedly nil")
            return nil
        }

        guard let responseDict = responseObject as? [String: Any] else {
            Logger.error("response object was not a dictionary")
            return nil
        }

        guard let messageDicts = responseDict["messages"] as? [[String: Any]] else {
            Logger.error("messages object was not a list of dictionaries")
            return nil
        }

        let moreMessages = { () -> Bool in
            if let responseMore = responseDict["more"] as? Bool {
                return responseMore
            } else {
                Logger.warn("more object was not a bool. Assuming no more")
                return false
            }
        }()

        let envelopes: [SSKProtoEnvelope] = messageDicts.compactMap { buildEnvelope(messageDict: $0) }

        return (
            envelopes: envelopes,
            more: moreMessages
        )
    }

    private class func buildEnvelope(messageDict: [String: Any]) -> SSKProtoEnvelope? {
        do {
            let params = ParamParser(dictionary: messageDict)

            let typeInt: Int32 = try params.required(key: "type")
            guard let type: SSKProtoEnvelopeType = SSKProtoEnvelopeType(rawValue: typeInt) else {
                throw OWSAssertionError("Invalid envelope type: \(typeInt)")
            }

            let timestamp: UInt64 = try params.required(key: "timestamp")

            let builder = SSKProtoEnvelope.builder(timestamp: timestamp)
            builder.setType(type)
            if let sourceUuid: String = try params.optional(key: "sourceUuid") {
                builder.setSourceServiceID(sourceUuid)
            }
            if let sourceDevice: UInt32 = try params.optional(key: "sourceDevice") {
                builder.setSourceDevice(sourceDevice)
            }
            if let destinationUuid: String = try params.optional(key: "destinationUuid") {
                builder.setDestinationServiceID(destinationUuid)
            }
            if let content = try params.optionalBase64EncodedData(key: "content") {
                builder.setContent(content)
            }
            if let serverTimestamp: UInt64 = try params.optional(key: "serverTimestamp") {
                builder.setServerTimestamp(serverTimestamp)
            }
            if let serverGuid: String = try params.optional(key: "guid") {
                builder.setServerGuid(serverGuid)
            }
            if let story: Bool = try params.optional(key: "story") {
                builder.setStory(story)
            }
            if let token = try params.optionalBase64EncodedData(key: "reportSpamToken") {
                builder.setSpamReportingToken(token)
            }

            return try builder.build()
        } catch {
            owsFailDebug("error building envelope: \(error)")
            return nil
        }
    }

    private struct RESTBatch {
        let envelopes: [SSKProtoEnvelope]
        let serverDeliveryTimestamp: UInt64
        let hasMore: Bool
    }

    private func fetchBatchViaRest() async throws -> RESTBatch {
        let request = OWSRequestFactory.getMessagesRequest()
        let response = try await networkManager.makePromise(request: request).awaitable()
        guard let json = response.responseBodyJson else {
            throw OWSAssertionError("Missing or invalid JSON")
        }
        guard
            let timestampString = response.responseHeaders["x-signal-timestamp"],
            let serverDeliveryTimestamp = UInt64(timestampString)
        else {
            throw OWSAssertionError("Unable to parse server delivery timestamp.")
        }
        guard let (envelopes, more) = Self.parseMessagesResponse(responseObject: json) else {
            throw OWSAssertionError("Invalid response.")
        }
        return RESTBatch(envelopes: envelopes, serverDeliveryTimestamp: serverDeliveryTimestamp, hasMore: more)
    }

    fileprivate struct EnvelopeInfo {
        let sourceAddress: SignalServiceAddress?
        let serverGuid: String?
        let timestamp: UInt64
        let serviceTimestamp: UInt64
    }

    private class func buildEnvelopeInfo(envelope: SSKProtoEnvelope) -> EnvelopeInfo {
        EnvelopeInfo(sourceAddress: envelope.sourceAddress,
                     serverGuid: envelope.serverGuid,
                     timestamp: envelope.timestamp,
                     serviceTimestamp: envelope.serverTimestamp)
    }
}

// MARK: -

private class MessageAckOperation: OWSOperation {

    fileprivate typealias EnvelopeInfo = MessageFetcherJob.EnvelopeInfo

    private let envelopeInfo: EnvelopeInfo
    private let pendingAck: PendingTask

    // A heuristic to quickly filter out multiple ack attempts for the same message
    // This doesn't affect correctness, just tries to guard against backing up our operation queue with repeat work
    static private var inFlightAcks = AtomicSet<String>(lock: .sharedGlobal)
    private var didRecordAckId = false
    private let inFlightAckId: String

    public static var pendingAcksCount: Int {
        inFlightAcks.count
    }

    private static func inFlightAckId(forEnvelopeInfo envelopeInfo: EnvelopeInfo) -> String {
        // All messages *should* have a guid, but we'll handle things correctly if they don't
        owsAssertDebug(envelopeInfo.serverGuid?.nilIfEmpty != nil)

        if let serverGuid = envelopeInfo.serverGuid?.nilIfEmpty {
            return serverGuid
        } else if let sourceServiceId = envelopeInfo.sourceAddress?.serviceId {
            return "\(sourceServiceId.serviceIdUppercaseString)_\(envelopeInfo.timestamp)"
        } else {
            // This *could* collide, but we don't have enough info to ack the message anyway. So it should be fine.
            return "\(envelopeInfo.serviceTimestamp)"
        }
    }

    private static let unfairLock = UnfairLock()
    private static var successfulAckSet = OrderedSet<String>()
    private static func didAck(inFlightAckId: String) {
        unfairLock.withLock {
            successfulAckSet.append(inFlightAckId)
            // REST fetches are batches of 100.
            let maxAckCount: Int = 128
            while successfulAckSet.count > maxAckCount,
                  let firstAck = successfulAckSet.first {
                successfulAckSet.remove(firstAck)
            }
        }
    }
    private static func hasAcked(inFlightAckId: String) -> Bool {
        unfairLock.withLock {
            successfulAckSet.contains(inFlightAckId)
        }
    }

    fileprivate init?(envelopeInfo: EnvelopeInfo, pendingAcks: PendingTasks) {

        let inFlightAckId = Self.inFlightAckId(forEnvelopeInfo: envelopeInfo)
        self.inFlightAckId = inFlightAckId

        guard !Self.hasAcked(inFlightAckId: inFlightAckId) else {
            Logger.info("Skipping new ack operation for \(envelopeInfo). Duplicate ack already complete")
            return nil
        }
        guard !Self.inFlightAcks.contains(inFlightAckId) else {
            Logger.info("Skipping new ack operation for \(envelopeInfo). Duplicate ack already enqueued")
            return nil
        }

        let pendingAck = pendingAcks.buildPendingTask(label: "Ack, timestamp: \(envelopeInfo.timestamp), serviceTimestamp: \(envelopeInfo.serviceTimestamp)")

        self.envelopeInfo = envelopeInfo
        self.pendingAck = pendingAck

        super.init()

        self.remainingRetries = 3

        // MessageAckOperation must have a higher priority than than the
        // operations used to flush the ack operation queue.
        self.queuePriority = .high
        Self.inFlightAcks.insert(inFlightAckId)
        didRecordAckId = true
    }

    public override func run() {
        let request: TSRequest
        if let serverGuid = envelopeInfo.serverGuid, !serverGuid.isEmpty {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(serverGuid: serverGuid)
        } else {
            let error = OWSAssertionError("Cannot ACK message which has neither source, nor server GUID and timestamp.")
            reportError(error)
            return
        }

        let inFlightAckId = self.inFlightAckId
        firstly(on: DispatchQueue.global()) {
            self.networkManager.makePromise(request: request)
        }.done(on: DispatchQueue.global()) { _ in
            Self.didAck(inFlightAckId: inFlightAckId)
            self.reportSuccess()
        }.catch(on: DispatchQueue.global()) { error in
            self.reportError(error)
        }
    }

    @objc
    public override func didComplete() {
        super.didComplete()
        if didRecordAckId {
            Self.inFlightAcks.remove(inFlightAckId)
        }
        pendingAck.complete()
    }
}

// MARK: -

extension Promise {
    public static func waitUntil(checkFrequency: TimeInterval = 0.01,
                                 dispatchQueue: DispatchQueue = .global(),
                                 conditionBlock: @escaping () -> Bool) -> Promise<Void> {

        let (promise, future) = Promise<Void>.pending()
        fulfillWaitUntil(future: future,
                         checkFrequency: checkFrequency,
                         dispatchQueue: dispatchQueue,
                         conditionBlock: conditionBlock)
        return promise
    }

    private static func fulfillWaitUntil(future: Future<Void>,
                                         checkFrequency: TimeInterval,
                                         dispatchQueue: DispatchQueue,
                                         conditionBlock: @escaping () -> Bool) {
        if conditionBlock() {
            future.resolve()
            return
        }
        dispatchQueue.asyncAfter(deadline: .now() + checkFrequency) {
            fulfillWaitUntil(future: future,
                             checkFrequency: checkFrequency,
                             dispatchQueue: dispatchQueue,
                             conditionBlock: conditionBlock)
        }
    }
}
