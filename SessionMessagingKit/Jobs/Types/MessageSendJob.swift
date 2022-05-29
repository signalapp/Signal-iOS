// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SignalCoreKit
import SessionUtilitiesKit
import SessionSnodeKit

public enum MessageSendJob: JobExecutor {
    public static var maxFailureCount: Int = 10
    public static var requiresThreadId: Bool = true
    public static let requiresInteractionId: Bool = false   // Some messages don't have interactions
    
    public static func run(
        _ job: Job,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        guard
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData)
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        if details.message is VisibleMessage {
            guard
                let jobId: Int64 = job.id,
                let interactionId: Int64 = job.interactionId
            else {
                failure(job, JobRunnerError.missingRequiredDetails, false)
                return
            }
            
            // Check if there are any attachments associated to this message, and if so
            // upload them now
            //
            // Note: Normal attachments should be sent in a non-durable way but any
            // attachments for LinkPreviews and Quotes will be processed through this mechanism
            let attachmentState: (shouldFail: Bool, shouldDefer: Bool)? = GRDBStorage.shared.write { db in
                let allAttachmentStateInfo: [Attachment.StateInfo] = try Attachment
                    .stateInfo(interactionId: interactionId)
                    .fetchAll(db)
                
                // If there were failed attachments then this job should fail (can't send a
                // message which has associated attachments if the attachments fail to upload)
                guard !allAttachmentStateInfo.contains(where: { $0.state == .failedDownload }) else {
                    return (true, false)
                }
                
                // Create jobs for any pending (or failed) attachment jobs and insert them into the
                // queue before the current job (this will mean the current job will re-run
                // after these inserted jobs complete)
                //
                // Note: If there are any 'downloaded' attachments then they also need to be
                // uploaded (as a 'downloaded' attachment will be on the current users device
                // but not on the message recipients device - both LinkPreview and Quote can
                // have this case)
                try allAttachmentStateInfo
                    .filter { $0.state == .uploading || $0.state == .failedUpload || $0.state == .downloaded }
                    .filter { stateInfo in
                        // Don't add a new job if there is one already in the queue
                        !JobRunner.hasPendingOrRunningJob(
                            with: .attachmentUpload,
                            details: AttachmentUploadJob.Details(
                                messageSendJobId: jobId,
                                attachmentId: stateInfo.attachmentId
                            )
                        )
                    }
                    .compactMap { stateInfo in
                        JobRunner
                            .insert(
                                db,
                                job: Job(
                                    variant: .attachmentUpload,
                                    behaviour: .runOnce,
                                    threadId: job.threadId,
                                    interactionId: interactionId,
                                    details: AttachmentUploadJob.Details(
                                        messageSendJobId: jobId,
                                        attachmentId: stateInfo.attachmentId
                                    )
                                ),
                                before: job
                            )?
                            .id
                    }
                    .forEach { otherJobId in
                        // Create the dependency between the jobs
                        try JobDependencies(
                            jobId: jobId,
                            dependantId: otherJobId
                        )
                        .insert(db)
                    }
                
                // If there were pending or uploading attachments then stop here (we want to
                // upload them first and then re-run this send job - the 'JobRunner.insert'
                // method will take care of this)
                return (
                    false,
                    allAttachmentStateInfo.contains(where: { $0.state != .uploaded })
                )
            }
            
            // Don't send messages with failed attachment uploads
            //
            // Note: If we have gotten to this point then any dependant attachment upload
            // jobs will have permanently failed so this message send should also do so
            guard attachmentState?.shouldFail == false else {
                failure(job, AttachmentError.notUploaded, true)
                return
            }

            // Defer the job if we found incomplete uploads
            guard attachmentState?.shouldDefer == false else {
                deferred(job)
                return
            }
        }
        
        // Add the threadId to the message if there isn't one set
        details.message.threadId = (details.message.threadId ?? job.threadId)
        
        // Perform the actual message sending
        GRDBStorage.shared.write { db -> Promise<Void> in
            try MessageSender.sendImmediate(
                db,
                message: details.message,
                to: details.destination,
                interactionId: job.interactionId
            )
        }
        .done2 { _ in success(job, false) }
        .catch2 { error in
            SNLog("Couldn't send message due to error: \(error).")
            
            switch error {
                case let senderError as MessageSenderError where !senderError.isRetryable:
                    failure(job, error, true)
                    
                case OnionRequestAPI.Error.httpRequestFailedAtDestination(let statusCode, _, _) where statusCode == 429: // Rate limited
                    failure(job, error, true)
                    
                default:
                    SNLog("Failed to send \(type(of: details.message)).")
                    
                    if details.message is VisibleMessage {
                        guard
                            let interactionId: Int64 = job.interactionId,
                            GRDBStorage.shared.read({ db in try Interaction.exists(db, id: interactionId) }) == true
                        else {
                            // The message has been deleted so permanently fail the job
                            failure(job, error, true)
                            return
                        }
                    }
                    
                    failure(job, error, false)
            }
        }
    }
}

// MARK: - MessageSendJob.Details

extension MessageSendJob {
    public struct Details: Codable {
        // Note: This approach is less than ideal (since it needs to be manually maintained) but
        // I couldn't think of an easy way to support a generic decoded type for the 'message'
        // value in the database while using Codable
        private static let supportedMessageTypes: [String: Message.Type] = [
            "VisibleMessage": VisibleMessage.self,
            
            "ReadReceipt": ReadReceipt.self,
            "TypingIndicator": TypingIndicator.self,
            "ClosedGroupControlMessage": ClosedGroupControlMessage.self,
            "DataExtractionNotification": DataExtractionNotification.self,
            "ExpirationTimerUpdate": ExpirationTimerUpdate.self,
            "ConfigurationMessage": ConfigurationMessage.self,
            "UnsendRequest": UnsendRequest.self,
            "MessageRequestResponse": MessageRequestResponse.self
        ]
        
        private enum CodingKeys: String, CodingKey {
            case interactionId
            case destination
            case messageType
            case message
        }
        
        public let destination: Message.Destination
        public let message: Message
        
        // MARK: - Initialization
        
        public init(
            destination: Message.Destination,
            message: Message
        ) {
            self.destination = destination
            self.message = message
        }
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            guard let messageType: String = try? container.decode(String.self, forKey: .messageType) else {
                Logger.error("Unable to decode messageSend job due to missing messageType")
                throw GRDBStorageError.decodingFailed
            }
            
            /// Note: This **MUST** be a `Codable.Type` rather than a `Message.Type` otherwise the decoding will result
            /// in a `Message` object being returned rather than the desired subclass
            guard let MessageType: Codable.Type = MessageSendJob.Details.supportedMessageTypes[messageType] else {
                Logger.error("Unable to decode messageSend job due to unsupported messageType")
                throw GRDBStorageError.decodingFailed
            }
            guard let message: Message = try MessageType.decoded(with: container, forKey: .message) as? Message else {
                Logger.error("Unable to decode messageSend job due to message conversion issue")
                throw GRDBStorageError.decodingFailed
            }

            self = Details(
                destination: try container.decode(Message.Destination.self, forKey: .destination),
                message: message
            )
        }
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            let messageType: Codable.Type = type(of: message)
            let maybeMessageTypeString: String? = MessageSendJob.Details.supportedMessageTypes
                .first(where: { _, type in messageType == type })?
                .key
            
            guard let messageTypeString: String = maybeMessageTypeString else {
                Logger.error("Unable to encode messageSend job due to unsupported messageType")
                throw GRDBStorageError.objectNotFound
            }

            try container.encode(destination, forKey: .destination)
            try container.encode(messageTypeString, forKey: .messageType)
            try container.encode(message, forKey: .message)
        }
    }
}
