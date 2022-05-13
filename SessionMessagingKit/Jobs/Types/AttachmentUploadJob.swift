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
        success: @escaping (Job, Bool) -> (),
        failure: @escaping (Job, Error?, Bool) -> (),
        deferred: @escaping (Job) -> ()
    ) {
        guard
            let threadId: String = job.threadId,
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder().decode(Details.self, from: detailsData),
            let (attachment, openGroup): (Attachment, OpenGroup?) = GRDBStorage.shared.read({ db in
                guard let attachment: Attachment = try Attachment.fetchOne(db, id: details.attachmentId) else {
                    return nil
                }
                
                return (attachment, try OpenGroup.fetchOne(db, id: threadId))
            })
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        attachment.upload(
            using: { data in
                if let openGroup: OpenGroup = openGroup {
                    return OpenGroupAPIV2.upload(data, to: openGroup.room, on: openGroup.server)
                }
                
                return FileServerAPIV2.upload(data)
            },
            encrypt: (openGroup == nil),
            success: { success(job, false) },
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
