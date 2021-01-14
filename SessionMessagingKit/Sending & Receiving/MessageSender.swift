import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

@objc(SNMessageSender)
public final class MessageSender : NSObject {

    // MARK: Error
    public enum Error : LocalizedError {
        case invalidMessage
        case protoConversionFailed
        case proofOfWorkCalculationFailed
        case noUserX25519KeyPair
        case noUserED25519KeyPair
        case signingFailed
        case encryptionFailed
        // Closed groups
        case noThread
        case noKeyPair
        case invalidClosedGroupUpdate

        internal var isRetryable: Bool {
            switch self {
            case .invalidMessage, .protoConversionFailed, .proofOfWorkCalculationFailed, .invalidClosedGroupUpdate, .signingFailed, .encryptionFailed: return false
            default: return true
            }
        }
        
        public var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .proofOfWorkCalculationFailed: return "Proof of work calculation failed."
            case .noUserX25519KeyPair: return "Couldn't find user X25519 key pair."
            case .noUserED25519KeyPair: return "Couldn't find user ED25519 key pair."
            case .signingFailed: return "Couldn't sign message."
            case .encryptionFailed: return "Couldn't encrypt message."
            // Closed groups
            case .noThread: return "Couldn't find a thread associated with the given group public key."
            case .noKeyPair: return "Couldn't find a private key associated with the given group public key."
            case .invalidClosedGroupUpdate: return "Invalid group update."
            }
        }
    }

    // MARK: Initialization
    private override init() { }

    public static let shared = MessageSender() // FIXME: Remove once requestSenderKey is static

    // MARK: Preparation
    public static func prep(_ signalAttachments: [SignalAttachment], for message: VisibleMessage, using transaction: YapDatabaseReadWriteTransaction) {
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else {
            #if DEBUG
            preconditionFailure()
            #else
            return
            #endif
        }
        var attachments: [TSAttachmentStream] = []
        signalAttachments.forEach {
            let attachment = TSAttachmentStream(contentType: $0.mimeType, byteCount: UInt32($0.dataLength), sourceFilename: $0.sourceFilename,
                caption: $0.captionText, albumMessageId: tsMessage.uniqueId!)
            attachments.append(attachment)
            attachment.write($0.dataSource)
            attachment.save(with: transaction)
        }
        prep(attachments, for: message, using: transaction)
    }
    
    @objc(prep:forMessage:usingTransaction:)
    public static func prep(_ attachmentStreams: [TSAttachmentStream], for message: VisibleMessage, using transaction: YapDatabaseReadWriteTransaction) {
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else {
            #if DEBUG
            preconditionFailure()
            #else
            return
            #endif
        }
        var attachments = attachmentStreams
        // The line below locally generates a thumbnail for the quoted attachment. It just needs to happen at some point during the
        // message sending process.
        tsMessage.quotedMessage?.createThumbnailAttachmentsIfNecessary(with: transaction)
        var linkPreviewAttachmentID: String?
        if let id = tsMessage.linkPreview?.imageAttachmentId,
            let attachment = TSAttachment.fetch(uniqueId: id, transaction: transaction) as? TSAttachmentStream {
            linkPreviewAttachmentID = id
            attachments.append(attachment)
        }
        // Anything added to message.attachmentIDs will be uploaded by an UploadAttachmentJob. Any attachment IDs added to tsMessage will
        // make it render as an attachment (not what we want in the case of a link preview or quoted attachment).
        message.attachmentIDs = attachments.map { $0.uniqueId! }
        tsMessage.attachmentIds.removeAllObjects()
        tsMessage.attachmentIds.addObjects(from: message.attachmentIDs)
        if let id = linkPreviewAttachmentID { tsMessage.attachmentIds.remove(id) }
        tsMessage.save(with: transaction)
    }

    // MARK: Convenience
    public static func send(_ message: Message, to destination: Message.Destination, using transaction: Any) -> Promise<Void> {
        switch destination {
        case .contact(_), .closedGroup(_): return sendToSnodeDestination(destination, message: message, using: transaction)
        case .openGroup(_, _): return sendToOpenGroupDestination(destination, message: message, using: transaction)
        }
    }

    // MARK: One-on-One Chats & Closed Groups
    internal static func sendToSnodeDestination(_ destination: Message.Destination, message: Message, using transaction: Any, isSyncMessage: Bool = false) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let storage = SNMessagingKitConfiguration.shared.storage
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let userPublicKey = storage.getUserPublicKey()
        var isMainAppAndActive = false
        if let sharedUserDefaults = UserDefaults(suiteName: "group.com.loki-project.loki-messenger") {
            isMainAppAndActive = sharedUserDefaults.bool(forKey: "isMainAppActive")
        }
        // Set the timestamp, sender and recipient
        if message.sentTimestamp == nil { // Visible messages will already have their sent timestamp set
            message.sentTimestamp = NSDate.millisecondTimestamp()
        }
        message.sender = userPublicKey
        switch destination {
        case .contact(let publicKey): message.recipient = publicKey
        case .closedGroup(let groupPublicKey): message.recipient = groupPublicKey
        case .openGroup(_, _): preconditionFailure()
        }
        let isSelfSend = (message.recipient == userPublicKey)
        // Set the failure handler (need it here already for precondition failure handling)
        func handleFailure(with error: Swift.Error, using transaction: YapDatabaseReadWriteTransaction) {
            MessageSender.handleFailedMessageSend(message, with: error, using: transaction)
            if case .contact(_) = destination, message is VisibleMessage, !isSelfSend {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .messageSendingFailed, object: NSNumber(value: message.sentTimestamp!))
                }
            }
            seal.reject(error)
        }
        // Validate the message
        guard message.isValid else { handleFailure(with: Error.invalidMessage, using: transaction); return promise }
        // Stop here if this is a self-send (unless it's a configuration message or a sync message)
        guard !isSelfSend || message is ConfigurationMessage || isSyncMessage else {
            storage.write(with: { transaction in
                MessageSender.handleSuccessfulMessageSend(message, to: destination, using: transaction)
                seal.fulfill(())
            }, completion: { })
            return promise
        }
        // Attach the user's profile if needed
        if let message = message as? VisibleMessage {
            let displayName = storage.getUserDisplayName()!
            if let profileKey = storage.getUserProfileKey(), let profilePictureURL = storage.getUserProfilePictureURL() {
                message.profile = VisibleMessage.Profile(displayName: displayName, profileKey: profileKey, profilePictureURL: profilePictureURL)
            } else {
                message.profile = VisibleMessage.Profile(displayName: displayName)
            }
        }
        // Convert it to protobuf
        guard let proto = message.toProto(using: transaction) else { handleFailure(with: Error.protoConversionFailed, using: transaction); return promise }
        // Serialize the protobuf
        let plaintext: Data
        do {
            plaintext = try proto.serializedData()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            handleFailure(with: error, using: transaction)
            return promise
        }
        // Encrypt the serialized protobuf
        if case .contact(_) = destination, message is VisibleMessage, !isSelfSend {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .encryptingMessage, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let ciphertext: Data
        do {
            switch destination {
            case .contact(let publicKey): ciphertext = try encryptWithSessionProtocol(plaintext, for: publicKey)
            case .closedGroup(let groupPublicKey):
                guard let encryptionKeyPair = Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else { throw Error.noKeyPair }
                ciphertext = try encryptWithSessionProtocol(plaintext, for: encryptionKeyPair.hexEncodedPublicKey)
            case .openGroup(_, _): preconditionFailure()
            }
        } catch {
            SNLog("Couldn't encrypt message for destination: \(destination) due to error: \(error).")
            handleFailure(with: error, using: transaction)
            return promise
        }
        // Wrap the result
        let kind: SNProtoEnvelope.SNProtoEnvelopeType
        let senderPublicKey: String
        switch destination {
        case .contact(_):
            kind = .unidentifiedSender
            senderPublicKey = ""
        case .closedGroup(let groupPublicKey):
            kind = .closedGroupCiphertext
            senderPublicKey = groupPublicKey
        case .openGroup(_, _): preconditionFailure()
        }
        let wrappedMessage: Data
        do {
            wrappedMessage = try MessageWrapper.wrap(type: kind, timestamp: message.sentTimestamp!,
                senderPublicKey: senderPublicKey, base64EncodedContent: ciphertext.base64EncodedString())
        } catch {
            SNLog("Couldn't wrap message due to error: \(error).")
            handleFailure(with: error, using: transaction)
            return promise
        }
        // Calculate proof of work
        if case .contact(_) = destination, message is VisibleMessage, !isSelfSend {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .calculatingMessagePoW, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let recipient = message.recipient!
        let base64EncodedData = wrappedMessage.base64EncodedString()
        guard let (timestamp, nonce) = ProofOfWork.calculate(ttl: message.ttl, publicKey: recipient, data: base64EncodedData) else {
            SNLog("Proof of work calculation failed.")
            handleFailure(with: Error.proofOfWorkCalculationFailed, using: transaction)
            return promise
        }
        // Send the result
        if case .contact(_) = destination, message is VisibleMessage, !isSelfSend {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .messageSending, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let snodeMessage = SnodeMessage(recipient: recipient, data: base64EncodedData, ttl: message.ttl, timestamp: timestamp, nonce: nonce)
        SnodeAPI.sendMessage(snodeMessage).done(on: DispatchQueue.global(qos: .userInitiated)) { promises in
            var isSuccess = false
            let promiseCount = promises.count
            var errorCount = 0
            promises.forEach {
                let _ = $0.done(on: DispatchQueue.global(qos: .userInitiated)) { _ in
                    guard !isSuccess else { return } // Succeed as soon as the first promise succeeds
                    isSuccess = true
                    if case .contact(_) = destination, message is VisibleMessage, !isSelfSend {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .messageSent, object: NSNumber(value: message.sentTimestamp!))
                        }
                    }
                    storage.write(with: { transaction in
                        MessageSender.handleSuccessfulMessageSend(message, to: destination, using: transaction)
                        var shouldNotify = (message is VisibleMessage)
                        if let closedGroupUpdate = message as? ClosedGroupUpdate, case .new = closedGroupUpdate.kind {
                            shouldNotify = true
                        }
                        if shouldNotify {
                            let notifyPNServerJob = NotifyPNServerJob(message: snodeMessage)
                            if isMainAppAndActive {
                                JobQueue.shared.add(notifyPNServerJob, using: transaction)
                                seal.fulfill(())
                            } else {
                                notifyPNServerJob.execute().done(on: DispatchQueue.global(qos: .userInitiated)) {
                                    seal.fulfill(())
                                }.catch(on: DispatchQueue.global(qos: .userInitiated)) { _ in
                                    seal.fulfill(()) // Always fulfill because the notify PN server job isn't critical.
                                }
                            }
                        } else {
                            seal.fulfill(())
                        }
                    }, completion: { })
                }
                $0.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                    errorCount += 1
                    guard errorCount == promiseCount else { return } // Only error out if all promises failed
                    storage.write(with: { transaction in
                        handleFailure(with: error, using: transaction as! YapDatabaseReadWriteTransaction)
                    }, completion: { })
                }
            }
        }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
            SNLog("Couldn't send message due to error: \(error).")
            storage.write(with: { transaction in
                handleFailure(with: error, using: transaction as! YapDatabaseReadWriteTransaction)
            }, completion: { })
        }
        // Return
        return promise
    }

    // MARK: Open Groups
    internal static func sendToOpenGroupDestination(_ destination: Message.Destination, message: Message, using transaction: Any) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let storage = SNMessagingKitConfiguration.shared.storage
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Set the timestamp, sender and recipient
        if message.sentTimestamp == nil { // Visible messages will already have their sent timestamp set
            message.sentTimestamp = NSDate.millisecondTimestamp()
        }
        message.sender = storage.getUserPublicKey()
        switch destination {
        case .contact(_): preconditionFailure()
        case .closedGroup(_): preconditionFailure()
        case .openGroup(let channel, let server): message.recipient = "\(server).\(channel)"
        }
        // Set the failure handler (need it here already for precondition failure handling)
        func handleFailure(with error: Swift.Error, using transaction: YapDatabaseReadWriteTransaction) {
            MessageSender.handleFailedMessageSend(message, with: error, using: transaction)
            seal.reject(error)
        }
        // Validate the message
        guard let message = message as? VisibleMessage else {
            #if DEBUG
            preconditionFailure()
            #else
            handleFailure(with: Error.invalidMessage, using: transaction)
            return promise
            #endif
        }
        guard message.isValid else { handleFailure(with: Error.invalidMessage, using: transaction); return promise }
        // The back-end doesn't accept messages without a body so we use this as a workaround
        if message.text?.isEmpty != false {
            message.text = String(message.sentTimestamp!)
        }
        // Convert the message to an open group message
        let (channel, server) = { () -> (UInt64, String) in
            switch destination {
            case .openGroup(let channel, let server): return (channel, server)
            default: preconditionFailure()
            }
        }()
        guard let openGroupMessage = OpenGroupMessage.from(message, for: server, using: transaction) else { handleFailure(with: Error.invalidMessage, using: transaction); return promise }
        // Send the result
        OpenGroupAPI.sendMessage(openGroupMessage, to: channel, on: server).done(on: DispatchQueue.global(qos: .userInitiated)) { openGroupMessage in
            message.openGroupServerMessageID = openGroupMessage.serverID
            storage.write(with: { transaction in
                MessageSender.handleSuccessfulMessageSend(message, to: destination, using: transaction)
                seal.fulfill(())
            }, completion: { })
        }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
            storage.write(with: { transaction in
                handleFailure(with: error, using: transaction as! YapDatabaseReadWriteTransaction)
            }, completion: { })
        }
        // Return
        return promise
    }

    // MARK: Success & Failure Handling
    public static func handleSuccessfulMessageSend(_ message: Message, to destination: Message.Destination, using transaction: Any) {
        Storage.shared.addReceivedMessageTimestamp(message.sentTimestamp!, using: transaction) // To later ignore self-sends in a multi device context
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else { return }
        tsMessage.openGroupServerMessageID = message.openGroupServerMessageID ?? 0
        var recipients = [ message.recipient! ]
        if case .closedGroup(_) = destination, let threadID = message.threadID, // threadID should always be set at this point
            let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction as! YapDatabaseReadTransaction), thread.isClosedGroup {
            recipients = thread.groupModel.groupMemberIds
        }
        recipients.forEach { recipient in
            tsMessage.update(withSentRecipient: recipient, wasSentByUD: true, transaction: transaction as! YapDatabaseReadWriteTransaction)
        }
        OWSDisappearingMessagesJob.shared().startAnyExpiration(for: tsMessage, expirationStartedAt: NSDate.millisecondTimestamp(), transaction: transaction as! YapDatabaseReadWriteTransaction)
        // Sync the message if:
        // • it wasn't a self-send
        // • it was a visible message
        let userPublicKey = getUserHexEncodedPublicKey()
        if case .contact(let publicKey) = destination, publicKey != userPublicKey, let message = message as? VisibleMessage {
            message.syncTarget = publicKey
            // FIXME: Make this a job
            sendToSnodeDestination(.contact(publicKey: userPublicKey), message: message, using: transaction, isSyncMessage: true).retainUntilComplete()
        }
    }

    public static func handleFailedMessageSend(_ message: Message, with error: Swift.Error, using transaction: Any) {
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else { return }
        tsMessage.update(sendingError: error, transaction: transaction as! YapDatabaseReadWriteTransaction)
    }
}
