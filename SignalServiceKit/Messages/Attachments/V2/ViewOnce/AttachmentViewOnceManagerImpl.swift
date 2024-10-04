//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentViewOnceManagerImpl: AttachmentViewOnceManager {

    private let attachmentStore: AttachmentStore
    private let db: any DB
    private let interactionStore: InteractionStore

    public init(
        attachmentStore: AttachmentStore,
        db: any DB,
        interactionStore: InteractionStore
    ) {
        self.attachmentStore = attachmentStore
        self.db = db
        self.interactionStore = interactionStore
    }

    public func prepareViewOnceContentForDisplay(_ message: TSMessage) -> ViewOnceContent? {
        guard let messageRowId = message.sqliteRowId else {
            // Don't ever display uninserted view once messages; we can't lock without the db.
            return nil
        }
        // Re-fetch the message.
        let message = db.read { tx in
            self.interactionStore.fetchInteraction(rowId: messageRowId, tx: tx) as? TSMessage
        }
        guard let message else {
            return nil
        }

        guard message.isViewOnceMessage else {
            owsFailDebug("Unexpected view once message.")
            return nil
        }

        // We should _always_ mark the message as complete,
        // even if the message is malformed, or if we fail
        // to do the "file system dance" below, etc.
        // and we fail to present the message content.
        defer {
            db.write { tx in
                // This will eliminate the renderable content of the message.
                ViewOnceMessages.markAsComplete(
                    message: message,
                    sendSyncMessages: true,
                    transaction: SDSDB.shimOnlyBridge(tx)
                )
            }
        }

        let attachment = db.read { tx in
            return attachmentStore.fetchFirstReferencedAttachment(
                for: .messageBodyAttachment(messageRowId: messageRowId),
                tx: tx
            )
        }
        guard let attachmentStream = attachment?.asReferencedStream else {
            owsFailDebug("Viewing unavailable view once attachment")
            return nil
        }

        let viewOnceType: ViewOnceContent.ContentType
        switch attachmentStream.attachmentStream.contentType {
        case .file, .invalid, .audio:
            owsFailDebug("Unexpected content type.")
            return nil
        case .animatedImage:
            viewOnceType = .animatedImage
        case .image:
            viewOnceType = .stillImage
        case .video where attachmentStream.reference.renderingFlag == .shouldLoop:
            viewOnceType = .loopingVideo
        case .video:
            viewOnceType = .video
        }

        // To ensure that we never show the content more than once,
        // we mark the "view-once message" as complete _before_
        // presenting its contents.  A side effect of this is that
        // its renderable content is deleted.  We need the renderable
        // content to present it.  Therefore, we do a little dance:
        //
        // * Move the attachment file to a temporary file.
        // * Delete the temporary file when done displaying (handled by ViewOnceContent).
        // * If the app terminates at any step during this process,
        //   either: a) the file wasn't moved, the message wasn't
        //   marked as complete and the content wasn't displayed
        //   so the user can try again after relaunch.
        //   b) the file was moved and will be cleaned up on next
        //   launch like any other temp file if it hasn't been
        //   deleted already.
        let originalFileUrl = attachmentStream.attachmentStream.fileURL
        guard OWSFileSystem.fileOrFolderExists(url: originalFileUrl) else {
            owsFailDebug("Missing attachment file.")
            return nil
        }
        let tempFileUrl = OWSFileSystem.temporaryFileUrl()
        guard !OWSFileSystem.fileOrFolderExists(url: tempFileUrl) else {
            owsFailDebug("Temp file unexpectedly already exists.")
            return nil
        }
        // Copy the attachment to the temp file.
        do {
            try OWSFileSystem.copyFile(from: originalFileUrl, to: tempFileUrl)
        } catch {
            owsFailDebug("Couldn't copy file.")
            return nil
        }
        guard OWSFileSystem.fileOrFolderExists(url: tempFileUrl) else {
            owsFailDebug("Missing temp file.")
            return nil
        }
        // This should be redundant since temp files are
        // created inside the per-launch temp folder
        // and should inherit protection from it.
        guard OWSFileSystem.protectFileOrFolder(atPath: tempFileUrl.path) else {
            owsFailDebug("Couldn't protect temp file.")
            try? OWSFileSystem.deleteFile(url: tempFileUrl)
            return nil
        }

        return ViewOnceContent(
            messageId: message.uniqueId,
            type: viewOnceType,
            fileUrl: tempFileUrl,
            encryptionKey: attachmentStream.attachmentStream.attachment.encryptionKey,
            plaintextLength: attachmentStream.attachmentStream.info.unencryptedByteCount,
            mimeType: attachmentStream.attachmentStream.mimeType
        )
    }
}
