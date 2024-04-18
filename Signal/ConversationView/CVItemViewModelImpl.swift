//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class CVComponentStateWrapper: NSObject, CVItemViewModel {
    public var interaction: TSInteraction
    public var componentState: CVComponentState

    init(interaction: TSInteraction, componentState: CVComponentState) {
        self.interaction = interaction
        self.componentState = componentState
    }

    public var contactShare: ContactShareViewModel? {
        AssertIsOnMainThread()

        return componentState.contactShareModel
    }

    public var isGiftBadge: Bool {
        AssertIsOnMainThread()

        return componentState.giftBadge != nil
    }

    public var stickerMetadata: StickerMetadata? {
        AssertIsOnMainThread()

        return componentState.stickerMetadata
    }

    public var stickerAttachment: TSResourceStream? {
        AssertIsOnMainThread()

        return componentState.stickerAttachment
    }

    public var stickerInfo: StickerInfo? {
        AssertIsOnMainThread()

        return componentState.stickerInfo
    }

    public var linkPreview: OWSLinkPreview? {
        AssertIsOnMainThread()

        return componentState.linkPreviewModel
    }

    public var linkPreviewAttachment: TSResource? {
        AssertIsOnMainThread()

        return componentState.linkPreview?.linkPreviewAttachment
    }

    public var hasRenderableContent: Bool {
        return componentState.hasRenderableContent
    }
}

// This class should only be accessed on the main thread.
public class CVItemViewModelImpl: CVComponentStateWrapper {
    public let renderItem: CVRenderItem

    public init(renderItem: CVRenderItem) {
        AssertIsOnMainThread()

        self.renderItem = renderItem

        super.init(interaction: renderItem.interaction, componentState: renderItem.componentState)
    }

    // MARK: -

    public var thread: TSThread {
        AssertIsOnMainThread()

        return renderItem.itemModel.thread
    }

    public var messageCellType: CVMessageCellType {
        AssertIsOnMainThread()

        return componentState.messageCellType
    }

    public var paymentAttachment: CVComponentState.PaymentAttachment? {
        AssertIsOnMainThread()

        return componentState.paymentAttachment
    }

    public var reactionState: InteractionReactionState? {
        AssertIsOnMainThread()

        return componentState.reactions?.reactionState
    }

    public var displayableBodyText: DisplayableText? {
        AssertIsOnMainThread()

        return componentState.displayableBodyText
    }

    public var isViewOnce: Bool {
        AssertIsOnMainThread()

        guard let message = interaction as? TSMessage else {
            return false
        }
        return message.isViewOnceMessage
    }

    public var wasRemotelyDeleted: Bool {
        AssertIsOnMainThread()

        return (interaction as? TSMessage)?.wasRemotelyDeleted == true
    }

    public var audioAttachmentStream: TSResourceStream? {
        AssertIsOnMainThread()

        return componentState.audioAttachmentStream
    }

    public var genericAttachmentStream: TSResourceStream? {
        AssertIsOnMainThread()

        return componentState.genericAttachmentStream
    }

    public var bodyMediaAttachmentStreams: [TSResourceStream] {
        AssertIsOnMainThread()

        return componentState.bodyMediaAttachmentStreams
    }

    public var hasUnloadedAttachments: Bool {

        if componentState.bodyText == .oversizeTextDownloading {
            return true
        }
        if
            let audioAttachment = componentState.audioAttachment?.attachment,
            audioAttachment.asResourceStream() == nil
        {
            return true
        }
        if
            let genericAttachment = componentState.genericAttachment?.attachment.attachment,
            genericAttachment.asResourceStream() == nil
        {
            return true
        }
        if
            let sticker = componentState.sticker,
            sticker.attachmentStream == nil
        {
            return true
        }
        guard let bodyMedia = componentState.bodyMedia else {
            return false
        }
        return bodyMedia.items.contains(where: { $0.attachment.attachment.asResourceStream() == nil })
    }
}

// MARK: - Actions

extension CVItemViewModelImpl {

    var canEditMessage: Bool {
        return DependenciesBridge.shared.editManager.canShowEditMenu(interaction: interaction, thread: thread)
    }

    var canCopyOrShareOrSpeakText: Bool {
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
        BodyRangesTextView.copyToPasteboard(displayableBodyText.fullTextValue)
    }

    var canShareMedia: Bool {
        !shareableAttachments.isEmpty
    }

    private var shareableAttachments: [TSAttachmentStream] {
        guard !isViewOnce else {
            return []
        }

        if let attachment = self.audioAttachmentStream {
            return [attachment.bridgeStream]
        } else if let attachment = self.genericAttachmentStream {
            return [attachment.bridgeStream]
        } else {
            return self.bodyMediaAttachmentStreams.lazy.filter { attachment in
                switch attachment.computeContentType() {
                case .audio, .file:
                    return false
                case .image, .animatedImage:
                    return true
                case .video:
                    if
                        let filePath = attachment.bridgeStream.originalFilePath,
                        UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath)
                    {
                        return true
                    }
                    return false
                }
            }.map { attachment in
                return attachment.bridgeStream
            }
        }
    }

    func shareMediaAction(sender: Any?) {
        guard !isViewOnce else {
            return
        }

        guard !wasRemotelyDeleted else {
            return
        }

        let attachments = shareableAttachments
        guard !attachments.isEmpty else {
            return
        }
        AttachmentSharing.showShareUI(for: attachments, sender: sender)
    }

    var canForwardMessage: Bool {
        guard !isViewOnce else {
            return false
        }

        guard !wasRemotelyDeleted else {
            return false
        }

        switch messageCellType {
        case .unknown, .dateHeader, .typingIndicator, .unreadIndicator, .threadDetails, .systemMessage, .unknownThreadWarning, .defaultDisappearingMessageTimer:
            return false
        case .giftBadge:
            return false
        case .textOnlyMessage, .audio, .genericAttachment, .contactShare, .bodyMedia, .viewOnce, .stickerMessage, .quoteOnlyMessage:
            return !hasUnloadedAttachments
        case .paymentAttachment:
            return false
        }
    }
}

// MARK: -

public extension CVComponentState {

    var displayableBodyText: DisplayableText? {
        bodyText?.displayableText
    }

    var audioAttachmentStream: TSResourceStream? {
        audioAttachment?.attachmentStream
    }

    var genericAttachmentStream: TSResourceStream? {
        genericAttachment?.attachmentStream
    }

    var bodyMediaAttachmentStreams: [TSResourceStream] {
        guard let bodyMedia = self.bodyMedia else {
            return []
        }
        return bodyMedia.items.compactMap { $0.attachmentStream }
    }

    var contactShareModel: ContactShareViewModel? {
        guard let contactShare = self.contactShare else {
            return nil
        }
        return contactShare.state.contactShare
    }

    var stickerMetadata: StickerMetadata? {
        sticker?.stickerMetadata
    }

    var stickerAttachment: TSResourceStream? {
        sticker?.attachmentStream
    }

    var stickerInfo: StickerInfo? {
        sticker?.stickerMetadata?.stickerInfo
    }

    var linkPreviewModel: OWSLinkPreview? {
        linkPreview?.linkPreview
    }
}
