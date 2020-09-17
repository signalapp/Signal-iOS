//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
    }

    // MARK: Singletons

    private class var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private class var messageReceiver: OWSMessageReceiver {
        return SSKEnvironment.shared.messageReceiver
    }

    private class var signalService: OWSSignalService {
        return OWSSignalService.shared()
    }

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    // MARK: -

    // This operation queue ensures that only one fetch operation is
    // running at a given time.
    private let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageFetcherJob.operationQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    fileprivate var activeOperationCount: Int {
        return operationQueue.operationCount
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
        let operation = MessageFetchOperation()
        let promise = operation.promise
        let fetchCycle = MessageFetchCycle(promise: promise)

        _ = self.serialQueue.sync {
            activeFetchCycles.insert(fetchCycle.uuid)
        }

        operationQueue.addOperation(operation)

        completionQueue.async {
            self.operationQueue.waitUntilAllOperationsAreFinished()

            _ = self.serialQueue.sync {
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
            fetchMessagesViaRest()
        }.done {
            resolver.fulfill(())
        }.catch { error in
            Logger.error("Error: \(error).")
            resolver.reject(error)
        }
    }

    // MARK: -

    private class func fetchMessagesViaRest() -> Promise<Void> {
        Logger.debug("")

        return firstly {
            fetchBatchViaRest()
        }.then { (envelopes: [SSKProtoEnvelope], serverDeliveryTimestamp: UInt64, more: Bool) -> Promise<Void> in
            for envelope in envelopes {
                Logger.info("received envelope.")
                do {
                    let envelopeData = try envelope.serializedData()
                    self.messageReceiver.handleReceivedEnvelopeData(
                        envelopeData,
                        serverDeliveryTimestamp: serverDeliveryTimestamp
                    )
                } catch {
                    owsFailDebug("failed to serialize envelope")
                }
                self.acknowledgeDelivery(envelope: envelope)
            }

            if more {
                Logger.info("fetching more messages.")

                return self.fetchMessagesViaRest()
            } else {
                // All finished
                return Promise.value(())
            }
        }
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

    private class func acknowledgeDelivery(envelope: SSKProtoEnvelope) {
        let request: TSRequest
        if let serverGuid = envelope.serverGuid, serverGuid.count > 0 {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(withServerGuid: serverGuid)
        } else if let sourceAddress = envelope.sourceAddress, sourceAddress.isValid, envelope.timestamp > 0 {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(with: sourceAddress, timestamp: envelope.timestamp)
        } else {
            owsFailDebug("Cannot ACK message which has neither source, nor server GUID and timestamp.")
            return
        }

        self.networkManager.makeRequest(request,
                                        success: { (_: URLSessionDataTask?, _: Any?) -> Void in
                                            Logger.debug("acknowledged delivery for message at timestamp: \(envelope.timestamp)")
        },
                                        failure: { (_: URLSessionDataTask?, error: Error?) in
                                            Logger.debug("acknowledging delivery for message at timestamp: \(envelope.timestamp) failed with error: \(String(describing: error))")
        })
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
