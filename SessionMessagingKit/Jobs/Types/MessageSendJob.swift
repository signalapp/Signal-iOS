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
        queue: DispatchQueue,
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
        
        // We need to include 'fileIds' when sending messages with attachments to Open Groups
        // so extract them from any associated attachments
        var messageFileIds: [String] = []
        
        if details.message is VisibleMessage {
            guard
                let jobId: Int64 = job.id,
                let interactionId: Int64 = job.interactionId
            else {
                failure(job, JobRunnerError.missingRequiredDetails, false)
                return
            }
            
            // If the original interaction no longer exists then don't bother sending the message (ie. the
            // message was deleted before it even got sent)
            guard Storage.shared.read({ db in try Interaction.exists(db, id: interactionId) }) == true else {
                failure(job, StorageError.objectNotFound, true)
                return
            }
            
            // Check if there are any attachments associated to this message, and if so
            // upload them now
            //
            // Note: Normal attachments should be sent in a non-durable way but any
            // attachments for LinkPreviews and Quotes will be processed through this mechanism
            let attachmentState: (shouldFail: Bool, shouldDefer: Bool, fileIds: [String])? = Storage.shared.write { db in
                let allAttachmentStateInfo: [Attachment.StateInfo] = try Attachment
                    .stateInfo(interactionId: interactionId)
                    .fetchAll(db)
                let maybeFileIds: [String?] = allAttachmentStateInfo
                    .map { Attachment.fileId(for: $0.downloadUrl) }
                let fileIds: [String] = maybeFileIds.compactMap { $0 }
                
                // If there were failed attachments then this job should fail (can't send a
                // message which has associated attachments if the attachments fail to upload)
                guard !allAttachmentStateInfo.contains(where: { $0.state == .failedDownload }) else {
                    return (true, false, fileIds)
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
                    .filter { attachment -> Bool in
                        // Non-media quotes won't have thumbnails so so don't try to upload them
                        guard attachment.downloadUrl != Attachment.nonMediaQuoteFileId else { return false }
                        
                        switch attachment.state {
                            case .uploading, .pendingDownload, .downloading, .failedUpload, .downloaded:
                                return true
                                
                            default: return false
                        }
                    }
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
                    .compactMap { stateInfo -> (jobId: Int64, job: Job)? in
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
                            )
                    }
                    .forEach { otherJobId, _ in
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
                let isMissingFileIds: Bool = (maybeFileIds.count != fileIds.count)
                let hasPendingUploads: Bool = allAttachmentStateInfo.contains(where: { $0.state != .uploaded })
                
                return (
                    (isMissingFileIds && !hasPendingUploads),
                    hasPendingUploads,
                    fileIds
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
            
            // Store the fileIds so they can be sent with the open group message content
            messageFileIds = (attachmentState?.fileIds ?? [])
        }
        
        // Store the sentTimestamp from the message in case it fails due to a clockOutOfSync error
        let originalSentTimestamp: UInt64? = details.message.sentTimestamp
        
        // Add the threadId to the message if there isn't one set
        details.message.threadId = (details.message.threadId ?? job.threadId)
        
        // Perform the actual message sending
        Storage.shared.writeAsync { db -> Promise<Void> in
            try MessageSender.sendImmediate(
                db,
                message: details.message,
                to: details.destination
                    .with(fileIds: messageFileIds),
                interactionId: job.interactionId
            )
        }
        .done(on: queue) { _ in success(job, false) }
        .catch(on: queue) { error in
            SNLog("Couldn't send message due to error: \(error).")
            
            switch error {
                case let senderError as MessageSenderError where !senderError.isRetryable:
                    failure(job, error, true)
                    
                case OnionRequestAPIError.httpRequestFailedAtDestination(let statusCode, _, _) where statusCode == 429: // Rate limited
                    failure(job, error, true)
                    
                case SnodeAPIError.clockOutOfSync:
                    SNLog("\(originalSentTimestamp != nil ? "Permanently Failing" : "Failing") to send \(type(of: details.message)) due to clock out of sync issue.")
                    failure(job, error, (originalSentTimestamp != nil))
                    
                default:
                    SNLog("Failed to send \(type(of: details.message)).")
                    
                    if details.message is VisibleMessage {
                        guard
                            let interactionId: Int64 = job.interactionId,
                            Storage.shared.read({ db in try Interaction.exists(db, id: interactionId) }) == true
                        else {
                            // The message has been deleted so permanently fail the job
                            failure(job, error, true)
                            return
                        }
                    }
                    
                    failure(job, error, false)
            }
        }
        .retainUntilComplete()
    }
}

// MARK: - MessageSendJob.Details

extension MessageSendJob {
    public struct Details: Codable {
        private enum CodingKeys: String, CodingKey {
            case destination
            case message
            case variant
        }
        
        public let destination: Message.Destination
        public let message: Message
        public let variant: Message.Variant?
        
        // MARK: - Initialization
        
        public init(
            destination: Message.Destination,
            message: Message
        ) {
            self.destination = destination
            self.message = message
            self.variant = Message.Variant(from: message)
        }
        
        // MARK: - Codable
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            guard let variant: Message.Variant = try? container.decode(Message.Variant.self, forKey: .variant) else {
                SNLog("Unable to decode messageSend job due to missing variant")
                throw StorageError.decodingFailed
            }
            
            self = Details(
                destination: try container.decode(Message.Destination.self, forKey: .destination),
                message: try variant.decode(from: container, forKey: .message)
            )
        }
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            guard let variant: Message.Variant = Message.Variant(from: message) else {
                SNLog("Unable to encode messageSend job due to unsupported variant")
                throw StorageError.objectNotFound
            }

            try container.encode(destination, forKey: .destination)
            try container.encode(message, forKey: .message)
            try container.encode(variant, forKey: .variant)
        }
    }
}
