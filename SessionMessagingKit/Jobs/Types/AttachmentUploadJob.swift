// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SignalCoreKit
import SessionUtilitiesKit

public enum AttachmentUploadJob: JobExecutor {
    public static var maxFailureCount: Int = 10
    public static var requiresThreadId: Bool = true
    public static let requiresInteractionId: Bool = true
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        guard
            let threadId: String = job.threadId,
            let interactionId: Int64 = job.interactionId,
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData),
            let (attachment, openGroup): (Attachment, OpenGroup?) = Storage.shared.read({ db in
                guard let attachment: Attachment = try Attachment.fetchOne(db, id: details.attachmentId) else {
                    return nil
                }
                
                return (attachment, try OpenGroup.fetchOne(db, id: threadId))
            })
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        // If the original interaction no longer exists then don't bother uploading the attachment (ie. the
        // message was deleted before it even got sent)
        guard Storage.shared.read({ db in try Interaction.exists(db, id: interactionId) }) == true else {
            failure(job, StorageError.objectNotFound, true)
            return
        }
        
        // If the attachment is still pending download the hold off on running this job
        guard attachment.state != .pendingDownload && attachment.state != .downloading else {
            deferred(job)
            return
        }
        
        // Note: In the AttachmentUploadJob we intentionally don't provide our own db instance to prevent
        // reentrancy issues when the success/failure closures get called before the upload as the JobRunner
        // will attempt to update the state of the job immediately
        attachment.upload(
            queue: queue,
            using: { db, data in
                SNLog("[AttachmentUpload] Started for message \(interactionId) (\(attachment.byteCount) bytes)")
                
                if let openGroup: OpenGroup = openGroup {
                    return OpenGroupAPI
                        .uploadFile(
                            db,
                            bytes: data.bytes,
                            to: openGroup.roomToken,
                            on: openGroup.server
                        )
                        .map { _, response -> String in response.id }
                }
                
                return FileServerAPI.upload(data)
                    .map { response -> String in response.id }
            },
            encrypt: (openGroup == nil),
            success: { _ in success(job, false) },
            failure: { error in failure(job, error, false) }
        )
    }
}

// MARK: - AttachmentUploadJob.Details

extension AttachmentUploadJob {
    public struct Details: Codable {
        /// This is the id for the messageSend job this attachmentUpload job is associated to, the value isn't used for any of
        /// the logic but we want to mandate that the attachmentUpload job can only be used alongside a messageSend job
        ///
        /// **Note:** If we do decide to remove this the `_003_YDBToGRDBMigration` will need to be updated as it
        /// fails if this connection can't be made
        public let messageSendJobId: Int64
        
        /// The id of the `Attachment` to upload
        public let attachmentId: String
        
        public init(messageSendJobId: Int64, attachmentId: String) {
            self.messageSendJobId = messageSendJobId
            self.attachmentId = attachmentId
        }
    }
}
