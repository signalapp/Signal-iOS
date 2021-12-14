import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

@objc(SNMessageSender)
public final class MessageSender : NSObject {

    // MARK: Error
    public enum Error : LocalizedError {
        case invalidMessage
        case protoConversionFailed
        case noUserX25519KeyPair
        case noUserED25519KeyPair
        case signingFailed
        case encryptionFailed
        case noUsername
        // Closed groups
        case noThread
        case noKeyPair
        case invalidClosedGroupUpdate

        internal var isRetryable: Bool {
            switch self {
            case .invalidMessage, .protoConversionFailed, .invalidClosedGroupUpdate, .signingFailed, .encryptionFailed: return false
            default: return true
            }
        }
        
        public var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .noUserX25519KeyPair: return "Couldn't find user X25519 key pair."
            case .noUserED25519KeyPair: return "Couldn't find user ED25519 key pair."
            case .signingFailed: return "Couldn't sign message."
            case .encryptionFailed: return "Couldn't encrypt message."
            case .noUsername: return "Missing username."
            // Closed groups
            case .noThread: return "Couldn't find a thread associated with the given group public key."
            case .noKeyPair: return "Couldn't find a private key associated with the given group public key."
            case .invalidClosedGroupUpdate: return "Invalid group update."
            }
        }
    }

    // MARK: Initialization
    private override init() { }

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
        case .openGroup(_, _), .openGroupV2(_, _): return sendToOpenGroupDestination(destination, message: message, using: transaction)
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
        case .openGroup(_, _), .openGroupV2(_, _): preconditionFailure()
        }
        let isSelfSend = (message.recipient == userPublicKey)
        // Set the failure handler (need it here already for precondition failure handling)
        func handleFailure(with error: Swift.Error, using transaction: YapDatabaseReadWriteTransaction) {
            MessageSender.handleFailedMessageSend(message, with: error, using: transaction)
            seal.reject(error)
        }
        // Validate the message
        guard message.isValid else { handleFailure(with: Error.invalidMessage, using: transaction); return promise }
        // Stop here if this is a self-send, unless it's:
        // • a configuration message
        // • a sync message
        // • a closed group control message of type `new`
        // • an unsend request
        let isNewClosedGroupControlMessage = given(message as? ClosedGroupControlMessage) { if case .new = $0.kind { return true } else { return false } } ?? false
        guard !isSelfSend || message is ConfigurationMessage || isSyncMessage || isNewClosedGroupControlMessage || message is UnsendRequest else {
            storage.write(with: { transaction in
                MessageSender.handleSuccessfulMessageSend(message, to: destination, using: transaction)
                seal.fulfill(())
            }, completion: { })
            return promise
        }
        // Attach the user's profile if needed
        if let message = message as? VisibleMessage {
            guard let name = storage.getUser()?.name else { handleFailure(with: Error.noUsername, using: transaction); return promise }
            if let profileKey = storage.getUser()?.profileEncryptionKey?.keyData, let profilePictureURL = storage.getUser()?.profilePictureURL {
                message.profile = VisibleMessage.Profile(displayName: name, profileKey: profileKey, profilePictureURL: profilePictureURL)
            } else {
                message.profile = VisibleMessage.Profile(displayName: name)
            }
        }
        // Convert it to protobuf
        guard let proto = message.toProto(using: transaction) else { handleFailure(with: Error.protoConversionFailed, using: transaction); return promise }
        // Serialize the protobuf
        let plaintext: Data
        do {
            plaintext = (try proto.serializedData() as NSData).paddedMessageBody()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            handleFailure(with: error, using: transaction)
            return promise
        }
        // Encrypt the serialized protobuf
        let ciphertext: Data
        do {
            switch destination {
            case .contact(let publicKey): ciphertext = try encryptWithSessionProtocol(plaintext, for: publicKey)
            case .closedGroup(let groupPublicKey):
                guard let encryptionKeyPair = Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else { throw Error.noKeyPair }
                ciphertext = try encryptWithSessionProtocol(plaintext, for: encryptionKeyPair.hexEncodedPublicKey)
            case .openGroup(_, _), .openGroupV2(_, _): preconditionFailure()
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
            kind = .sessionMessage
            senderPublicKey = ""
        case .closedGroup(let groupPublicKey):
            kind = .closedGroupMessage
            senderPublicKey = groupPublicKey
        case .openGroup(_, _), .openGroupV2(_, _): preconditionFailure()
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
        // Send the result
        let base64EncodedData = wrappedMessage.base64EncodedString()
        let timestamp = UInt64(Int64(message.sentTimestamp!) + SnodeAPI.clockOffset)
        let snodeMessage = SnodeMessage(recipient: message.recipient!, data: base64EncodedData, ttl: message.ttl, timestamp: timestamp)
        SnodeAPI.sendMessage(snodeMessage).done(on: DispatchQueue.global(qos: .userInitiated)) { promises in
            var isSuccess = false
            let promiseCount = promises.count
            var errorCount = 0
            promises.forEach {
                let _ = $0.done(on: DispatchQueue.global(qos: .userInitiated)) { rawResponse in
                    guard !isSuccess else { return } // Succeed as soon as the first promise succeeds
                    isSuccess = true
                    storage.write(with: { transaction in
                        let json = rawResponse as? JSON
                        let hash = json?["hash"] as? String
                        message.serverHash = hash
                        MessageSender.handleSuccessfulMessageSend(message, to: destination, isSyncMessage: isSyncMessage, using: transaction)
                        var shouldNotify = ((message is VisibleMessage || message is UnsendRequest) && !isSyncMessage)
                        /*
                        if let closedGroupControlMessage = message as? ClosedGroupControlMessage, case .new = closedGroupControlMessage.kind {
                            shouldNotify = true
                        }
                         */
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
        case .openGroupV2(let room, let server): message.recipient = "\(server).\(room)"
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
        // Attach the user's profile
        guard let name = storage.getUser()?.name else { handleFailure(with: Error.noUsername, using: transaction); return promise }
        if let profileKey = storage.getUser()?.profileEncryptionKey?.keyData, let profilePictureURL = storage.getUser()?.profilePictureURL {
            message.profile = VisibleMessage.Profile(displayName: name, profileKey: profileKey, profilePictureURL: profilePictureURL)
        } else {
            message.profile = VisibleMessage.Profile(displayName: name)
        }
        // Convert it to protobuf
        guard let proto = message.toProto(using: transaction) else { handleFailure(with: Error.protoConversionFailed, using: transaction); return promise }
        // Serialize the protobuf
        let plaintext: Data
        do {
            plaintext = (try proto.serializedData() as NSData).paddedMessageBody()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            handleFailure(with: error, using: transaction)
            return promise
        }
        // Send the result
        guard case .openGroupV2(let room, let server) = destination else { preconditionFailure() }
        let openGroupMessage = OpenGroupMessageV2(serverID: nil, sender: nil, sentTimestamp: message.sentTimestamp!,
            base64EncodedData: plaintext.base64EncodedString(), base64EncodedSignature: nil)
        OpenGroupAPIV2.send(openGroupMessage, to: room, on: server).done(on: DispatchQueue.global(qos: .userInitiated)) { openGroupMessage in
            message.openGroupServerMessageID = given(openGroupMessage.serverID) { UInt64($0) }
            storage.write(with: { transaction in
                MessageSender.handleSuccessfulMessageSend(message, to: destination, serverTimestamp: openGroupMessage.sentTimestamp, using: transaction)
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
    public static func handleSuccessfulMessageSend(_ message: Message, to destination: Message.Destination, serverTimestamp: UInt64? = nil, isSyncMessage: Bool = false, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        // Get the visible message if possible
        if let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) {
            // When the sync message is successfully sent, the hash value of this TSOutgoingMessage
            // will be replaced by the hash value of the sync message. Since the hash value of the
            // real message has no use when we delete a message. It is OK to let it be.
            tsMessage.serverHash = message.serverHash
            // Track the open group server message ID and update server timestamp
            if let openGroupServerMessageID = message.openGroupServerMessageID, let timestamp = serverTimestamp {
                // Use server timestamp for open group messages
                // Otherwise the quote messages may not be able
                // to be found by the timestamp on other devices
                tsMessage.updateOpenGroupServerID(openGroupServerMessageID, serverTimeStamp: timestamp)
            }
            // Mark the message as sent
            var recipients = [ message.recipient! ]
            if case .closedGroup(_) = destination, let threadID = message.threadID, // threadID should always be set at this point
                let thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction), thread.isClosedGroup {
                recipients = thread.groupModel.groupMemberIds
            }
            recipients.forEach { recipient in
                tsMessage.update(withSentRecipient: recipient, wasSentByUD: true, transaction: transaction)
            }
            tsMessage.save(with: transaction)
            NotificationCenter.default.post(name: .messageSentStatusDidChange, object: nil, userInfo: nil)
            // Start the disappearing messages timer if needed
            OWSDisappearingMessagesJob.shared().startAnyExpiration(for: tsMessage, expirationStartedAt: NSDate.millisecondTimestamp(), transaction: transaction)
        }
        // Prevent the same ExpirationTimerUpdate to be handled twice
        if let message = message as? ExpirationTimerUpdate {
            Storage.shared.addReceivedMessageTimestamp(message.sentTimestamp!, using: transaction)
        }
        // Sync the message if:
        // • it's a visible message or an expiration timer update
        // • the destination was a contact
        // • we didn't sync it already
        let userPublicKey = getUserHexEncodedPublicKey()
        if case .contact(let publicKey) = destination, !isSyncMessage {
            if let message = message as? VisibleMessage { message.syncTarget = publicKey }
            if let message = message as? ExpirationTimerUpdate { message.syncTarget = publicKey }
            // FIXME: Make this a job
            sendToSnodeDestination(.contact(publicKey: userPublicKey), message: message, using: transaction, isSyncMessage: true).retainUntilComplete()
        }
    }

    public static func handleFailedMessageSend(_ message: Message, with error: Swift.Error, using transaction: Any) {
        guard let tsMessage = TSOutgoingMessage.find(withTimestamp: message.sentTimestamp!) else { return }
        // Remove the message timestamps if it fails
        Storage.shared.removeReceivedMessageTimestamps([message.sentTimestamp!], using: transaction)
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        tsMessage.update(sendingError: error, transaction: transaction)
        MessageInvalidator.invalidate(tsMessage, with: transaction)
    }
}
