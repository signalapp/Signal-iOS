//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import LibSignalClient

/// An ObjC wrapper around UnidentifiedSenderMessageContent.ContentHint
@objc
public enum SealedSenderContentHint: Int, CustomStringConvertible {
    /// Indicates that the content of a message requires rendering user-visible errors immediately
    /// upon decryption failure. It is not expected that it will be resent, and we make no attempt
    /// to preserve ordering if it is.
    /// Insert a placeholder: No
    /// Show error to user: Yes, immediately
    case `default` = 0
    /// Indicates that the content of a message requires rendering user-visible errors upon
    /// decryption failure, but errors will be delayed in case the message is resent before
    /// the user attempts to view it. In order to facilitate insertion of resent messages in situ, a
    /// placeholder is inserted into the interaction table to reserve its positioning.
    /// Insert a placeholder: Yes
    /// Show error to user: Yes, after some deferral period
    case resendable
    /// Indicates that the content of a message does not require rendering any user-visible
    /// errors upon decryption failure. These messages may be resent, but we don't insert
    /// a placeholder for them so their ordering is not preserved.
    /// Insert a placeholder: No
    /// Show error to user: No
    case implicit

    init(_ signalClientHint: UnidentifiedSenderMessageContent.ContentHint) {
        switch signalClientHint {
        case .default: self = .default
        case .resendable: self = .resendable
        case .implicit: self = .implicit
        default:
            owsFailDebug("Unspecified case \(signalClientHint)")
            self = .default
        }
    }

    public var signalClientHint: UnidentifiedSenderMessageContent.ContentHint {
        switch self {
        case .default: return .default
        case .resendable: return .resendable
        case .implicit: return .implicit
        }
    }

    public var description: String {
        switch self {
        case .default: return "default"
        case .resendable: return "resendable"
        case .implicit: return "implicit"
        }
    }
}

// MARK: -

extension OWSMessageManager {

    private static let pendingTasks = PendingTasks(label: "messageManager")

    public static func pendingTasksPromise() -> Promise<Void> {
        // This promise blocks on all pending tasks already in flight,
        // but will not block on new tasks enqueued after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }

    @objc
    public static func buildPendingTask(label: String) -> PendingTask {
        Self.pendingTasks.buildPendingTask(label: label)
    }

    @objc
    public func updateApplicationBadgeCount() {
        let readUnreadCount: (SDSAnyReadTransaction) -> UInt = { transaction in
            InteractionFinder.unreadCountInAllThreads(transaction: transaction.unwrapGrdbRead)
        }

        let fetchBadgeCount = { () -> Promise<UInt> in
            // The main app gets to perform this synchronously
            if CurrentAppContext().isMainApp {
                return .value(self.databaseStorage.read(block: readUnreadCount))
            } else {
                return self.databaseStorage.read(.promise, readUnreadCount)
            }
        }

        fetchBadgeCount().done {
            CurrentAppContext().setMainAppBadgeNumber(Int($0))
        }.catch { error in
            owsFailDebug("Failed to update badge number: \(error)")
        }
    }

    @objc
    func isValidEnvelope(_ envelope: SSKProtoEnvelope) -> Bool {
        return envelope.isValid
    }

    /// Performs a limited amount of time sensitive processing before scheduling the remainder of message processing
    ///
    /// Currently, the preprocess step only parses sender key distribution messages to update the sender key store. It's important
    /// the sender key store is updated *before* the write transaction completes since we don't know if the next message to be
    /// decrypted will depend on the sender key store being up to date.
    ///
    /// Some other things worth noting:
    /// - We should preprocess *all* envelopes, even those where the sender is blocked. This is important because it protects us
    /// from a case where the recipeint blocks and then unblocks a user. If the sender they blocked sent an SKDM while the user was
    /// blocked, their understanding of the world is that we have saved the SKDM. After unblock, if we don't have the SKDM we'll fail
    /// to decrypt.
    /// - This *needs* to happen in the very same write transaction where the message was decrypted. It's important to keep in mind
    /// that the NSE could race with the main app when processing messages. The write transaction is used to protect us from any races.
    @objc
    func preprocessEnvelope(envelope: SSKProtoEnvelope, plaintext: Data?, transaction: SDSAnyWriteTransaction) {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            owsFail("Should not process messages")
        }
        guard self.tsAccountManager.isRegistered else {
            owsFailDebug("Not registered")
            return
        }
        guard isValidEnvelope(envelope) else {
            owsFailDebug("Invalid envelope")
            return
        }
        guard let plaintext = plaintext else {
            Logger.warn("No plaintext")
            return
        }

        // Currently, this function is only used for SKDM processing
        // Since this is idempotent, we don't need to check for a duplicate envelope.
        //
        // SKDM proecessing is also not user-visible, so we don't want to skip if the sender is
        // blocked. This ensures that we retain session info to decrypt future messages from a blocked
        // sender if they're ever unblocked.
        let contentProto: SSKProtoContent
        do {
            contentProto = try SSKProtoContent(serializedData: plaintext)
        } catch {
            owsFailDebug("Failed to deserialize content proto: \(error)")
            return
        }

        if let skdmBytes = contentProto.senderKeyDistributionMessage {
            Logger.info("Preprocessing content: \(description(for: contentProto))")
            handleIncomingEnvelope(envelope, withSenderKeyDistributionMessage: skdmBytes, transaction: transaction)
        }
    }

    @objc
    func handleIncomingEnvelope(
        _ envelope: SSKProtoEnvelope,
        withSenderKeyDistributionMessage skdmData: Data,
        transaction writeTx: SDSAnyWriteTransaction) {

        guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
            return owsFailDebug("Invalid source address")
        }

        do {
            let skdm = try SenderKeyDistributionMessage(bytes: skdmData.map { $0 })
            let sourceDeviceId = envelope.sourceDevice
            let protocolAddress = try ProtocolAddress(from: sourceAddress, deviceId: sourceDeviceId)
            try processSenderKeyDistributionMessage(skdm, from: protocolAddress, store: senderKeyStore, context: writeTx)

            Logger.info("Processed incoming sender key distribution message. Sender: \(sourceAddress).\(sourceDeviceId)")

        } catch {
            owsFailDebug("Failed to process incoming sender key \(error)")
        }
    }

    @objc
    func handleIncomingEnvelope(
        _ envelope: SSKProtoEnvelope,
        withDecryptionErrorMessage bytes: Data,
        transaction writeTx: SDSAnyWriteTransaction
    ) {
        guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
            return owsFailDebug("Invalid source address")
        }
        let sourceDeviceId = envelope.sourceDevice

        do {
            let errorMessage = try DecryptionErrorMessage(bytes: bytes)
            guard errorMessage.deviceId == tsAccountManager.storedDeviceId() else {
                Logger.info("Received a DecryptionError message targeting a linked device. Ignoring.")
                return
            }
            let protocolAddress = try ProtocolAddress(from: sourceAddress, deviceId: sourceDeviceId)

            let didPerformSessionReset: Bool

            if let ratchetKey = errorMessage.ratchetKey {
                // If a ratchet key is included, this was a 1:1 session message
                // Archive the session if the current key matches.
                // PNI TODO: We should never get a DEM for our PNI, but we should check that anyway.
                let sessionStore = signalProtocolStore(for: .aci).sessionStore
                let sessionRecord = try sessionStore.loadSession(for: protocolAddress, context: writeTx)
                if try sessionRecord?.currentRatchetKeyMatches(ratchetKey) == true {
                    Logger.info("Decryption error included ratchet key. Archiving...")
                    sessionStore.archiveSession(for: sourceAddress,
                                                deviceId: Int32(sourceDeviceId),
                                                transaction: writeTx)
                    didPerformSessionReset = true
                } else {
                    Logger.info("Ratchet key mismatch. Leaving session as-is.")
                    didPerformSessionReset = false
                }
            } else {
                // If we don't have a ratchet key, this was a sender key session message.
                // Let's log any info about SKDMs that we had sent to the address requesting resend
                senderKeyStore.logSKDMInfo(for: sourceAddress, transaction: writeTx)
                didPerformSessionReset = false
            }

            Logger.warn("Performing message resend of timestamp \(errorMessage.timestamp)")
            let resendResponse = OWSOutgoingResendResponse(
                address: sourceAddress,
                deviceId: Int64(sourceDeviceId),
                failedTimestamp: Int64(errorMessage.timestamp),
                didResetSession: didPerformSessionReset,
                transaction: writeTx
            )

            let sendBlock = { (transaction: SDSAnyWriteTransaction) in
                if let resendResponse = resendResponse {
                    Self.messageSenderJobQueue.add(message: resendResponse.asPreparer, transaction: transaction)
                }
            }

            if DebugFlags.delayedMessageResend.get() {
                DispatchQueue.sharedUtility.asyncAfter(deadline: .now() + 10) {
                    Self.databaseStorage.asyncWrite { writeTx in
                        sendBlock(writeTx)
                    }
                }
            } else {
                sendBlock(writeTx)
            }

        } catch {
            owsFailDebug("Failed to process decryption error message \(error)")
        }
    }

    @objc
    public static func descriptionForDataMessageContents(_ dataMessage: SSKProtoDataMessage) -> String {
        var splits = [String]()
        if !dataMessage.attachments.isEmpty {
            splits.append("attachments: \(dataMessage.attachments.count)")
        }
        if dataMessage.group != nil {
            splits.append("groupV1")
        }
        if dataMessage.groupV2 != nil {
            splits.append("groupV2")
        }
        if dataMessage.quote != nil {
            splits.append("quote")
        }
        if !dataMessage.contact.isEmpty {
            splits.append("contacts: \(dataMessage.contact.count)")
        }
        if !dataMessage.preview.isEmpty {
            splits.append("previews: \(dataMessage.preview.count)")
        }
        if dataMessage.sticker != nil {
            splits.append("sticker")
        }
        if dataMessage.reaction != nil {
            splits.append("reaction")
        }
        if dataMessage.delete != nil {
            splits.append("delete")
        }
        if !dataMessage.bodyRanges.isEmpty {
            splits.append("bodyRanges: \(dataMessage.bodyRanges.count)")
        }
        if dataMessage.groupCallUpdate != nil {
            splits.append("groupCallUpdate")
        }
        if dataMessage.payment != nil {
            splits.append("payment")
        }
        if dataMessage.body?.nilIfEmpty != nil {
            splits.append("body")
        }
        if dataMessage.expireTimer > 0 {
            splits.append("expireTimer")
        }
        if dataMessage.profileKey != nil {
            splits.append("profileKey")
        }
        if dataMessage.isViewOnce {
            splits.append("isViewOnce")
        }
        if dataMessage.flags > 0 {
            splits.append("flags: \(dataMessage.flags)")
        }
        return "[" + splits.joined(separator: ", ") + "]"
    }
}

extension SSKProtoEnvelope {
    var isValid: Bool {
        guard timestamp >= 1 else {
            owsFailDebug("Invalid timestamp")
            return false
        }
        guard SDS.fitsInInt64(timestamp) else {
            owsFailDebug("Invalid timestamp")
            return false
        }
        guard hasValidSource else {
            owsFailDebug("Invalid source")
            return false
        }
        guard sourceDevice >= 1 else {
            owsFailDebug("Invalid source device")
            return false
        }
        return true
    }

    @objc
    var formattedAddress: String {
        return "\(String(describing: sourceAddress)).\(sourceDevice)"
    }
}

extension SSKProtoContent {
    @objc
    var contentDescription: String {
        var message = String()
        if let syncMessage = self.syncMessage {
            message.append("<SyncMessage: \(syncMessage.contentDescription) />")
        } else if let dataMessage = self.dataMessage {
            message.append("<DataMessage: \(dataMessage.contentDescription) />")
        } else if let callMessage = self.callMessage {
            message.append("<CallMessage \(callMessage.contentDescription) />")
        } else if let nullMessage = self.nullMessage {
            message.append("<NullMessage: \(nullMessage) />")
        } else if let receiptMessage = self.receiptMessage {
            message.append("<ReceiptMessage: \(receiptMessage) />")
        } else if let typingMessage = self.typingMessage {
            message.append("<TypingMessage: \(typingMessage) />")
        } else if let decryptionErrorMessage = self.decryptionErrorMessage {
            message.append("<DecryptionErrorMessage: \(decryptionErrorMessage) />")
        } else if let storyMessage = self.storyMessage {
            message.append("<StoryMessage: \(storyMessage) />")
        }

         // SKDM's are not mutually exclusive with other content types
         if hasSenderKeyDistributionMessage {
             if !message.isEmpty {
                 message.append(" + ")
             }
             message.append("SenderKeyDistributionMessage")
         }

        if message.isEmpty {
            // Don't fire an analytics event; if we ever add a new content type, we'd generate a ton of
            // analytics traffic.
            owsFailDebug("Unknown content type.")
            return "UnknownContent"

        }
        return message
    }
}

extension SSKProtoCallMessage {
    @objc
    var contentDescription: String {
        let messageType: String
        let callId: UInt64

        if let offer = self.offer {
            messageType = "Offer"
            callId = offer.id
        } else if let busy = self.busy {
            messageType = "Busy"
            callId = busy.id
        } else if let answer = self.answer {
            messageType = "Answer"
            callId = answer.id
        } else if let legacyHangup = self.legacyHangup {
            messageType = "legacyHangup"
            callId = legacyHangup.id
        } else if let hangup = self.hangup {
            messageType = "Hangup"
            callId = hangup.id
        } else if let firstICEUpdate = iceUpdate.first {
            messageType = "Ice Updates \(iceUpdate.count)"
            callId = firstICEUpdate.id
        } else if let opaque = self.opaque {
            if opaque.hasUrgency {
                messageType = "Opaque (\(opaque.unwrappedUrgency.contentDescription))"
            } else {
                messageType = "Opaque"
            }
            callId = 0
        } else {
            owsFailDebug("failure: unexpected call message type: \(self)")
            messageType = "Unknown"
            callId = 0
        }

        return "type: \(messageType), id: \(callId)"
    }
}

extension SSKProtoCallMessageOpaqueUrgency {
    var contentDescription: String {
        switch self {
        case .droppable:
            return "Droppable"
        case .handleImmediately:
            return "HandleImmediately"
        default:
            return "Unknown"
        }
    }
}

extension SSKProtoDataMessage {
    @objc
    var contentDescription: String {
        var parts = [String]()
        if group != nil {
            parts.append("(Group:YES) )")
        }
        if Int64(flags) & Int64(SSKProtoDataMessageFlags.endSession.rawValue) != 0 {
            parts.append("EndSession")
        } else if Int64(flags) & Int64(SSKProtoDataMessageFlags.expirationTimerUpdate.rawValue) != 0 {
            parts.append("ExpirationTimerUpdate")
        } else if Int64(flags) & Int64(SSKProtoDataMessageFlags.profileKeyUpdate.rawValue) != 0 {
            parts.append("ProfileKey")
        } else if attachments.count > 0 {
            parts.append("MessageWithAttachment")
        } else {
            parts.append("Plain")
        }
        return "<\(parts.joined(separator: " ")) />"
    }
}

extension SSKProtoSyncMessage {
    @objc
    var contentDescription: String {
        if sent != nil {
            return "SentTranscript"
        }
        if contacts != nil {
            return "Contacts"
        }
        if groups != nil {
            return "Groups"
        }
        if let request = self.request {
            if !request.hasType {
                return "Unknown sync request."
            }
            switch request.unwrappedType {
            case .contacts:
                return "ContactRequest"
            case .groups:
                return "GroupRequest"
            case .blocked:
                return "BlockedRequest"
            case .configuration:
                return "ConfigurationRequest"
            case .keys:
                return "KeysRequest"
            case .pniIdentity:
                return "PniIdentityRequest"
            default:
                owsFailDebug("Unknown sync message request type")
                return "UnknownRequest"
            }
        }
        if !read.isEmpty {
            return "ReadReceipt"
        }
        if blocked != nil {
            return "Blocked"
        }
        if let verified = verified {
            return "Verification for: \(String(describing: verified.destinationAddress))"
        }
        if configuration != nil {
            return "Configuration"
        }
        if !stickerPackOperation.isEmpty {
            var operationTypes = [String]()
            for packOperationProto in stickerPackOperation {
                if !packOperationProto.hasType {
                    operationTypes.append("unknown")
                    continue
                }
                switch packOperationProto.unwrappedType {
                case .install:
                    operationTypes.append("install")
                case .remove:
                    operationTypes.append("remove")
                default:
                    operationTypes.append("unknown")
                }
            }
            return "StickerPackOperation: \(operationTypes.joined(separator: ", "))"
        }
        if viewOnceOpen != nil {
            return "ViewOnceOpen"
        }
        if let fetchLatest = fetchLatest {
            switch fetchLatest.unwrappedType {
            case .unknown:
                return "FetchLatest_Unknown"
            case .localProfile:
                return "FetchLatest_LocalProfile"
            case .storageManifest:
                return "FetchLatest_StorageManifest"
            case .subscriptionStatus:
                return "FetchLatest_SubscriptionStatus"
            }
        }
        if keys != nil {
            return "Keys"
        }
        if messageRequestResponse != nil {
            return "MessageRequestResponse"
        }
        if outgoingPayment != nil {
            return "OutgoingPayment"
        }
        if !viewed.isEmpty {
            return "ViewedReceipt"
        }
        if pniIdentity != nil {
            return "PniIdentity"
        }
        owsFailDebug("Unknown sync message type")
        return "Unknown"

    }
}

@objc
class MessageManagerRequest: NSObject {
    @objc
    let envelope: SSKProtoEnvelope

    @objc
    let plaintextData: Data

    @objc
    let wasReceivedByUD: Bool

    @objc
    let serverDeliveryTimestamp: UInt64

    @objc
    let shouldDiscardVisibleMessages: Bool

    enum Kind {
        case modern(SSKProtoContent)
        case unactionable
    }
    private let kind: Kind

    @objc
    var protoContent: SSKProtoContent? {
        switch kind {
        case .modern(let content):
            return content
        case .unactionable:
            return nil
        }
    }

    @objc
    var messageType: OWSMessageManagerMessageType {
        if protoContent?.syncMessage != nil {
            return .syncMessage
        }
        if protoContent?.dataMessage != nil {
            return .dataMessage
        }
        if protoContent?.callMessage != nil {
            return .callMessage
        }
        if protoContent?.typingMessage != nil {
            return .typingMessage
        }
        if protoContent?.nullMessage != nil {
            return .nullMessage
        }
        if protoContent?.receiptMessage != nil {
            return .receiptMessage
        }
        if protoContent?.decryptionErrorMessage != nil {
            return .decryptionErrorMessage
        }
        if protoContent?.storyMessage != nil {
            return .storyMessage
        }
        if protoContent?.hasSenderKeyDistributionMessage ?? false {
            return .hasSenderKeyDistributionMessage
        }
        return .unknown
    }

    @objc
    init?(envelope: SSKProtoEnvelope,
          plaintextData: Data,
          wasReceivedByUD: Bool,
          serverDeliveryTimestamp: UInt64,
          shouldDiscardVisibleMessages: Bool,
          transaction: SDSAnyWriteTransaction) {
        guard envelope.isValid, let sourceAddress = envelope.sourceAddress else {
            owsFailDebug("Missing envelope")
            return nil
        }
        self.envelope = envelope
        self.plaintextData = plaintextData
        self.wasReceivedByUD = wasReceivedByUD
        self.serverDeliveryTimestamp = serverDeliveryTimestamp
        self.shouldDiscardVisibleMessages = shouldDiscardVisibleMessages

        if Self.isDuplicate(envelope, address: sourceAddress, transaction: transaction) {
            Logger.info("Ignoring previously received envelope from \(envelope.formattedAddress) with timestamp: \(envelope.timestamp)")
            return nil
        }

        if envelope.content != nil {
            do {
                let contentProto = try SSKProtoContent(serializedData: self.plaintextData)
                Logger.info("handling content: <Content: \(contentProto.contentDescription)>")
                if contentProto.callMessage != nil && shouldDiscardVisibleMessages {
                    Logger.info("Discarding message with timestamp \(envelope.timestamp)")
                    return nil
                }

                if envelope.story {
                    guard StoryManager.areStoriesEnabled(transaction: transaction) else {
                        Logger.info("Discarding story message received while stories are disabled")
                        return nil
                    }
                    guard contentProto.storyMessage != nil || (contentProto.dataMessage?.storyContext != nil && contentProto.dataMessage?.groupV2 != nil) else {
                        owsFailDebug("Discarding story message with invalid content.")
                        return nil
                    }
                }

                kind = .modern(contentProto)
            } catch {
                owsFailDebug("could not parse proto: \(error)")
                return nil
            }
        } else {
            kind = .unactionable
        }
    }

    private static func isDuplicate(_ envelope: SSKProtoEnvelope,
                                    address: SignalServiceAddress,
                                    transaction: SDSAnyReadTransaction) -> Bool {
        return InteractionFinder.existsIncomingMessage(timestamp: envelope.timestamp,
                                                       address: address,
                                                       sourceDeviceId: envelope.sourceDevice,
                                                       transaction: transaction)
    }
}
