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
        public let attachmentId: String
        
        public init(attachmentId: String) {
            self.attachmentId = attachmentId
        }
    }
    
    public enum AttachmentUploadError: LocalizedError {
        case noAttachment
        case encryptionFailed

        public var errorDescription: String? {
            switch self {
                case .noAttachment: return "No such attachment."
                case .encryptionFailed: return "Couldn't encrypt file."
            }
        }
    }
}
