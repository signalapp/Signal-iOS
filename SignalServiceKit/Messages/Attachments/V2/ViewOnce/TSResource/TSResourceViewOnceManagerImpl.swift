//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceViewOnceManagerImpl: TSResourceViewOnceManager {

    private let attachmentViewOnceManager: AttachmentViewOnceManager
    private let db: any DB

    public init(
        attachmentViewOnceManager: AttachmentViewOnceManager,
        db: any DB
    ) {
        self.attachmentViewOnceManager = attachmentViewOnceManager
        self.db = db
    }

    public func prepareViewOnceContentForDisplay(_ message: TSMessage) -> TSViewOnceContent? {
        if message.attachmentIds?.isEmpty != false {
            return attachmentViewOnceManager.prepareViewOnceContentForDisplay(message)?.asTSContent
        }

        var content: TSViewOnceContent?
        // The only way to ensure that the content is never presented
        // more than once is to do a bunch of work (include file system
        // activity) inside a write transaction, which normally
        // wouldn't be desirable.
        db.write { transaction in
            let transaction = SDSDB.shimOnlyBridge(transaction)
            let interactionId = message.uniqueId
            guard let message = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) as? TSMessage else {
                return
            }
            guard message.isViewOnceMessage else {
                owsFailDebug("Unexpected message.")
                return
            }
            let messageId = message.uniqueId

            // Auto-complete the message before going any further.
            ViewOnceMessages.completeIfNecessary(message: message, transaction: transaction)
            guard !message.isViewOnceComplete else {
                return
            }

            // We should _always_ mark the message as complete,
            // even if the message is malformed, or if we fail
            // to do the "file system dance" below, etc.
            // and we fail to present the message content.
            defer {
                // This will eliminate the renderable content of the message.
                ViewOnceMessages.markAsComplete(message: message, sendSyncMessages: true, transaction: transaction)
            }

            guard
                let firstAttachmentId = message.attachmentIds?.first,
                let attachmentStream = TSAttachmentStream.anyFetchAttachmentStream(
                    uniqueId: firstAttachmentId,
                    transaction: transaction
                )
            else {
                return
            }
            guard attachmentStream.computeIsValidVisualMedia() else {
                return
            }
            let mimeType = attachmentStream.mimeType
            if mimeType.isEmpty {
                owsFailDebug("Missing mime type.")
                return
            }

            let viewOnceType: TSViewOnceContent.ContentType
            switch attachmentStream.computeContentType() {
            case .animatedImage:
                viewOnceType = .animatedImage
            case .image:
                viewOnceType = .stillImage
            case .video where attachmentStream.attachmentType.asRenderingFlag == .shouldLoop:
                viewOnceType = .loopingVideo
            case .video:
                viewOnceType = .video
            case .audio, .file, .invalid:
                owsFailDebug("Unexpected content type.")
                return
            }

            // To ensure that we never show the content more than once,
            // we mark the "view-once message" as complete _before_
            // presenting its contents.  A side effect of this is that
            // its renderable content is deleted.  We need the renderable
            // content to present it.  Therefore, we do a little dance:
            //
            // * Move the attachment file to a temporary file.
            // * Create an empty placeholder file in the old attachment
            //   file's location so that TSAttachmentStream's invariant
            //   of always corresponding to an underlying file on disk
            //   remains true.
            // * Delete the temporary file when this view is dismissed.
            // * If the app terminates at any step during this process,
            //   either: a) the file wasn't moved, the message wasn't
            //   marked as complete and the content wasn't displayed
            //   so the user can try again after relaunch.
            //   b) the file was moved and will be cleaned up on next
            //   launch like any other temp file if it hasn't been
            //   deleted already.
            guard let originalFilePath = attachmentStream.originalFilePath else {
                owsFailDebug("Attachment missing file path.")
                return
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: originalFilePath) else {
                owsFailDebug("Missing attachment file.")
                return
            }
            guard let fileExtension = MimeTypeUtil.fileExtensionForMimeType(mimeType) else {
                owsFailDebug("Couldn't determine file extension.")
                return
            }
            let tempFilePath = OWSFileSystem.temporaryFilePath(fileExtension: fileExtension)
            // Move the attachment to the temp file.
            do {
                try OWSFileSystem.moveFilePath(originalFilePath, toFilePath: tempFilePath)
            } catch {
                owsFailDebug("Couldn't move file: \(error.shortDescription)")
                return
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: tempFilePath) else {
                owsFailDebug("Missing temp file.")
                return
            }
            // This should be redundant since temp files are
            // created inside the per-launch temp folder
            // and should inherit protection from it.
            guard OWSFileSystem.protectFileOrFolder(atPath: tempFilePath) else {
                owsFailDebug("Couldn't protect temp file.")
                OWSFileSystem.deleteFile(tempFilePath)
                return
            }
            // Create new empty "placeholder file at the attachment's old
            //  location, since the attachment model should always correspond
            // to an underlying file on disk.
            guard OWSFileSystem.ensureFileExists(originalFilePath) else {
                owsFailDebug("Couldn't create placeholder file.")
                OWSFileSystem.deleteFile(tempFilePath)
                return
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: originalFilePath) else {
                owsFailDebug("Missing placeholder file.")
                OWSFileSystem.deleteFile(tempFilePath)
                return
            }

            content = TSViewOnceContent(
                messageId: messageId,
                type: viewOnceType,
                unencryptedFileUrl: URL(fileURLWithPath: tempFilePath),
                mimeType: mimeType
            )
        }
        return content
    }
}
