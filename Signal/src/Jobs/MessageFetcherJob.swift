//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSMessageFetcherJob)
class MessageFetcherJob: NSObject {

    private let TAG = "[MessageFetcherJob]"

    private var timer: Timer?

    // MARK: injected dependencies
    private let networkManager: TSNetworkManager
    private let messageReceiver: OWSMessageReceiver
    private let signalService: OWSSignalService

    init(messageReceiver: OWSMessageReceiver, networkManager: TSNetworkManager, signalService: OWSSignalService) {
        self.messageReceiver = messageReceiver
        self.networkManager = networkManager
        self.signalService = signalService
    }

    public func run() -> Promise<Void> {
        Logger.debug("\(TAG) in \(#function)")

        guard signalService.isCensorshipCircumventionActive else {
            Logger.debug("\(self.TAG) delegating message fetching to SocketManager since we're using normal transport.")
            TSSocketManager.requestSocketOpen()
            return Promise(value: ())
        }

        Logger.info("\(TAG) fetching messages via REST.")

        let promise = self.fetchUndeliveredMessages().then { (envelopes: [OWSSignalServiceProtosEnvelope], more: Bool) -> Promise<Void> in
            for envelope in envelopes {
                Logger.info("\(self.TAG) received envelope.")
                self.messageReceiver.handleReceivedEnvelope(envelope)
                self.acknowledgeDelivery(envelope: envelope)
            }

            if more {
                Logger.info("\(self.TAG) fetching more messages.")
                return self.run()
            } else {
                // All finished
                return Promise(value: ())
            }
        }

        promise.retainUntilComplete()

        return promise
    }

    @objc func run() -> AnyPromise {
        return AnyPromise(run())
    }

    // use in DEBUG or wherever you can't receive push notifications to poll for messages.
    // Do not use in production.
    public func startRunLoop(timeInterval: Double) {
        Logger.error("\(TAG) Starting message fetch polling. This should not be used in production.")
        timer = WeakTimer.scheduledTimer(timeInterval: timeInterval, target: self, userInfo: nil, repeats: true) {[weak self] _ in
            let _: Promise<Void>? = self?.run()
            return
        }
    }

    public func stopRunLoop() {
        timer?.invalidate()
        timer = nil
    }

    private func parseMessagesResponse(responseObject: Any?) -> (envelopes: [OWSSignalServiceProtosEnvelope], more: Bool)? {
        guard let responseObject = responseObject else {
            Logger.error("\(self.TAG) response object was surpringly nil")
            return nil
        }

        guard let responseDict = responseObject as? [String: Any] else {
            Logger.error("\(self.TAG) response object was not a dictionary")
            return nil
        }

        guard let messageDicts = responseDict["messages"] as? [[String: Any]] else {
            Logger.error("\(self.TAG) messages object was not a list of dictionaries")
            return nil
        }

        let moreMessages = { () -> Bool in
            if let responseMore = responseDict["more"] as? Bool {
                return responseMore
            } else {
                Logger.warn("\(self.TAG) more object was not a bool. Assuming no more")
                return false
            }
        }()

        let envelopes = messageDicts.map { buildEnvelope(messageDict: $0) }.filter { $0 != nil }.map { $0! }

        return (
            envelopes: envelopes,
            more: moreMessages
        )
    }

    private func buildEnvelope(messageDict: [String: Any]) -> OWSSignalServiceProtosEnvelope? {
        let builder = OWSSignalServiceProtosEnvelopeBuilder()

        guard let typeInt = messageDict["type"] as? Int32 else {
            Logger.error("\(TAG) message body didn't have type")
            return nil
        }

        guard let type = OWSSignalServiceProtosEnvelopeType(rawValue:typeInt) else {
            Logger.error("\(TAG) message body type was invalid")
            return nil
        }
        builder.setType(type)

        if let relay = messageDict["relay"] as? String {
            builder.setRelay(relay)
        }

        guard let timestamp = messageDict["timestamp"] as? UInt64 else {
            Logger.error("\(TAG) message body didn't have timestamp")
            return nil
        }
        builder.setTimestamp(timestamp)

        guard let source = messageDict["source"] as? String else {
            Logger.error("\(TAG) message body didn't have source")
            return nil
        }
        builder.setSource(source)

        guard let sourceDevice = messageDict["sourceDevice"] as? UInt32 else {
            Logger.error("\(TAG) message body didn't have sourceDevice")
            return nil
        }
        builder.setSourceDevice(sourceDevice)

        if let encodedLegacyMessage = messageDict["message"] as? String {
            Logger.debug("\(TAG) message body had legacyMessage")
            if let legacyMessage = Data(base64Encoded: encodedLegacyMessage) {
                builder.setLegacyMessage(legacyMessage)
            }
        }

        if let encodedContent = messageDict["content"] as? String {
            Logger.debug("\(TAG) message body had content")
            if let content = Data(base64Encoded: encodedContent) {
                builder.setContent(content)
            }
        }

        return builder.build()
    }

    private func fetchUndeliveredMessages() -> Promise<(envelopes: [OWSSignalServiceProtosEnvelope], more: Bool)> {
        return Promise { fulfill, reject in
            let messagesRequest = OWSGetMessagesRequest()

            self.networkManager.makeRequest(
                messagesRequest,
                success: { (_: URLSessionDataTask?, responseObject: Any?) -> Void in
                    guard let (envelopes, more) = self.parseMessagesResponse(responseObject: responseObject) else {
                        Logger.error("\(self.TAG) response object had unexpected content")
                        return reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    fulfill((envelopes: envelopes, more: more))
                },
                failure: { (_: URLSessionDataTask?, error: Error?) in
                    guard let error = error else {
                        Logger.error("\(self.TAG) error was surpringly nil. sheesh rough day.")
                        return reject(OWSErrorMakeUnableToProcessServerResponseError())
                    }

                    reject(error)
            })
        }
    }

    private func acknowledgeDelivery(envelope: OWSSignalServiceProtosEnvelope) {
        let request = OWSAcknowledgeMessageDeliveryRequest(source: envelope.source, timestamp: envelope.timestamp)
        self.networkManager.makeRequest(request,
                                        success: { (_: URLSessionDataTask?, _: Any?) -> Void in
                                            Logger.debug("\(self.TAG) acknowledged delivery for message at timestamp: \(envelope.timestamp)")
        },
                                        failure: { (_: URLSessionDataTask?, error: Error?) in
                                            Logger.debug("\(self.TAG) acknowledging delivery for message at timestamp: \(envelope.timestamp) failed with error: \(String(describing: error))")
        })
    }
}
