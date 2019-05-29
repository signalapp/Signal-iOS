//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc(OWSMessageFetcherJob)
public class MessageFetcherJob: NSObject {

    private var timer: Timer?

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: Singletons

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var messageReceiver: OWSMessageReceiver {
        return SSKEnvironment.shared.messageReceiver
    }

    private var signalService: OWSSignalService {
        return OWSSignalService.sharedInstance()
    }

    // MARK: 

    @discardableResult
    public func run() -> Promise<Void> {
        Logger.debug("")

        guard signalService.isCensorshipCircumventionActive else {
            Logger.debug("delegating message fetching to SocketManager since we're using normal transport.")
            TSSocketManager.shared.requestSocketOpen()
            return Promise.value(())
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
                return Promise.value(())
            }
        }

        promise.retainUntilComplete()

        return promise
    }

    @objc
    @discardableResult
    public func run() -> AnyPromise {
        return AnyPromise(run() as Promise)
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

            guard let timestamp: UInt64 = try params.required(key: "timestamp") else {
                Logger.error("`timestamp` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("timestamp")
            }

            let builder = SSKProtoEnvelope.builder(timestamp: timestamp)
            builder.setType(type)

            if let source: String = try params.optional(key: "source") {
                builder.setSource(source)
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

    private func fetchUndeliveredMessages() -> Promise<(envelopes: [SSKProtoEnvelope], more: Bool)> {
        return Promise { resolver in
            let request = OWSRequestFactory.getMessagesRequest()
            self.networkManager.makeRequest(
                request,
                success: { (_: URLSessionDataTask?, responseObject: Any?) -> Void in
                    guard let (envelopes, more) = self.parseMessagesResponse(responseObject: responseObject) else {
                        Logger.error("response object had unexpected content")
                        return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    resolver.fulfill((envelopes: envelopes, more: more))
                },
                failure: { (_: URLSessionDataTask?, error: Error?) in
                    guard let error = error else {
                        Logger.error("error was surpringly nil. sheesh rough day.")
                        return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    resolver.reject(error)
            })
        }
    }

    private func acknowledgeDelivery(envelope: SSKProtoEnvelope) {
        let request: TSRequest
        if let serverGuid = envelope.serverGuid, serverGuid.count > 0 {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(withServerGuid: serverGuid)
        } else if let source = envelope.source, source.count > 0, envelope.timestamp > 0 {
            request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(withSource: source, timestamp: envelope.timestamp)
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
