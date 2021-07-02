//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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

    private let serialQueue = DispatchQueue(label: "org.signal.messageFetcherJob.serialQueue")

    private let completionQueue = DispatchQueue(label: "org.signal.messageFetcherJob.completionQueue")

    // This property should only be accessed on serialQueue.
    private var activeFetchCycles = Set<UUID>()

    // This property should only be accessed on serialQueue.
    private var completedFetchCyclesCounter: UInt = 0

    @objc
    public static let didChangeStateNotificationName = Notification.Name("MessageFetcherJob.didChangeStateNotificationName")

    @discardableResult
    public func run() -> MessageFetchCycle {
        Logger.debug("")

        // Use an operation queue to ensure that only one fetch cycle is done
        // at a time.
        let fetchOperation = MessageFetchOperation()
        let promise = fetchOperation.promise
        let fetchCycle = MessageFetchCycle(promise: promise)

        _ = self.serialQueue.sync {
            activeFetchCycles.insert(fetchCycle.uuid)
        }

        // We don't want to re-fetch any messages that have
        // already been processed, so fetch operations should
        // block on "message ack" operations.  We accomplish
        // this by having our message fetch operations depend
        // on a no-op operation that flushes the "message ack"
        // operation queue.
        let flushAckOperation = Operation()
        flushAckOperation.queuePriority = .normal
        ackOperationQueue.addOperation(flushAckOperation)

        fetchOperation.addDependency(flushAckOperation)
        fetchOperationQueue.addOperation(fetchOperation)

        completionQueue.async {
            self.fetchOperationQueue.waitUntilAllOperationsAreFinished()

            self.serialQueue.sync {
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
        return AnyPromise(run().promise)
    }

    private func postDidChangeState() {
        NotificationCenter.default.postNotificationNameAsync(MessageFetcherJob.didChangeStateNotificationName, object: nil)
    }

    public func isFetchCycleComplete(fetchCycle: MessageFetchCycle) -> Bool {
        return self.serialQueue.sync {
            return self.activeFetchCycles.contains(fetchCycle.uuid)
        }
    }

    public var areAllFetchCyclesComplete: Bool {
        return self.serialQueue.sync {
            return self.activeFetchCycles.isEmpty
        }
    }

    public var completedRestFetches: UInt {
        return self.serialQueue.sync {
            return self.completedFetchCyclesCounter
        }
    }

    public class var shouldUseWebSocket: Bool {
        return CurrentAppContext().isMainApp && !signalService.isCensorshipCircumventionActive
    }

    @objc
    public var hasCompletedInitialFetch: Bool {
        if Self.shouldUseWebSocket {
            let isWebsocketDrained = (TSSocketManager.shared.socketState() == .open &&
                                        TSSocketManager.shared.hasEmptiedInitialQueue())
            guard isWebsocketDrained else { return false }
        } else {
            guard completedRestFetches > 0 else { return false }
        }
        return true
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func fetchingCompletePromise() -> AnyPromise {
        return AnyPromise(fetchingCompletePromise())
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

            return NotificationCenter.default.observe(once: .webSocketStateDidChange).then { _ in
                return self.fetchingCompletePromise()
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
                return self.fetchingCompletePromise()
            }.asVoid()
        }
    }

    // MARK: -

    fileprivate class func fetchMessages(resolver: Resolver<Void>) {
        Logger.debug("")

        guard tsAccountManager.isRegisteredAndReady else {
            assert(AppReadiness.isAppReady)
            Logger.warn("not registered")
            return resolver.fulfill(())
        }

        if shouldUseWebSocket {
            Logger.debug("delegating message fetching to SocketManager since we're using normal transport.")
            TSSocketManager.shared.requestSocketOpen()
            return resolver.fulfill(())
        } else if CurrentAppContext().shouldProcessIncomingMessages {
            // Main app should use REST if censorship circumvention is active.
            // Notification extension that should always use REST.
        } else {
            return resolver.reject(OWSAssertionError("App extensions should not fetch messages."))
        }

        Logger.info("Fetching messages via REST.")

        firstly {
            fetchMessagesViaRestWhenReady()
        }.done {
            resolver.fulfill(())
        }.catch { error in
            Logger.error("Error: \(error).")
            resolver.reject(error)
        }
    }

    // MARK: -

    // This operation queue ensures that only one fetch operation is
    // running at a given time.
    private let ackOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageFetcherJob.ackOperationQueue"
        operationQueue.maxConcurrentOperationCount = 3
        return operationQueue
    }()

    private func acknowledgeDelivery(envelopeInfo: EnvelopeInfo) {
        let ackOperation = MessageAckOperation(envelopeInfo: envelopeInfo)
        ackOperationQueue.addOperation(ackOperation)
    }

    // MARK: -

    typealias EnvelopeJob = MessageProcessor.EnvelopeJob

    private class func fetchMessagesViaRest() -> Promise<Void> {
        Logger.debug("")

        return firstly(on: .global()) {
            fetchBatchViaRest()
        }.map(on: .global()) { (envelopes: [SSKProtoEnvelope], serverDeliveryTimestamp: UInt64, more: Bool) -> ([EnvelopeJob], UInt64, Bool) in
            let envelopeJobs: [EnvelopeJob] = envelopes.compactMap { envelope in
                let envelopeInfo = Self.buildEnvelopeInfo(envelope: envelope)
                do {
                    let envelopeData = try envelope.serializedData()
                    return EnvelopeJob(encryptedEnvelopeData: envelopeData, encryptedEnvelope: envelope) {_ in
                        Self.messageFetcherJob.acknowledgeDelivery(envelopeInfo: envelopeInfo)
                    }
                } catch {
                    owsFailDebug("failed to serialize envelope")
                    Self.messageFetcherJob.acknowledgeDelivery(envelopeInfo: envelopeInfo)
                    return nil
                }
            }
            return (envelopeJobs: envelopeJobs, serverDeliveryTimestamp: serverDeliveryTimestamp, more: more)
        }.then(on: .global()) { (envelopeJobs: [EnvelopeJob], serverDeliveryTimestamp: UInt64, more: Bool) -> Promise<Void> in
            Self.messageProcessor.processEncryptedEnvelopes(
                envelopeJobs: envelopeJobs,
                serverDeliveryTimestamp: serverDeliveryTimestamp
            )

            if more {
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
        // In NSE, if messageProcessor queue has enough content,
        // wait before fetching more envelopes.
        // We need to bound peak memory usage in the NSE when processing
        // lots of incoming message.
        return !Self.messageProcessor.hasSomeQueuedContent
    }

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

            if let source: String = try params.optional(key: "source") {
                builder.setSourceE164(source)
            }

            if let sourceDevice: UInt32 = try params.optional(key: "sourceDevice") {
                builder.setSourceDevice(sourceDevice)
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

    private class func fetchBatchViaRest() -> Promise<(envelopes: [SSKProtoEnvelope], serverDeliveryTimestamp: UInt64, more: Bool)> {
        return Promise { resolver in
            let request = OWSRequestFactory.getMessagesRequest()
            self.networkManager.makeRequest(
                request,
                success: { task, responseObject -> Void in
                    guard let httpResponse = task.response as? HTTPURLResponse,
                        let timestampString = httpResponse.allHeaderFields["x-signal-timestamp"] as? String,
                        let serverDeliveryTimestamp = UInt64(timestampString) else {
                            return resolver.reject(OWSAssertionError("Unable to parse server delivery timestamp."))
                    }

                    guard let (envelopes, more) = self.parseMessagesResponse(responseObject: responseObject) else {
                        Logger.error("response object had unexpected content")
                        return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    resolver.fulfill((envelopes: envelopes, serverDeliveryTimestamp: serverDeliveryTimestamp, more: more))
                },
                failure: { (_: URLSessionDataTask?, error: Error?) in
                    guard let error = error else {
                        Logger.error("error was surprisingly nil. sheesh rough day.")
                        return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    resolver.reject(error)
            })
        }
    }

    fileprivate struct EnvelopeInfo {
        let sourceAddress: SignalServiceAddress?
        let serverGuid: String?
        let timestamp: UInt64
    }

    private class func buildEnvelopeInfo(envelope: SSKProtoEnvelope) -> EnvelopeInfo {
        EnvelopeInfo(sourceAddress: envelope.sourceAddress,
                     serverGuid: envelope.serverGuid,
                     timestamp: envelope.timestamp)
    }
}

// MARK: -

private class MessageFetchOperation: OWSOperation {

    let promise: Promise<Void>
    let resolver: Resolver<Void>

    override required init() {

        let (promise, resolver) = Promise<Void>.pending()
        self.promise = promise
        self.resolver = resolver
        super.init()
        self.remainingRetries = 3
    }

    public override func run() {
        Logger.debug("")

        MessageFetcherJob.fetchMessages(resolver: resolver)

        _ = promise.ensure {
            self.reportSuccess()
        }
    }
}

// MARK: -

private class MessageAckOperation: OWSOperation {

    fileprivate typealias EnvelopeInfo = MessageFetcherJob.EnvelopeInfo

    private let envelopeInfo: EnvelopeInfo

    fileprivate required init(envelopeInfo: EnvelopeInfo) {
        self.envelopeInfo = envelopeInfo

        super.init()

        self.remainingRetries = 3

        // MessageAckOperation must have a higher priority than than the
        // operations used to flush the ack operation queue.
        self.queuePriority = .high
    }

    public override func run() {
        Logger.debug("")

        let request: TSRequest
        if let serverGuid = envelopeInfo.serverGuid, serverGuid.count > 0 {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(withServerGuid: serverGuid)
        } else if let sourceAddress = envelopeInfo.sourceAddress, sourceAddress.isValid, envelopeInfo.timestamp > 0 {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(with: sourceAddress, timestamp: envelopeInfo.timestamp)
        } else {
            let error = OWSAssertionError("Cannot ACK message which has neither source, nor server GUID and timestamp.")
            reportError(error.asUnretryableError)
            return
        }

        let envelopeInfo = self.envelopeInfo
        self.networkManager.makeRequest(request,
                                        success: { (_: URLSessionDataTask?, _: Any?) -> Void in
                                            Logger.debug("acknowledged delivery for message at timestamp: \(envelopeInfo.timestamp)")
                                            self.reportSuccess()
                                        },
                                        failure: { (_: URLSessionDataTask?, error: Error?) in
                                            Logger.debug("acknowledging delivery for message at timestamp: \(envelopeInfo.timestamp) " + "failed with error: \(String(describing: error))")
                                            if let error = error {
                                                if IsNetworkConnectivityFailure(error) {
                                                    self.reportError(error.asRetryableError)
                                                } else {
                                                    self.reportError(error.asUnretryableError)
                                                }
                                            } else {
                                                let error = OWSAssertionError("Unknown error while acknowledging delivery for message.")
                                                self.reportError(error.asUnretryableError)
                                            }
                                        })
    }
}

// MARK: -

extension Promise {
    public static func waitUntil(checkFrequency: TimeInterval = 0.01,
                                 dispatchQueue: DispatchQueue = .global(),
                                 conditionBlock: @escaping () -> Bool) -> Promise<Void> {

        let (promise, resolver) = Promise<Void>.pending()
        fulfillWaitUntil(resolver: resolver,
                         checkFrequency: checkFrequency,
                         dispatchQueue: dispatchQueue,
                         conditionBlock: conditionBlock)
        return promise
    }

    private static func fulfillWaitUntil(resolver: Resolver<Void>,
                                         checkFrequency: TimeInterval,
                                         dispatchQueue: DispatchQueue,
                                         conditionBlock: @escaping () -> Bool) {
        if conditionBlock() {
            resolver.fulfill(())
            return
        }
        dispatchQueue.asyncAfter(deadline: .now() + checkFrequency) {
            fulfillWaitUntil(resolver: resolver,
                             checkFrequency: checkFrequency,
                             dispatchQueue: dispatchQueue,
                             conditionBlock: conditionBlock)
        }
    }
}
