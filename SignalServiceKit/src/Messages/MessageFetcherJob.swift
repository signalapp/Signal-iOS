//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

// This token can be used to observe the completion of a given fetch cycle.
public struct MessageFetchCycle: Hashable, Equatable {
    public let uuid = UUID()
    public let promise: Promise<Void>

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    // MARK: Equatable

    public static func == (lhs: MessageFetchCycle, rhs: MessageFetchCycle) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}

// MARK: -

public class MessageFetcherJob: NSObject {

    private var timer: Timer?

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        if CurrentAppContext().shouldProcessIncomingMessages && CurrentAppContext().isMainApp {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                // Fetch messages as soon as possible after launching. In particular, when
                // launching from the background, without this, we end up waiting some extra
                // seconds before receiving an actionable push notification.
                if Self.tsAccountManager.isRegistered {
                    firstly(on: .global()) {
                        self.run()
                    }.catch(on: .global()) { error in
                        owsFailDebugUnlessNetworkFailure(error)
                    }
                }
            }
        }
    }

    // MARK: -

    // This operation queue ensures that only one fetch operation is
    // running at a given time.
    private let fetchOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageFetcherJob.fetchOperationQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    fileprivate var activeOperationCount: Int {
        return fetchOperationQueue.operationCount
    }

    private let unfairLock = UnfairLock()

    private let completionQueue = DispatchQueue(label: "org.signal.messageFetcherJob.completionQueue")

    // This property should only be accessed with unfairLock acquired.
    private var activeFetchCycles = Set<UUID>()

    // This property should only be accessed with unfairLock acquired.
    private var completedFetchCyclesCounter: UInt = 0

    @objc
    public static let didChangeStateNotificationName = Notification.Name("MessageFetcherJob.didChangeStateNotificationName")

    @discardableResult
    public func run() -> MessageFetchCycle {
        Logger.info("")

        // Use an operation queue to ensure that only one fetch cycle is done
        // at a time.
        let fetchOperation = MessageFetchOperation()
        let promise = fetchOperation.promise
        let fetchCycle = MessageFetchCycle(promise: promise)

        _ = self.unfairLock.withLock {
            activeFetchCycles.insert(fetchCycle.uuid)
        }

        // We don't want to re-fetch any messages that have
        // already been processed, so fetch operations should
        // block on "message ack" operations.  We accomplish
        // this by having our message fetch operations depend
        // on a no-op operation that flushes the "message ack"
        // operation queue.
        let shouldFlush = !FeatureFlags.deprecateREST
        if shouldFlush {
            let flushAckOperation = Operation()
            flushAckOperation.queuePriority = .normal
            ackOperationQueue.addOperation(flushAckOperation)

            fetchOperation.addDependency(flushAckOperation)
        }

        fetchOperationQueue.addOperation(fetchOperation)

        completionQueue.async {
            self.fetchOperationQueue.waitUntilAllOperationsAreFinished()

            self.unfairLock.withLock {
                self.activeFetchCycles.remove(fetchCycle.uuid)
                self.completedFetchCyclesCounter += 1
            }

            self.postDidChangeState()
        }

        self.postDidChangeState()

        return fetchCycle
    }

    @objc
    @discardableResult
    public func runObjc() -> AnyPromise {
        AnyPromise(run().promise)
    }

    private func postDidChangeState() {
        NotificationCenter.default.postNotificationNameAsync(MessageFetcherJob.didChangeStateNotificationName, object: nil)
    }

    public func isFetchCycleComplete(fetchCycle: MessageFetchCycle) -> Bool {
        unfairLock.withLock {
            self.activeFetchCycles.contains(fetchCycle.uuid)
        }
    }

    public var areAllFetchCyclesComplete: Bool {
        unfairLock.withLock {
            self.activeFetchCycles.isEmpty
        }
    }

    public var completedRestFetches: UInt {
        unfairLock.withLock {
            self.completedFetchCyclesCounter
        }
    }

    public class var shouldUseWebSocket: Bool {
        if signalService.isCensorshipCircumventionActive {
            return false
        }
        if FeatureFlags.deprecateREST {
            return true
        } else {
            return CurrentAppContext().isMainApp
        }
    }

    @objc
    public var hasCompletedInitialFetch: Bool {
        if Self.shouldUseWebSocket {
            let isWebsocketDrained = (socketManager.socketState(forType: .identified) == .open &&
                                        socketManager.hasEmptiedInitialQueue)
            guard isWebsocketDrained else { return false }
        } else {
            guard completedRestFetches > 0 else { return false }
        }
        return true
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func fetchingCompletePromise() -> AnyPromise {
        AnyPromise(fetchingCompletePromise())
    }

    public func fetchingCompletePromise() -> Promise<Void> {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            if DebugFlags.isMessageProcessingVerbose {
                Logger.verbose("!shouldProcessIncomingMessages")
            }
            return Promise.value(())
        }

        if Self.shouldUseWebSocket {
            guard !hasCompletedInitialFetch else {
                if DebugFlags.isMessageProcessingVerbose {
                    Logger.verbose("hasCompletedInitialFetch")
                }
                return Promise.value(())
            }

            if DebugFlags.isMessageProcessingVerbose {
                Logger.verbose("!hasCompletedInitialFetch")
            }

            return NotificationCenter.default.observe(once: OWSWebSocket.webSocketStateDidChange).then { _ in
                self.fetchingCompletePromise()
            }.asVoid()
        } else {
            guard !areAllFetchCyclesComplete || !hasCompletedInitialFetch else {
                if DebugFlags.isMessageProcessingVerbose {
                    Logger.verbose("areAllFetchCyclesComplete && hasCompletedInitialFetch")
                }
                return Promise.value(())
            }

            if DebugFlags.isMessageProcessingVerbose {
                Logger.verbose("!areAllFetchCyclesComplete || !hasCompletedInitialFetch")
            }

            return NotificationCenter.default.observe(once: Self.didChangeStateNotificationName).then { _ in
                self.fetchingCompletePromise()
            }.asVoid()
        }
    }

    // MARK: -

    fileprivate class func fetchMessages(future: Future<Void>) {
        Logger.info("")

        guard tsAccountManager.isRegisteredAndReady else {
            assert(AppReadiness.isAppReady)
            Logger.warn("Not registered.")
            return future.resolve()
        }

        if shouldUseWebSocket {
            Logger.info("delegating message fetching to SocketManager since we're using normal transport.")
            socketManager.didReceivePush()
            // Should we wait to resolve the future until we know the WebSocket is open? Wait until it empties?
            return future.resolve()
        } else if CurrentAppContext().shouldProcessIncomingMessages {
            // Main app should use REST if censorship circumvention is active.
            // Notification extension that should always use REST.
        } else {
            return future.reject(OWSAssertionError("App extensions should not fetch messages."))
        }

        Logger.info("Fetching messages via REST.")

        firstly {
            fetchMessagesViaRestWhenReady()
        }.done {
            future.resolve()
        }.catch { error in
            Logger.error("Error: \(error).")
            future.reject(error)
        }
    }

    // MARK: -

    // We want to have multiple ACKs in flight at a time.
    private let ackOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageFetcherJob.ackOperationQueue"
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

    private class func fetchMessagesViaRest() -> Promise<Void> {
        if DebugFlags.internalLogging {
            Logger.info("")
        } else {
            Logger.debug("")
        }

        return firstly(on: .global()) {
            fetchBatchViaRest()
        }.map(on: .global()) { (batch: RESTBatch) -> ([EnvelopeJob], UInt64, Bool) in
            if DebugFlags.internalLogging {
                Logger.info("REST fetched envelopes: \(batch.envelopes.count)")
            }

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
            return (envelopeJobs: envelopeJobs,
                    serverDeliveryTimestamp: batch.serverDeliveryTimestamp,
                    hasMore: batch.hasMore)
        }.then(on: .global()) { (envelopeJobs: [EnvelopeJob], serverDeliveryTimestamp: UInt64, hasMore: Bool) -> Promise<Void> in
            let queuedContentCountOld = Self.messageProcessor.queuedContentCount
            for job in envelopeJobs {
                Self.messageProcessor.processEncryptedEnvelope(
                    job.encryptedEnvelope,
                    serverDeliveryTimestamp: serverDeliveryTimestamp,
                    envelopeSource: .rest,
                    completion: job.completion)
            }
            let queuedContentCountNew = Self.messageProcessor.queuedContentCount

            if DebugFlags.internalLogging {
                Logger.info("messageProcessor.queuedContentCount: \(queuedContentCountOld) + \(envelopeJobs.count) -> \(queuedContentCountNew)")
            }

            if hasMore {
                Logger.info("fetching more messages.")

                return self.fetchMessagesViaRestWhenReady()
            } else {
                // All finished
                return Promise.value(())
            }
        }
    }

    private class func fetchMessagesViaRestWhenReady() -> Promise<Void> {
        Promise<Void>.waitUntil {
            isReadyToFetchMessagesViaRest
        }.then {
            fetchMessagesViaRest()
        }
    }

    private class var isReadyToFetchMessagesViaRest: Bool {
        guard CurrentAppContext().isNSE else {
            // If not NSE, fetch more immediately.
            return true
        }

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
        guard incompleteEnvelopeCount < maxIncompleteEnvelopeCount else {
            if DebugFlags.internalLogging,
               incompleteEnvelopeCount != Self.lastIncompleteEnvelopeCount.get() {
                Logger.info("queuedContentCount: \(queuedContentCount) + pendingAcksCount: \(pendingAcksCount) = \(incompleteEnvelopeCount)")
                Self.lastIncompleteEnvelopeCount.set(incompleteEnvelopeCount)
            }
            return false
        }

        return true
    }

    private static let lastIncompleteEnvelopeCount = AtomicValue<Int>(0)

    // MARK: - Run Loop

    // use in DEBUG or wherever you can't receive push notifications to poll for messages.
    // Do not use in production.
    public func startRunLoop(timeInterval: Double) {
        Logger.error("Starting message fetch polling. This should not be used in production.")
        timer = WeakTimer.scheduledTimer(timeInterval: timeInterval, target: self, userInfo: nil, repeats: true) {[weak self] _ in
            _ = self?.run()
            return
        }
    }

    public func stopRunLoop() {
        timer?.invalidate()
        timer = nil
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
                Logger.error("`type` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("type")
            }

            guard let timestamp: UInt64 = try params.required(key: "timestamp") else {
                Logger.error("`timestamp` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("timestamp")
            }

            let builder = SSKProtoEnvelope.builder(timestamp: timestamp)
            builder.setType(type)

            if let sourceUuid: String = try params.optional(key: "sourceUuid") {
                builder.setSourceUuid(sourceUuid)
            }

            if let sourceDevice: UInt32 = try params.optional(key: "sourceDevice") {
                builder.setSourceDevice(sourceDevice)
            }

            if let destinationUuid: String = try params.optional(key: "destinationUuid") {
                builder.setDestinationUuid(destinationUuid)
            }

            if let legacyMessage = try params.optionalBase64EncodedData(key: "message") {
                builder.setLegacyMessage(legacyMessage)
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

    private class func fetchBatchViaRest() -> Promise<RESTBatch> {
        firstly(on: .global()) { () -> Promise<HTTPResponse> in
            let request = OWSRequestFactory.getMessagesRequest()
            return self.networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            guard let timestampString = response.responseHeaders["x-signal-timestamp"],
                  let serverDeliveryTimestamp = UInt64(timestampString) else {
                throw OWSAssertionError("Unable to parse server delivery timestamp.")
            }

            guard let (envelopes, more) = self.parseMessagesResponse(responseObject: json) else {
                throw OWSAssertionError("Invalid response.")
            }

            return RESTBatch(envelopes: envelopes,
                             serverDeliveryTimestamp: serverDeliveryTimestamp,
                             hasMore: more)
        }
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

private class MessageFetchOperation: OWSOperation {

    let promise: Promise<Void>
    let future: Future<Void>

    override required init() {

        let (promise, future) = Promise<Void>.pending()
        self.promise = promise
        self.future = future
        super.init()
        self.remainingRetries = 3
    }

    public override func run() {
        Logger.info("")

        MessageFetcherJob.fetchMessages(future: future)

        _ = promise.ensure {
            self.reportSuccess()
        }
    }
}

// MARK: -

private class MessageAckOperation: OWSOperation {

    fileprivate typealias EnvelopeInfo = MessageFetcherJob.EnvelopeInfo

    private let envelopeInfo: EnvelopeInfo
    private let pendingAck: PendingTask

    // A heuristic to quickly filter out multiple ack attempts for the same message
    // This doesn't affect correctness, just tries to guard against backing up our operation queue with repeat work
    static private var inFlightAcks = AtomicSet<String>()
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
        } else if let sourceUuid = envelopeInfo.sourceAddress?.uuid {
            return "\(sourceUuid.uuidString)_\(envelopeInfo.timestamp)"
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

    fileprivate required init?(envelopeInfo: EnvelopeInfo, pendingAcks: PendingTasks) {

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
        Logger.debug("")

        let request: TSRequest
        if let serverGuid = envelopeInfo.serverGuid, !serverGuid.isEmpty {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(withServerGuid: serverGuid)
        } else if let sourceAddress = envelopeInfo.sourceAddress, sourceAddress.isValid, envelopeInfo.timestamp > 0 {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(with: sourceAddress, timestamp: envelopeInfo.timestamp)
        } else {
            let error = OWSAssertionError("Cannot ACK message which has neither source, nor server GUID and timestamp.")
            reportError(error)
            return
        }

        let envelopeInfo = self.envelopeInfo
        let inFlightAckId = self.inFlightAckId
        firstly(on: .global()) {
            self.networkManager.makePromise(request: request)
        }.done(on: .global()) { _ in
            Self.didAck(inFlightAckId: inFlightAckId)

            if DebugFlags.internalLogging {
                Logger.info("acknowledged delivery for message at timestamp: \(envelopeInfo.timestamp), serviceTimestamp: \(envelopeInfo.serviceTimestamp)")
            } else {
                Logger.debug("acknowledged delivery for message at timestamp: \(envelopeInfo.timestamp), serviceTimestamp: \(envelopeInfo.serviceTimestamp)")
            }
            self.reportSuccess()
        }.catch(on: .global()) { error in
            if DebugFlags.internalLogging {
                Logger.info("acknowledging delivery for message at timestamp: \(envelopeInfo.timestamp), serviceTimestamp: \(envelopeInfo.serviceTimestamp) " + " failed with error: \(error)")
            } else {
                Logger.debug("acknowledging delivery for message at timestamp: \(envelopeInfo.timestamp), serviceTimestamp: \(envelopeInfo.serviceTimestamp) " + " failed with error: \(error)")
            }
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
