//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupMessageAttachmentArchiver: MessageBackupProtoArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore

    init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
    }

    // MARK: - Archiving

    func archiveBodyAttachments(
        _ message: TSMessage,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<[BackupProto_FilePointer]> {
        // TODO: convert message's attachments into proto

        // TODO: enqueue upload of message's attachments to media tier (& thumbnail)

        return .success([])
    }

    // MARK: Restoring

    public func restoreBodyAttachments(
        _ attachments: [BackupProto_MessageAttachment],
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        var uuidErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>.ErrorType.InvalidProtoDataError]()
        let withUnwrappedUUIDs: [(BackupProto_MessageAttachment, UUID?)]
        withUnwrappedUUIDs = attachments.map { attachment in
            if attachment.hasClientUuid {
                guard let uuid = UUID(data: attachment.clientUuid) else {
                    uuidErrors.append(.invalidAttachmentClientUUID)
                    return (attachment, nil)
                }
                return (attachment, uuid)
            } else {
                return (attachment, nil)
            }
        }
        guard uuidErrors.isEmpty else {
            return .messageFailure(uuidErrors.map {
                .restoreFrameError(.invalidProtoData($0), chatItemId)
            })
        }

        let ownedAttachments = withUnwrappedUUIDs.map { attachment, clientUUID in
            return OwnedAttachmentBackupPointerProto(
                proto: attachment.pointer,
                renderingFlag: attachment.flag.asAttachmentFlag,
                clientUUID: clientUUID,
                owner: .messageBodyAttachment(.init(
                    messageRowId: messageRowId,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: thread.threadRowId
                ))
            )
        }

        return restoreAttachments(
            ownedAttachments,
            chatItemId: chatItemId,
            tx: tx
        )
    }

    public func restoreQuotedReplyThumbnailAttachment(
        _ attachment: BackupProto_MessageAttachment,
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let clientUUID: UUID?
        if attachment.hasClientUuid {
            guard let uuid = UUID(data: attachment.clientUuid) else {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.invalidAttachmentClientUUID),
                    chatItemId
                )])
            }
            clientUUID = uuid
        } else {
            clientUUID = nil
        }

        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment.pointer,
            renderingFlag: attachment.flag.asAttachmentFlag,
            clientUUID: clientUUID,
            owner: .quotedReplyAttachment(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            tx: tx
        )
    }

    public func restoreLinkPreviewAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment,
            // Link previews have no flags
            renderingFlag: .default,
            // ClientUUID is only for body and quoted reply attachments.
            clientUUID: nil,
            owner: .messageLinkPreview(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            tx: tx
        )
    }

    public func restoreContactAvatarAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment,
            // Contact share avatars have no flags
            renderingFlag: .default,
            // ClientUUID is only for body and quoted reply attachments.
            clientUUID: nil,
            owner: .messageContactAvatar(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            tx: tx
        )
    }

    private func restoreAttachments(
        _ attachments: [OwnedAttachmentBackupPointerProto],
        chatItemId: MessageBackup.ChatItemId,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        // TODO[Backups]: use actual subscription id. For now use a fixed,
        // arbitrary id, so that it never changes.
        let backupSubscriptionId = Data(repeating: 5, count: 32)
        let uploadEra: String
        do {
            uploadEra = try Attachment.uploadEra(backupSubscriptionId: backupSubscriptionId)
        } catch {
            return .messageFailure([.restoreFrameError(
                .uploadEraDerivationFailed(error),
                chatItemId
            )])
        }

        let errors = attachmentManager.createAttachmentPointers(
            from: attachments,
            uploadEra: uploadEra,
            tx: tx
        )

        // TODO: enqueue download of all the message's attachments

        if errors.isEmpty {
            return .success(())
        } else {
            // Treat attachment failures as message failures; a message
            // might have _only_ attachments and without them its invalid.
            return .messageFailure(errors.map {
                return .restoreFrameError(
                    $0.asRestoreFrameError,
                    chatItemId
                )
            })
        }
    }
}

extension BackupProto_MessageAttachment.Flag {

    fileprivate var asAttachmentFlag: AttachmentReference.RenderingFlag {
        switch self {
        case .none, .UNRECOGNIZED:
            return .default
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .gif:
            return .shouldLoop
        }
    }
}

extension OwnedAttachmentBackupPointerProto.CreationError {

    fileprivate var asRestoreFrameError: MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>.ErrorType {
        switch self {
        case .missingLocator:
            return .invalidProtoData(.filePointerMissingLocator)
        case .missingTransitCdnNumber:
            return .invalidProtoData(.filePointerMissingTransitCdnNumber)
        case .missingTransitCdnKey:
            return .invalidProtoData(.filePointerMissingTransitCdnKey)
        case .missingMediaName:
            return .invalidProtoData(.filePointerMissingMediaName)
        case .missingEncryptionKey:
            return .invalidProtoData(.filePointerMissingEncryptionKey)
        case .missingDigest:
            return .invalidProtoData(.filePointerMissingDigest)
        case .missingSize:
            return .invalidProtoData(.filePointerMissingSize)
        case .dbInsertionError(let error):
            return .databaseInsertionFailed(error)
        }
    }
}
