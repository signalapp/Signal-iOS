// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionUtilitiesKit
import SessionSnodeKit
import SignalCoreKit

public enum AttachmentDownloadJob: JobExecutor {
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
            let attachment: Attachment = GRDBStorage.shared
                .read({ db in try Attachment.fetchOne(db, id: details.attachmentId) })
        else {
            failure(job, JobRunnerError.missingRequiredDetails, false)
            return
        }
        
        // Due to the complex nature of jobs and how attachments can be reused it's possible for
        // and AttachmentDownloadJob to get created for an attachment which has already been
        // downloaded/uploaded so in those cases just succeed immediately
        guard attachment.state != .downloaded && attachment.state != .uploaded else {
            success(job, false)
            return
        }
        
        // Update to the 'downloading' state (no need to update the 'attachment' instance)
        GRDBStorage.shared.write { db in
            try Attachment
                .filter(id: attachment.id)
                .updateAll(db, Attachment.Columns.state.set(to: Attachment.State.downloading))
        }
        
        let temporaryFileUrl: URL = URL(
            fileURLWithPath: OWSTemporaryDirectoryAccessibleAfterFirstAuth() + UUID().uuidString
        )
        let downloadPromise: Promise<Data> = {
            guard
                let downloadUrl: String = attachment.downloadUrl,
                let fileAsString: String = downloadUrl.split(separator: "/").last.map({ String($0) }),
                let file: UInt64 = UInt64(fileAsString)
            else {
                return Promise(error: AttachmentDownloadError.invalidUrl)
            }
            
            if let openGroup: OpenGroup = GRDBStorage.shared.read({ db in try OpenGroup.fetchOne(db, id: threadId) }) {
                return OpenGroupAPIV2.download(file, from: openGroup.room, on: openGroup.server)
            }
            
            return FileServerAPIV2.download(file, useOldServer: downloadUrl.contains(FileServerAPIV2.oldServer))
        }()
        
        downloadPromise
            .then { data -> Promise<Void> in
                try data.write(to: temporaryFileUrl, options: .atomic)
                
                let plaintext: Data = try {
                    guard
                        let key: Data = attachment.encryptionKey,
                        let digest: Data = attachment.digest,
                        key.count > 0,
                        digest.count > 0
                    else { return data } // Open group attachments are unencrypted
                        
                    return try Cryptography.decryptAttachment(
                        data,
                        withKey: key,
                        digest: digest,
                        unpaddedSize: UInt32(attachment.byteCount)
                    )
                }()
                
                guard try attachment.write(data: plaintext) else {
                    throw AttachmentDownloadError.failedToSaveFile
                }
                
                return Promise.value(())
            }
            .done {
                // Remove the temporary file
                OWSFileSystem.deleteFile(temporaryFileUrl.path)
                
                /// Update the attachment state
                ///
                /// **Note:** We **MUST** use the `'with()` function here as it will update the
                /// `isValid` and `duration` values based on the downloaded data and the state
                GRDBStorage.shared.write { db in
                    _ = try attachment
                        .with(
                            state: .downloaded,
                            creationTimestamp: Date().timeIntervalSince1970,
                            localRelativeFilePath: attachment.originalFilePath?
                                .substring(from: (Attachment.attachmentsFolder.count + 1))  // Leading forward slash
                        )
                        .saved(db)
                }
                
                success(job, false)
            }
            .catch { error in
                OWSFileSystem.deleteFile(temporaryFileUrl.path)
                
                switch error {
                    case OnionRequestAPI.Error.httpRequestFailedAtDestination(let statusCode, _, _) where statusCode == 400:
                        /// Otherwise, the attachment will show a state of downloading forever, and the message
                        /// won't be able to be marked as read
                        ///
                        /// **Note:** We **MUST** use the `'with()` function here as it will update the
                        /// `isValid` and `duration` values based on the downloaded data and the state
                        GRDBStorage.shared.write { db in
                            _ = try attachment
                                .with(state: .failed)
                                .saved(db)
                        }
                        
                        // This usually indicates a file that has expired on the server, so there's no need to retry
                        failure(job, error, true)
                        
                    default:
                        failure(job, error, false)
                }
            }
    }
}

// MARK: - AttachmentDownloadJob.Details

extension AttachmentDownloadJob {
    public struct Details: Codable {
        public let attachmentId: String
        
        public init(attachmentId: String) {
            self.attachmentId = attachmentId
        }
    }
    
    public enum AttachmentDownloadError: LocalizedError {
        case failedToSaveFile
        case invalidUrl

        public var errorDescription: String? {
            switch self {
                case .failedToSaveFile: return "Failed to save file"
                case .invalidUrl: return "Invalid file URL"
            }
        }
    }
}
