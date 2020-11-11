//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalUtilitiesKit

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
        let promise = fetchUndeliveredMessages().then { promises -> Promise<Void> in
            let promises = promises.map { promise -> Promise<Void> in
                return promise.then { envelopes -> Promise<Void> in
                    for envelope in envelopes {
                        Logger.info("Envelope received.")
                        do {
                            let envelopeData = try envelope.serializedData()
                            self.messageReceiver.handleReceivedEnvelopeData(envelopeData)
                        } catch {
                            owsFailDebug("Failed to serialize envelope.")
                        }
                        self.acknowledgeDelivery(envelope: envelope)
                    }
                    return Promise.value(())
                }
            }
            return when(resolved: promises).asVoid()
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

            let builder = SSKProtoEnvelope.builder(type: type, timestamp: timestamp)

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

    private func fetchUndeliveredMessages() -> Promise<Set<Promise<[SSKProtoEnvelope]>>> {
        let userPublickKey = getUserHexEncodedPublicKey() // Can be missing in rare cases
        guard !userPublickKey.isEmpty else { return Promise.value(Set()) }
        return Promise.value(Set())
    }

    private func acknowledgeDelivery(envelope: SSKProtoEnvelope) {
        // Do nothing
    }
}
