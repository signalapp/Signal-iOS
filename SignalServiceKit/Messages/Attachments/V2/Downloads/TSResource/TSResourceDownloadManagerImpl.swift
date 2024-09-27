//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceDownloadManagerImpl: TSResourceDownloadManager {

    private let attachmentDownloadManager: AttachmentDownloadManager
    private let tsAttachmentDownloadManager: TSAttachmentDownloadManager
    private let tsResourceStore: TSResourceStore

    public init(
        appReadiness: AppReadiness,
        attachmentDownloadManager: AttachmentDownloadManager,
        tsResourceStore: TSResourceStore
    ) {
        self.attachmentDownloadManager = attachmentDownloadManager
        self.tsAttachmentDownloadManager = TSAttachmentDownloadManager(appReadiness: appReadiness)
        self.tsResourceStore = tsResourceStore

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(v2AttachmentProgressNotification(_:)),
            name: AttachmentDownloads.attachmentDownloadProgressNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: AttachmentDownloads.attachmentDownloadProgressNotification,
            object: nil
        )
    }

    @objc
    private func v2AttachmentProgressNotification(_ notification: Notification) {
        /// Forward all v2 notifications as v1 notifications.
        guard
            let rowId = notification.userInfo?[AttachmentDownloads.attachmentDownloadAttachmentIDKey] as? Attachment.IDType,
            let progress = notification.userInfo?[AttachmentDownloads.attachmentDownloadProgressKey] as? CGFloat
        else {
            return
        }
        NotificationCenter.default.post(
            name: TSResourceDownloads.attachmentDownloadProgressNotification,
            object: nil,
            userInfo: [
                TSResourceDownloads.attachmentDownloadAttachmentIDKey: TSResourceId.v2(rowId: rowId),
                TSResourceDownloads.attachmentDownloadProgressKey: progress
            ]
        )
    }

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        let resources = tsResourceStore.allAttachments(for: message, tx: tx)
        var hasLegacyRef = false
        var hasV2Ref = false
        resources.forEach {
            switch $0.concreteType {
            case .legacy:
                hasLegacyRef = true
            case .v2:
                hasV2Ref = true
            }
        }
        // They should all be one type or the other. No mixing allowed.
        owsAssertDebug(!(hasLegacyRef && hasV2Ref))
        if hasV2Ref {
            attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(message, priority: priority, tx: tx)
        } else if hasLegacyRef {
            tsAttachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(
                message,
                downloadBehavior: priority.tsDownloadBehavior,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        } else {
            return
        }
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        switch message.attachment {
        case .file:
            tsAttachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(
                message,
                downloadBehavior: priority.tsDownloadBehavior,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        case .text(let attachment):
            if attachment.preview?.usesV2AttachmentReference == true {
                attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(message, priority: priority, tx: tx)
            } else if attachment.preview?.legacyImageAttachmentId != nil {
                tsAttachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(
                    message,
                    downloadBehavior: priority.tsDownloadBehavior,
                    transaction: SDSDB.shimOnlyBridge(tx)
                )
            } else {
                Logger.info("Nothing to download!")
                return
            }
        case .foreignReferenceAttachment:
            attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(message, priority: priority, tx: tx)
        }
    }

    public func cancelDownload(for attachmentId: TSResourceId, tx: DBWriteTransaction) {
        switch attachmentId {
        case .legacy(let uniqueId):
            tsAttachmentDownloadManager.cancelDownload(attachmentId: uniqueId)
        case .v2(let rowId):
            attachmentDownloadManager.cancelDownload(for: rowId, tx: tx)
        }
    }

    public func downloadProgress(for attachmentId: TSResourceId, tx: DBReadTransaction) -> CGFloat? {
        switch attachmentId {
        case .legacy(let uniqueId):
            return tsAttachmentDownloadManager.downloadProgress(forAttachmentId: uniqueId)
        case .v2(let rowId):
            return attachmentDownloadManager.downloadProgress(for: rowId, tx: tx)
        }
    }
}
