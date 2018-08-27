//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc(OWSMessageFetcherJob)
public class MessageFetcherJob: NSObject {

    private var timer: Timer?

    // MARK: injected dependencies
    private let networkManager: TSNetworkManager
    private let messageReceiver: OWSMessageReceiver
    private let signalService: OWSSignalService

    @objc public init(messageReceiver: OWSMessageReceiver, networkManager: TSNetworkManager, signalService: OWSSignalService) {
        self.messageReceiver = messageReceiver
        self.networkManager = networkManager
        self.signalService = signalService

        super.init()

        SwiftSingletons.register(self)
    }

    @discardableResult
    public func run() -> Promise<Void> {
        Logger.debug("")

        guard signalService.isCensorshipCircumventionActive else {
            Logger.debug("delegating message fetching to SocketManager since we're using normal transport.")
            TSSocketManager.requestSocketOpen()
            return Promise(value: ())
        }

        Logger.info("fetching messages via REST.")

        let promise = self.fetchUndeliveredMessages().then { (envelopes: [SSKProtoEnvelope], more: Bool) -> Promise<Void> in
            for envelope in envelopes {
                Logger.info("received envelope.")
                do {
                    let envelopeData = try envelope.serializedData()
                    self.messageReceiver.handleReceivedEnvelopeData(envelopeData)
                } catch {
                    owsFailDebug("failed to serialize envelope")
                }
                self.acknowledgeDelivery(envelope: envelope)
            }

            if more {
                Logger.info("fetching more messages.")
                return self.run()
            } else {
                // All finished
                return Promise(value: ())
            }
        }

        promise.retainUntilComplete()

        return promise
    }

    @objc
    @discardableResult
    public func run() -> AnyPromise {
        return AnyPromise(run())
    }

    // use in DEBUG or wherever you can't receive push notifications to poll for messages.
    // Do not use in production.
    public func startRunLoop(timeInterval: Double) {
        Logger.error("Starting message fetch polling. This should not be used in production.")
        timer = WeakTimer.scheduledTimer(timeInterval: timeInterval, target: self, userInfo: nil, repeats: true) {[weak self] _ in
            let _: Promise<Void>? = self?.run()
            return
        }
    }

    public func stopRunLoop() {
        timer?.invalidate()
        timer = nil
    }

    private func parseMessagesResponse(responseObject: Any?) -> (envelopes: [SSKProtoEnvelope], more: Bool)? {
        guard let responseObject = responseObject else {
            Logger.error("response object was surpringly nil")
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

    private func buildEnvelope(messageDict: [String: Any]) -> SSKProtoEnvelope? {
        do {
            let params = ParamParser(dictionary: messageDict)

            let typeInt: Int32 = try params.required(key: "type")
            guard let type: SSKProtoEnvelope.SSKProtoEnvelopeType = SSKProtoEnvelope.SSKProtoEnvelopeType(rawValue: typeInt) else {
                Logger.error("`type` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("type")
            }

            guard let source: String = try params.required(key: "source") else {
                Logger.error("`source` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("source")
            }

            guard let timestamp: UInt64 = try params.required(key: "timestamp") else {
                Logger.error("`timestamp` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("timestamp")
            }

            guard let sourceDevice: UInt32 = try params.required(key: "sourceDevice") else {
                Logger.error("`sourceDevice` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("sourceDevice")
            }

            let builder = SSKProtoEnvelope.SSKProtoEnvelopeBuilder(type: type, source: source, sourceDevice: sourceDevice, timestamp: timestamp)

            if let legacyMessage = try params.optionalBase64EncodedData(key: "message") {
                builder.setLegacyMessage(legacyMessage)
            }
            if let content = try params.optionalBase64EncodedData(key: "content") {
                builder.setContent(content)
            }

            return try builder.build()
        } catch {
            owsFailDebug("error building envelope: \(error)")
            return nil
        }
    }

    private func fetchUndeliveredMessages() -> Promise<(envelopes: [SSKProtoEnvelope], more: Bool)> {
        return Promise { fulfill, reject in
            let request = OWSRequestFactory.getMessagesRequest()
            self.networkManager.makeRequest(
                request,
                success: { (_: URLSessionDataTask?, responseObject: Any?) -> Void in
                    guard let (envelopes, more) = self.parseMessagesResponse(responseObject: responseObject) else {
                        Logger.error("response object had unexpected content")
                        return reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    fulfill((envelopes: envelopes, more: more))
                },
                failure: { (_: URLSessionDataTask?, error: Error?) in
                    guard let error = error else {
                        Logger.error("error was surpringly nil. sheesh rough day.")
                        return reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    reject(error)
            })
        }
    }

    private func acknowledgeDelivery(envelope: SSKProtoEnvelope) {
        let source = envelope.source
        let request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(withSource: source, timestamp: envelope.timestamp)
        self.networkManager.makeRequest(request,
                                        success: { (_: URLSessionDataTask?, _: Any?) -> Void in
                                            Logger.debug("acknowledged delivery for message at timestamp: \(envelope.timestamp)")
        },
                                        failure: { (_: URLSessionDataTask?, error: Error?) in
                                            Logger.debug("acknowledging delivery for message at timestamp: \(envelope.timestamp) failed with error: \(String(describing: error))")
        })
    }
}
