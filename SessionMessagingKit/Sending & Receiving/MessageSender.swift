// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

@objc(SNMessageSender)
public final class MessageSender : NSObject {
    // MARK: Initialization
    private override init() { }

    // MARK: - Preparation
    
    public static func prep(
        _ db: Database,
        signalAttachments: [SignalAttachment],
        for message: VisibleMessage
    ) {
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
            attachment.attachmentType = $0.isVoiceMessage ? .voiceMessage : .default
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

    // MARK: - Convenience
    
    public static func send(_ db: Database, message: Message, to destination: Message.Destination, interactionId: Int64?) throws -> Promise<Void> {
        switch destination {
            case .contact(_), .closedGroup(_):
                return try sendToSnodeDestination(db, message: message, to: destination, interactionId: interactionId)

            case .openGroup(_, _), .openGroupV2(_, _):
                return sendToOpenGroupDestination(db, message: message, to: destination, interactionId: interactionId)
        }
    }

    // MARK: One-on-One Chats & Closed Groups
    
    internal static func sendToSnodeDestination(
        _ db: Database,
        message: Message,
        to destination: Message.Destination,
        interactionId: Int64?,
        isSyncMessage: Bool = false
    ) throws -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        let isMainAppActive: Bool = (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false)
        
        // Set the timestamp, sender and recipient
        if message.sentTimestamp == nil { // Visible messages will already have their sent timestamp set
            message.sentTimestamp = NSDate.millisecondTimestamp()
        }

        let isSelfSend: Bool = (message.recipient == userPublicKey)
        message.sender = userPublicKey
        message.recipient = {
            switch destination {
                case .contact(let publicKey): return publicKey
                case .closedGroup(let groupPublicKey): return groupPublicKey
                case .openGroup(_, _), .openGroupV2(_, _): preconditionFailure()
            }
        }()
        
        // Set the failure handler (need it here already for precondition failure handling)
        func handleFailure(_ db: Database, with error: MessageSenderError) {
            MessageSender.handleFailedMessageSend(db, message: message, with: error, interactionId: interactionId)
            seal.reject(error)
        }
        
        // Validate the message
        guard message.isValid else {
            handleFailure(db, with: .invalidMessage)
            return promise
        }
        
        // Stop here if this is a self-send, unless it's:
        // • a configuration message
        // • a sync message
        // • a closed group control message of type `new`
        // • an unsend request
        let isNewClosedGroupControlMessage: Bool = {
            switch (message as? ClosedGroupControlMessage)?.kind {
                case .new: return true
                default: return false
            }
        }()

        guard
            !isSelfSend ||
            message is ConfigurationMessage ||
            isSyncMessage ||
            isNewClosedGroupControlMessage ||
            message is UnsendRequest
        else {
            try MessageSender.handleSuccessfulMessageSend(db, message: message, to: destination, interactionId: interactionId)
            seal.fulfill(())
            return promise
        }
        
        // Attach the user's profile if needed
        if let message: VisibleMessage = message as? VisibleMessage {
            let profile: Profile = Profile.fetchOrCreateCurrentUser(db)
            
            if let profileKey: Data = profile.profileEncryptionKey?.keyData, let profilePictureUrl: String = profile.profilePictureUrl {
                message.profile = VisibleMessage.Profile(
                    displayName: profile.name,
                    profileKey: profileKey,
                    profilePictureUrl: profilePictureUrl
                )
            }
            else {
                message.profile = VisibleMessage.Profile(displayName: profile.name)
            }
        }
        
        // Convert it to protobuf
        guard let proto = message.toProto(db) else {
            handleFailure(db, with: .protoConversionFailed)
            return promise
        }
        
        // Serialize the protobuf
        let plaintext: Data
        do {
            plaintext = (try proto.serializedData() as NSData).paddedMessageBody()
        }
        catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            handleFailure(db, with: .other(error))
            return promise
        }
        
        // Encrypt the serialized protobuf
        let ciphertext: Data
        do {
            switch destination {
                case .contact(let publicKey):
                    ciphertext = try encryptWithSessionProtocol(plaintext, for: publicKey)
                    
                case .closedGroup(let groupPublicKey):
                    guard let encryptionKeyPair: ClosedGroupKeyPair = try? ClosedGroupKeyPair.fetchLatestKeyPair(db, threadId: groupPublicKey) else {
                        throw MessageSenderError.noKeyPair
                    }
                    
                    ciphertext = try encryptWithSessionProtocol(
                        plaintext,
                        for: "05\(encryptionKeyPair.publicKey.toHexString())"
                    )
                    
                case .openGroup(_, _), .openGroupV2(_, _): preconditionFailure()
            }
        }
        catch {
            SNLog("Couldn't encrypt message for destination: \(destination) due to error: \(error).")
            handleFailure(db, with: .other(error))
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
        }
        catch {
            SNLog("Couldn't wrap message due to error: \(error).")
            handleFailure(db, with: .other(error))
            return promise
        }
        
        // Send the result
        let base64EncodedData = wrappedMessage.base64EncodedString()
        let timestamp = UInt64(Int64(message.sentTimestamp!) + SnodeAPI.clockOffset)
        let snodeMessage = SnodeMessage(
            recipient: message.recipient!,
            data: base64EncodedData,
            ttl: message.ttl,
            timestampMs: timestamp
        )
        
        SnodeAPI.sendMessage(snodeMessage)
            .done(on: DispatchQueue.global(qos: .userInitiated)) { promises in
                let promiseCount = promises.count
                var isSuccess = false
                var errorCount = 0
                
                promises.forEach {
                    let _ = $0.done(on: DispatchQueue.global(qos: .userInitiated)) { rawResponse in
                        guard !isSuccess else { return } // Succeed as soon as the first promise succeeds
                        isSuccess = true
                        
                        GRDBStorage.shared.write { db in
                            let json = rawResponse as? JSON
                            let hash = json?["hash"] as? String
                            message.serverHash = hash
                            
                            try MessageSender.handleSuccessfulMessageSend(
                                db,
                                message: message,
                                to: destination,
                                interactionId: interactionId,
                                isSyncMessage: isSyncMessage
                            )
                            
                            let shouldNotify = (
                                (message is VisibleMessage || message is UnsendRequest) &&
                                !isSyncMessage
                            )
                            
                            /*
                            if let closedGroupControlMessage = message as? ClosedGroupControlMessage, case .new = closedGroupControlMessage.kind {
                                shouldNotify = true
                            }
                             */
                            guard shouldNotify else {
                                seal.fulfill(())
                                return
                            }
                            
                            let job: Job? = Job(
                                variant: .notifyPushServer,
                                behaviour: .runOnce,
                                details: NotifyPushServerJob.Details(message: snodeMessage)
                            )
                            
                            if isMainAppActive {
                                JobRunner.add(db, job: job)
                                seal.fulfill(())
                            }
                            else if let job: Job = job {
                                NotifyPushServerJob.run(
                                    job,
                                    success: { _, _ in seal.fulfill(()) },
                                    failure: { _, _, _ in
                                        // Always fulfill because the notify PN server job isn't critical.
                                        seal.fulfill(())
                                    },
                                    deferred: { _ in
                                        // Always fulfill because the notify PN server job isn't critical.
                                        seal.fulfill(())
                                    }
                                )
                            }
                            else {
                                // Always fulfill because the notify PN server job isn't critical.
                                seal.fulfill(())
                            }
                        }
                    }
                    $0.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                        errorCount += 1
                        guard errorCount == promiseCount else { return } // Only error out if all promises failed
                        
                        GRDBStorage.shared.write { db in
                            handleFailure(db, with: .other(error))
                        }
                    }
                }
            }
            .catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                SNLog("Couldn't send message due to error: \(error).")
                
                GRDBStorage.shared.write { db in
                    handleFailure(db, with: .other(error))
                }
            }
        
        return promise
    }

    // MARK: Open Groups
    
    internal static func sendToOpenGroupDestination(
        _ db: Database,
        message: Message,
        to destination: Message.Destination,
        interactionId: Int64?
    ) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        
        // Set the timestamp, sender and recipient
        if message.sentTimestamp == nil { // Visible messages will already have their sent timestamp set
            message.sentTimestamp = NSDate.millisecondTimestamp()
        }
        message.sender = getUserHexEncodedPublicKey()
        
        switch destination {
            case .contact(_): preconditionFailure()
            case .closedGroup(_): preconditionFailure()
            case .openGroup(let channel, let server): message.recipient = "\(server).\(channel)"
            case .openGroupV2(let room, let server): message.recipient = "\(server).\(room)"
        }
        
        // Set the failure handler (need it here already for precondition failure handling)
        func handleFailure(_ db: Database, with error: MessageSenderError) {
            MessageSender.handleFailedMessageSend(db, message: message, with: error, interactionId: interactionId)
            seal.reject(error)
        }
        // Validate the message
        guard let message = message as? VisibleMessage else {
            #if DEBUG
            preconditionFailure()
            #else
            handleFailure(db, with: MessageSenderError.invalidMessage)
            return promise
            #endif
        }
        guard message.isValid else {
            handleFailure(db, with: .invalidMessage)
            return promise
        }
        
        // Attach the user's profile
        message.profile = VisibleMessage.Profile(
            profile: Profile.fetchOrCreateCurrentUser()
        )

        if (message.profile?.displayName ?? "").isEmpty {
            handleFailure(db, with: .noUsername)
            return promise
        }
        
        // Convert it to protobuf
        guard let proto = message.toProto(db) else {
            handleFailure(db, with: .protoConversionFailed)
            return promise
        }
        
        // Serialize the protobuf
        let plaintext: Data
        do {
            plaintext = (try proto.serializedData() as NSData).paddedMessageBody()
        }
        catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            handleFailure(db, with: .other(error))
            return promise
        }
        
        // Send the result
        guard case .openGroupV2(let room, let server) = destination else { preconditionFailure() }
        
        let openGroupMessage = OpenGroupMessageV2(
            serverID: nil,
            sender: nil,
            sentTimestamp: message.sentTimestamp!,
            base64EncodedData: plaintext.base64EncodedString(),
            base64EncodedSignature: nil
        )
        
        OpenGroupAPIV2
            .send(
                openGroupMessage,
                to: room,
                on: server
            )
            .done(on: DispatchQueue.global(qos: .userInitiated)) { openGroupMessage in
                message.openGroupServerMessageId = given(openGroupMessage.serverID) { UInt64($0) }

                GRDBStorage.shared.write { db in
                    try MessageSender.handleSuccessfulMessageSend(
                        db,
                        message: message,
                        to: destination,
                        interactionId: interactionId,
                        serverTimestampMs: openGroupMessage.sentTimestamp
                    )
                    seal.fulfill(())
                }
            }
            .catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                GRDBStorage.shared.write { db in
                    handleFailure(db, with: .other(error))
                }
            }
        
        return promise
    }

    // MARK: Success & Failure Handling
    
    private static func handleSuccessfulMessageSend(
        _ db: Database,
        message: Message,
        to destination: Message.Destination,
        interactionId: Int64?,
        serverTimestampMs: UInt64? = nil,
        isSyncMessage: Bool = false
    ) throws {
        let interaction: Interaction? = try interaction(db, for: message, interactionId: interactionId)
        
        // Get the visible message if possible
        if let interaction: Interaction = interaction {
            // When the sync message is successfully sent, the hash value of this TSOutgoingMessage
            // will be replaced by the hash value of the sync message. Since the hash value of the
            // real message has no use when we delete a message. It is OK to let it be.
            try interaction.with(
                serverHash: message.serverHash,
                
                // Track the open group server message ID and update server timestamp (use server
                // timestamp for open group messages otherwise the quote messages may not be able
                // to be found by the timestamp on other devices
                timestampMs: (message.openGroupServerMessageId == nil ?
                    nil :
                    serverTimestampMs.map { Int64($0) }
                ),
                openGroupServerMessageId: message.openGroupServerMessageId.map { Int64($0) }
            ).update(db)
            
            // Mark the message as sent
            try interaction.recipientStates
                .fetchAll(db)
                .map { $0.with(state: .sent) }
                .saveAll(db)
            
            NotificationCenter.default.post(name: .messageSentStatusDidChange, object: nil, userInfo: nil)
            
            // Start the disappearing messages timer if needed
            JobRunner.upsert(
                db,
                job: DisappearingMessagesJob.updateNextRunIfNeeded(
                    db,
                    interaction: interaction,
                    startedAtMs: (Date().timeIntervalSince1970 * 1000)
                )
            )
        }
        
        // Prevent the same ExpirationTimerUpdate to be handled twice
        if message is ControlMessage {
            try? ControlMessageProcessRecord(
                threadId: {
                    switch destination {
                        case .contact(let publicKey): return publicKey
                        case .closedGroup(let groupPublicKey): return groupPublicKey
                        case .openGroupV2(let room, let server):
                            return OpenGroup.idFor(room: room, server: server)
                            
                        // FIXME: Remove support for V1 SOGS
                        case .openGroup: return getUserHexEncodedPublicKey(db)
                    }
                }(),
                sentTimestampMs: {
                    if message.openGroupServerMessageId != nil {
                        return (serverTimestampMs.map { Int64($0) } ?? 0)
                    }
                    
                    return (message.sentTimestamp.map { Int64($0) } ?? 0)
                }(),
                serverHash: (message.serverHash ?? ""),
                openGroupMessageServerId: (message.openGroupServerMessageId.map { Int64($0) } ?? 0)
            ).insert(db)
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
            try sendToSnodeDestination(
                db,
                message: message,
                to: .contact(publicKey: userPublicKey),
                interactionId: interactionId,
                isSyncMessage: true
            ).retainUntilComplete()
        }
    }

    public static func handleFailedMessageSend(
        _ db: Database,
        message: Message,
        with error: MessageSenderError,
        interactionId: Int64?
    ) {
        guard let interaction: Interaction = try? interaction(db, for: message, interactionId: interactionId) else {
            return
        }
        
        // Mark any "sending" recipients as "failed"
        try? interaction.recipientStates
            .fetchAll(db)
            .forEach { oldState in
                guard oldState.state == .sending else { return }
                
                try? oldState.with(
                    state: .failed,
                    mostRecentFailureText: error.localizedDescription
                ).save(db)
            }
        
        // Remove the message timestamps if it fails
    }
    
    // MARK: - Convenience
    
    private static func interaction(_ db: Database, for message: Message, interactionId: Int64?) throws -> Interaction? {
        if let interactionId: Int64 = interactionId {
            return try Interaction.fetchOne(db, id: interactionId)
        }
        else if let sentTimestamp: Double = message.sentTimestamp.map({ Double($0) }) {
            // If we have a threadId then include that in the filter to make the request smaller
            if
                let threadId: String = message.threadId,
                !threadId.isEmpty,
                let thread: SessionThread = try? SessionThread.fetchOne(db, id: threadId)
            {
                return try thread.interactions
                    .filter(Interaction.Columns.timestampMs == sentTimestamp)
                    .fetchOne(db)
            }
            
            return try Interaction
                .filter(Interaction.Columns.timestampMs == sentTimestamp)
                .fetchOne(db)
        }
        
        return nil
    }
}
