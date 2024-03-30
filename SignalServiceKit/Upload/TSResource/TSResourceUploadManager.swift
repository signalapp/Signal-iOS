//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TSResourceUploadManager {

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
            try await attachmentUploadManager.uploadAttachment(attachmentId: rowId)
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
