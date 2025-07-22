//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: -

public class MessageFetcherJob {

    private let appReadiness: AppReadiness
    private var messageProcessor: MessageProcessor { SSKEnvironment.shared.messageProcessorRef }

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness

        SwiftSingletons.register(self)
    }

    private static let didChangeStateNotificationName = Notification.Name("MessageFetcherJob.didChangeStateNotificationName")

    // MARK: -

    public func fetchViaRest() async throws {
        owsPrecondition(CurrentAppContext().shouldProcessIncomingMessages)
        owsPrecondition(CurrentAppContext().isNSE)
        owsPrecondition(self.appReadiness.isAppReady)
        owsAssertDebug(DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered)

        await self.startGroupMessageProcessorsIfNeeded()
        try await self.fetchMessagesViaRestWhenReady()
    }

    private func startGroupMessageProcessorsIfNeeded() async {
        await SSKEnvironment.shared.groupMessageProcessorManagerRef.startAllProcessors()
    }

    public var hasCompletedInitialFetch: Bool {
        get async {
            let chatConnectionManager = DependenciesBridge.shared.chatConnectionManager
            return await chatConnectionManager.hasEmptiedInitialQueue || self.didFinishFetchingViaREST.get()
        }
    }

    func preconditionForFetchingComplete() -> some Precondition {
        return NotificationPrecondition(
            notificationNames: [OWSChatConnection.chatConnectionStateDidChange, Self.didChangeStateNotificationName],
            isSatisfied: { await self.hasCompletedInitialFetch }
        )
    }

    // MARK: -

    // We want to have multiple ACKs in flight at a time.
    private let ackQueue = ConcurrentTaskQueue(concurrentLimit: 5)

    private let pendingAcks = PendingTasks()

    private func acknowledgeDelivery(envelopeInfo: EnvelopeInfo) {
        let pendingAck = pendingAcks.buildPendingTask()
        Task {
            defer {
                pendingAck.complete()
            }
            do {
                try await self.ackQueue.run {
                    try await self._acknowledgeDelivery(envelopeInfo: envelopeInfo)
                }
            } catch {
                Logger.warn("Couldn't ACK \(envelopeInfo.timestamp): \(error)")
            }
        }
    }

    private func _acknowledgeDelivery(envelopeInfo: EnvelopeInfo) async throws {
        try await Retry.performWithBackoff(maxAttempts: 3) {
            guard let serverGuid = envelopeInfo.serverGuid, !serverGuid.isEmpty else {
                throw OWSAssertionError("Can't ACK message without serverGuid.")
            }
            let request = OWSRequestFactory.acknowledgeMessageDeliveryRequest(serverGuid: serverGuid)
            _ = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request, canUseWebSocket: false)
        }
    }

    public func waitForPendingAcks() async throws {
        try await pendingAcks.waitForPendingTasks()
    }

    // MARK: -

    private struct EnvelopeJob {
        let encryptedEnvelope: SSKProtoEnvelope
        let completion: () -> Void
    }

    private let didFinishFetchingViaREST = AtomicBool(false, lock: .init())

    public func prepareToFetchViaREST() {
        self.didFinishFetchingViaREST.set(false)
    }

    private func fetchMessagesViaRest() async throws {
        let batch = try await Retry.performWithBackoff(maxAttempts: 6) {
            return try await fetchBatchViaRest()
        }

        let envelopeJobs: [EnvelopeJob] = batch.envelopes.map { envelope in
            let envelopeInfo = Self.buildEnvelopeInfo(envelope: envelope)
            return EnvelopeJob(encryptedEnvelope: envelope) {
                self.acknowledgeDelivery(envelopeInfo: envelopeInfo)
            }
        }

        for job in envelopeJobs {
            SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelope(
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
            NotificationCenter.default.postOnMainThread(name: MessageFetcherJob.didChangeStateNotificationName, object: nil)
        }
    }

    private func fetchMessagesViaRestWhenReady() async throws {
        try await messageProcessor.waitForFetchingAndProcessing(stages: [.messageProcessor])
        try await waitForPendingAcks()
        try await fetchMessagesViaRest()
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
            if let updatedPni: String = try params.optional(key: "updatedPni") {
                builder.setUpdatedPni(updatedPni)
            }
            if let urgent: Bool = try params.optional(key: "urgent") {
                builder.setUrgent(urgent)
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
        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request, canUseWebSocket: false)
        guard let json = response.responseBodyJson else {
            throw OWSAssertionError("Missing or invalid JSON")
        }
        guard
            let timestampString = response.headers["x-signal-timestamp"],
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
