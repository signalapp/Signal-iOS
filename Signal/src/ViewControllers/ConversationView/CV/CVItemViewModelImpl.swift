//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// This class should only be accessed on the main thread.
@objc
public class CVItemViewModelImpl: NSObject, CVItemViewModel {

    public let renderItem: CVRenderItem
    private var componentState: CVComponentState { renderItem.componentState }

    @objc
    public required init(renderItem: CVRenderItem) {
        AssertIsOnMainThread()

        self.renderItem = renderItem
    }

    // MARK: -

    @objc
    public var interaction: TSInteraction {
        AssertIsOnMainThread()

        return renderItem.interaction
    }

    public var thread: TSThread {
        AssertIsOnMainThread()

        return renderItem.itemModel.thread
    }

    public var messageCellType: CVMessageCellType {
        AssertIsOnMainThread()

        return componentState.messageCellType
    }

    public var reactionState: InteractionReactionState? {
        AssertIsOnMainThread()

        return componentState.reactions?.reactionState
    }

    public var displayableBodyText: DisplayableText? {
        AssertIsOnMainThread()

        return componentState.bodyText?.displayableText
    }

    public var isViewOnce: Bool {
        AssertIsOnMainThread()

        guard let message = interaction as? TSMessage else {
            return false
        }
        return message.isViewOnceMessage
    }

    public var audioAttachmentStream: TSAttachmentStream? {
        AssertIsOnMainThread()

        return componentState.audioAttachment?.attachmentStream
    }

    public var genericAttachmentStream: TSAttachmentStream? {
        AssertIsOnMainThread()

        return componentState.genericAttachment?.attachmentStream
    }

    public var bodyMediaAttachmentStreams: [TSAttachmentStream] {
        AssertIsOnMainThread()

        guard let bodyMedia = componentState.bodyMedia else {
            return []
        }
        return bodyMedia.items.compactMap { $0.attachmentStream }
    }

    public var contactShare: ContactShareViewModel? {
        AssertIsOnMainThread()

        guard let contactShare = componentState.contactShare else {
            return nil
        }
        return contactShare.state.contactShare
    }

    public var stickerMetadata: StickerMetadata? {
        AssertIsOnMainThread()

        return componentState.sticker?.stickerMetadata
    }

    public var stickerAttachment: TSAttachmentStream? {
        AssertIsOnMainThread()

        return componentState.sticker?.attachmentStream
    }

    public var stickerInfo: StickerInfo? {
        AssertIsOnMainThread()

        return componentState.sticker?.stickerMetadata?.stickerInfo
    }

    public var linkPreview: OWSLinkPreview? {
        AssertIsOnMainThread()

        return componentState.linkPreview?.linkPreview
    }

    public var linkPreviewAttachment: TSAttachment? {
        AssertIsOnMainThread()

        return componentState.linkPreview?.linkPreviewAttachment
    }

    public var hasUnloadedAttachments: Bool {

        if componentState.bodyText == .oversizeTextDownloading {
            return true
        }
        if componentState.audioAttachment?.attachment as? TSAttachmentPointer != nil {
            return true
        }
        if componentState.genericAttachment?.attachmentPointer != nil {
            return true
        }
        if componentState.sticker?.attachmentPointer != nil {
            return true
        }
        guard let bodyMedia = componentState.bodyMedia else {
            return false
        }
        return !bodyMedia.items.compactMap { $0.attachment as? TSAttachmentPointer }.isEmpty
    }
}

// MARK: - Actions

extension CVItemViewModelImpl {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    // MARK: -

    var canCopyOrShareText: Bool {
        guard !isViewOnce else {
            return false
        }
        // TODO: We could hypothetically support copying other
        // items like contact shares.
        return displayableBodyText != nil
    }

    func copyTextAction() {
        guard !isViewOnce else {
            return
        }
        // TODO: We could hypothetically support copying other
        // items like contact shares.
        guard let displayableBodyText = self.displayableBodyText else {
            return
        }
        MentionTextView.copyAttributedStringToPasteboard(displayableBodyText.fullAttributedText)
    }

    var canShareMedia: Bool {
        !shareableAttachments.isEmpty
    }

    private var shareableAttachments: [TSAttachmentStream] {
        guard !isViewOnce else {
            return []
        }

        if let attachment = self.audioAttachmentStream {
            return [attachment]
        } else if let attachment = self.genericAttachmentStream {
            return [attachment]
        } else {
            return self.bodyMediaAttachmentStreams.filter { attachment in
                guard attachment.isValidVisualMedia else {
                    return false
                }
                if attachment.isImage || attachment.isAnimated {
                    return true
                }
                if attachment.isVideo,
                   let filePath = attachment.originalFilePath,
                   UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath) {
                    return true
                }
                return false
            }
        }
    }

    func shareMediaAction(sender: Any) {
        guard !isViewOnce else {
            return
        }
        let attachments = shareableAttachments
        guard !attachments.isEmpty else {
            return
        }
        AttachmentSharing.showShareUI(forAttachments: attachments, sender: sender)
    }

    var canForwardMessage: Bool {
        guard !isViewOnce else {
            return false
        }

        switch messageCellType {
        case .unknown, .dateHeader, .typingIndicator, .unreadIndicator, .threadDetails, .systemMessage:
            return false
        case .textOnlyMessage, .audio, .genericAttachment, .contactShare, .bodyMedia, .viewOnce, .stickerMessage:
            return !hasUnloadedAttachments
        }
    }

    func deleteAction() {
        let interaction = self.interaction
        databaseStorage.asyncWrite { transaction in
            interaction.anyRemove(transaction: transaction)
        }
    }
}
