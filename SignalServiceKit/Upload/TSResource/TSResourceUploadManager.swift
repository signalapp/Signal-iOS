//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TSResourceUploadManager {

    /// Upload a transient attachment that isn't saved to the database for sending.
    func uploadTransientAttachment(dataSource: DataSource) async throws -> Upload.Result<Upload.LocalUploadMetadata>

    /// Upload a TSAttachment to the given endpoint.
    /// - Parameters:
    ///   - param attachmentId: The id of the TSResourceStream to upload
    ///   - param messageIds: A list of TSInteractions representing the message or
    ///   album this attachment is associated with
    func uploadAttachment(attachmentId: TSResourceId, legacyMessageOwnerIds: [String]) async throws
}

public class TSResourceUploadManagerImpl: TSResourceUploadManager {

    private let attachmentUploadManager: AttachmentUploadManager
    private let tsAttachmentUploadManager: TSAttachmentUploadManager

    public init(
        attachmentUploadManager: AttachmentUploadManager,
        tsAttachmentUploadManager: TSAttachmentUploadManager
    ) {
        self.attachmentUploadManager = attachmentUploadManager
        self.tsAttachmentUploadManager = tsAttachmentUploadManager

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(forwardV2UpdateProgress(_:)),
            name: Upload.Constants.attachmentUploadProgressNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func uploadTransientAttachment(dataSource: DataSource) async throws -> Upload.Result<Upload.LocalUploadMetadata> {
        // Note this doesn't actually do anything v2 attachment related; AttachmentUploadManager is just
        // where transient attachment upload code lives. (Because this class and TSAttachmentUploadManager
        // will eventually be deleted but that code should live on.)
        return try await attachmentUploadManager.uploadTransientAttachment(dataSource: dataSource)
    }

    /// Entry point for uploading an `TSResourceStream`
    /// Fetches the `TSResourceStream`, builds the upload, begins the
    /// upload, and updates the `TSResourceStream` upon success.
    ///
    /// It is assumed any errors that could be retried or otherwise handled will have happend at a lower level,
    /// so any error encountered here is considered unrecoverable and thrown to the caller.
    public func uploadAttachment(attachmentId: TSResourceId, legacyMessageOwnerIds: [String]) async throws {
        switch attachmentId {
        case .legacy(let uniqueId):
            try await tsAttachmentUploadManager.uploadAttachment(attachmentId: uniqueId, messageIds: legacyMessageOwnerIds)
        case .v2(let rowId):
            try await attachmentUploadManager.uploadTransitTierAttachment(attachmentId: rowId)
        }
    }

    @objc
    private func forwardV2UpdateProgress(_ notification: Notification) {
        guard
            let progress = notification.userInfo?[Upload.Constants.uploadProgressKey] as? Double,
            let attachmentId = notification.userInfo?[Upload.Constants.uploadAttachmentIDKey] as? Attachment.IDType
        else {
            return
        }
        NotificationCenter.default.postNotificationNameAsync(
            Upload.Constants.resourceUploadProgressNotification,
            object: nil,
            userInfo: [
                Upload.Constants.uploadProgressKey: progress,
                Upload.Constants.uploadResourceIDKey: TSResourceId.v2(rowId: attachmentId)
            ]
        )
    }
}
