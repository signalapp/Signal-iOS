//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc
public protocol ForwardMessageDelegate: AnyObject {
    @objc(forwardMessageFlowDidComplete:)
    func forwardMessageFlowDidComplete(threads: [TSThread])
    func forwardMessageFlowDidCancel()
}

// MARK: - Approval

extension ForwardMessageNavigationController {

    func approve() {
        do {
            try showApprovalUI()
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    func showApprovalUI() throws {
        switch conversationViewItem.messageCellType {
        case .textOnlyMessage:
            guard let body = approvalMessageText,
                body.count > 0 else {
                    throw OWSAssertionError("Missing body.")
            }

            let approvalView = TextApprovalViewController(messageText: body)
            approvalView.delegate = self
            pushViewController(approvalView, animated: true)
        case .contactShare:
            guard let oldContactShare = conversationViewItem.contactShare else {
                throw OWSAssertionError("Missing contactShareViewModel.")
            }
            let newContactShare = oldContactShare.copyForResending()
            let approvalView = ContactShareApprovalViewController(contactShare: newContactShare)
            approvalView.delegate = self
            pushViewController(approvalView, animated: true)
        case .audio,
             .genericAttachment,
             .stickerMessage:
            // Skip approval for these message types.
            send()
        case .mediaMessage:
//            fileprivate func pushApprovalViewController(
//                attachmentApprovalItems: [AttachmentApprovalItem],
//                options: AttachmentApprovalViewControllerOptions = .canAddMore,
//                animated: Bool
//                ) {
//                guard let sendMediaNavDelegate = self.sendMediaNavDelegate else {
//                    owsFailDebug("sendMediaNavDelegate was unexpectedly nil")
//                    return
//                }

//            public static let canAddMore = AttachmentApprovalViewControllerOptions(rawValue: 1 << 0)
//            public static let hasCancel = AttachmentApprovalViewControllerOptions(rawValue: 1 << 1)
//            public static let canToggleViewOnce = AttachmentApprovalViewControllerOptions(rawValue: 1 << 2)
            let options: AttachmentApprovalViewControllerOptions = .hasCancel
            let sendButtonImageName = "send-solid-24"

            var attachmentApprovalItems = [AttachmentApprovalItem]()
            guard let mediaAlbumItems = conversationViewItem.mediaAlbumItems else {
                throw OWSAssertionError("Missing mediaAlbumItems.")
            }
            for mediaAlbumItem in mediaAlbumItems {
                guard let attachmentStream = mediaAlbumItem.attachmentStream else {
                    continue
                }
                let signalAttachment = try attachmentStream.asSignalAttachmentForSending()
//                @interface ConversationMediaAlbumItem : NSObject
//
//                @property (nonatomic, readonly) TSAttachment *attachment;
//
//                // This property will only be set if the attachment is downloaded.
//                @property (nonatomic, readonly, nullable) TSAttachmentStream *attachmentStream;
//
//                // This property will be non-zero if the attachment is valid.
//                @property (nonatomic, readonly) CGSize mediaSize;
//
//                @property (nonatomic, readonly, nullable) NSString *caption;
//
//                @property (nonatomic, readonly) BOOL isFailedDownload;

//            for attachment in attachments {
                let attachmentApprovalItem = AttachmentApprovalItem(attachment: signalAttachment, canSave: false)
                attachmentApprovalItems.append(attachmentApprovalItem)
//                let cameraCaptureAttachment = CameraCaptureAttachment(signalAttachment: attachment, canSave: false)
//                navController.attachmentDraftCollection.append(.camera(attachment: cameraCaptureAttachment))
//                attachmentApprovalItems.append(cameraCaptureAttachment.attachmentApprovalItem)
            }
            //        let approvalItem = Attachmen
            let approvalViewController = AttachmentApprovalViewController(options: options,
                                                                          sendButtonImageName: sendButtonImageName,
                                                                          attachmentApprovalItems: attachmentApprovalItems)
            approvalViewController.approvalDelegate = self
            approvalViewController.messageText = approvalMessageText

            pushViewController(approvalViewController, animated: true)
        case .unknown,
             .oversizeTextDownloading,
             .viewOnce:
            throw OWSAssertionError("Invalid message type.")
        }
    }
}

// MARK: - Sending

extension ForwardMessageNavigationController {

    func send() {
        do {
            try tryToSend()
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    func tryToSend() throws {
        switch conversationViewItem.messageCellType {
        case .textOnlyMessage:
            guard let body = approvalMessageText,
                body.count > 0 else {
                    throw OWSAssertionError("Missing body.")
            }

            send { (thread, transaction) in
                self.send(body: body, thread: thread, transaction: transaction)
            }
        case .contactShare:
            guard let contactShare = approvedContactShare else {
                    throw OWSAssertionError("Missing contactShare.")
            }

            send { (thread, transaction) in
                let contactShareCopy = contactShare.copyForResending()

                if let avatarImage = contactShareCopy.avatarImage {
                    contactShareCopy.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
                }

                self.send(contactShare: contactShareCopy, thread: thread, transaction: transaction)
            }
        case .audio,
             .genericAttachment,
             .stickerMessage:

            guard let attachmentStream = conversationViewItem.attachmentStream else {
                throw OWSAssertionError("Missing attachmentStream.")
            }

            send { (thread, transaction) in
                let attachment = try attachmentStream.asSignalAttachmentForSending()
                self.send(body: "", attachment: attachment, thread: thread, transaction: transaction)
            }
        case .mediaMessage:
            guard let approvedAttachments = approvedAttachments else {
                throw OWSAssertionError("Missing approvedAttachments.")
            }

            let conversations = selectedConversationsForConversationPicker
            SendMediaNavigationController.sendApprovedMedia(conversations: conversations,
                                                            approvalMessageText: self.approvalMessageText,
                                                            approvedAttachments: approvedAttachments)
                .done { threads in
                    self.forwardMessageDelegate?.forwardMessageFlowDidComplete(threads: threads)
                }.retainUntilComplete()
        case .unknown,
             .oversizeTextDownloading,
             .viewOnce:
            throw OWSAssertionError("Invalid message type.")
        }
    }

    func send(body: String, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        let outgoingMessagePreparer = OutgoingMessagePreparer(fullMessageText: body, mediaAttachments: [], thread: thread, quotedReplyModel: nil, transaction: transaction)
        outgoingMessagePreparer.insertMessage(linkPreviewDraft: nil, transaction: transaction)
        messageSenderJobQueue.add(message: outgoingMessagePreparer, transaction: transaction)
    }

    func send(contactShare: ContactShareViewModel, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        let message = ThreadUtil.buildMessage(forContactShare: contactShare.dbRecord, in: thread, transaction: transaction)
        message.anyInsert(transaction: transaction)
        messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    func send(body: String, attachment: SignalAttachment, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        let outgoingMessagePreparer = OutgoingMessagePreparer(fullMessageText: body, mediaAttachments: [attachment], thread: thread, quotedReplyModel: nil, transaction: transaction)
        outgoingMessagePreparer.insertMessage(linkPreviewDraft: nil, transaction: transaction)
        messageSenderJobQueue.add(message: outgoingMessagePreparer, transaction: transaction)
    }

    func send(enqueueBlock: @escaping (TSThread, SDSAnyWriteTransaction) throws -> Void) {
        AssertIsOnMainThread()

        let conversations = selectedConversationsForConversationPicker

        DispatchQueue.global().async(.promise) {
            guard conversations.count > 0 else {
                throw OWSAssertionError("No recipients.")
            }

            var threads: [TSThread] = []

            var sendError: Error?
            self.databaseStorage.write { transaction in
                for conversation in conversations {
                    let thread: TSThread
                    switch conversation.messageRecipient {
                    case .contact(let address):
                        thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                                   transaction: transaction)
                    case .group(let groupThread):
                        thread = groupThread
                    }

                    do {
                        try enqueueBlock(thread, transaction)
                        threads.append(thread)
                    } catch {
                        owsFailDebug("error: \(error)")
                        sendError = error
                        break
                    }
                }
            }
            if let error = sendError {
                throw error
            }
                return threads
            }.done { threads in
                self.forwardMessageDelegate?.forwardMessageFlowDidComplete(threads: threads)
            }.retainUntilComplete()
    }
}

// MARK: -

@objc
class ForwardMessageNavigationController: OWSNavigationController {
//    class ForwardMessageNavigationController: SendMediaNavigationController {

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    // MARK: -

    @objc
    public weak var forwardMessageDelegate: ForwardMessageDelegate?

    var approvedAttachments: [SignalAttachment]?
    var approvedContactShare: ContactShareViewModel?
    var approvalMessageText: String?

    var selectedConversations: [ConversationItem] = []

    private let conversationViewItem: ConversationViewItem

    @objc
    public init(conversationViewItem: ConversationViewItem) {
        self.conversationViewItem = conversationViewItem

        if conversationViewItem.hasBodyText {
            self.approvalMessageText = conversationViewItem.displayableBodyText?.fullText
        }

        super.init(owsNavbar: ())

        let pickerVC = ConversationPickerViewController()
        pickerVC.delegate = self

        setViewControllers([
            pickerVC
            ], animated: false)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

extension ForwardMessageNavigationController: ConversationPickerDelegate {
    var selectedConversationsForConversationPicker: [ConversationItem] {
        return selectedConversations
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didSelectConversation conversation: ConversationItem) {
        self.selectedConversations.append(conversation)
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didDeselectConversation conversation: ConversationItem) {
        self.selectedConversations = self.selectedConversations.filter {
            $0.messageRecipient != conversation.messageRecipient
        }
    }

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        approve()
    }
}

// MARK: -

extension ForwardMessageNavigationController: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageText: String) {
        assert(messageText.count > 0)

        approvalMessageText = messageText.stripped.filterForDisplay

        send()
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }
}

// MARK: -

extension ForwardMessageNavigationController: ContactShareApprovalViewControllerDelegate {
    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didApproveContactShare contactShare: ContactShareViewModel) {
        approvedContactShare = contactShare

        send()
    }

    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didCancelContactShare contactShare: ContactShareViewModel) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }
}

// MARK: -

extension ForwardMessageNavigationController: AttachmentApprovalViewControllerDelegate {

    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        // TODO:
//        updateViewState(topViewController: attachmentApproval)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
        self.approvalMessageText = newMessageText
//        sendMediaNavDelegate?.sendMediaNav(self, didChangeMessageText: newMessageText)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
//        guard let removedDraft = attachmentDraftCollection.attachmentDraft(forAttachment: attachment) else {
//            owsFailDebug("removedDraft was unexpectedly nil")
//            return
//        }
//
//        attachmentDraftCollection.remove(removedDraft)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        self.approvedAttachments = attachments
        self.approvalMessageText = messageText

        send()
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
        owsFailDebug("Cannot add more to message forwards.")
    }

    var attachmentApprovalTextInputContextIdentifier: String? {
        return nil
    }
}

//extension ForwardMediaNavigationController: SendMediaNavDelegate {
//    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
//                             didApproveContactShare contactShare: ContactShareViewModel) {
//        approvedContactShare = contactShare
//
//        send()
//    }
//
//    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
//                             didCancelContactShare contactShare: ContactShareViewModel) {
//        forwardMessageDelegate?.forwardMessageFlowDidCancel()
//    }
//}

//@objc
//public protocol CameraFirstCaptureDelegate: AnyObject {
//    func cameraFirstCaptureSendFlowDidComplete(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
//    func cameraFirstCaptureSendFlowDidCancel(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
//}

//@objc
//public class ForwardMediaSendFlow: NSObject {
//    @objc
//    public weak var delegate: ForwardMessageDelegate?
//
//    var approvedAttachments: [SignalAttachment]?
//    var approvalMessageText: String?
//
//    var selectedConversations: [ConversationItem] = []
//
//    // MARK: Dependencies
//
//    var databaseStorage: SDSDatabaseStorage {
//        return SSKEnvironment.shared.databaseStorage
//    }
//}
////func forwardMessageFlowDidComplete(threads: [TSThread])
////func forwardMessageFlowDidCancel()
//
//extension ForwardMediaSendFlow: SendMediaNavDelegate {
//    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
//        delegate?.forwardMessageFlowDidCancel()
//    }
//    
//    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
//        self.approvedAttachments = attachments
//        self.approvalMessageText = messageText
//        
//        let pickerVC = ConversationPickerViewController()
//        pickerVC.delegate = self
//        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
//    }
//    
//    func sendMediaNavInitialMessageText(_ sendMediaNavigationController: SendMediaNavigationController) -> String? {
//        return approvalMessageText
//    }
//    
//    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageText newMessageText: String?) {
//        self.approvalMessageText = newMessageText
//    }
//    
//    var sendMediaNavApprovalButtonImageName: String {
//        return "arrow-right-24"
//    }
//    
//    var sendMediaNavCanSaveAttachments: Bool {
//        return true
//    }
//    
//    var sendMediaNavTextInputContextIdentifier: String? {
//        return nil
//    }
//}
//
//extension ForwardMediaSendFlow: ConversationPickerDelegate {
//    var selectedConversationsForConversationPicker: [ConversationItem] {
//        return selectedConversations
//    }
//    
//    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
//                            didSelectConversation conversation: ConversationItem) {
//        self.selectedConversations.append(conversation)
//    }
//    
//    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
//                            didDeselectConversation conversation: ConversationItem) {
//        self.selectedConversations = self.selectedConversations.filter {
//            $0.messageRecipient != conversation.messageRecipient
//        }
//    }
//    
//    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
//        guard let approvedAttachments = self.approvedAttachments else {
//            owsFailDebug("approvedAttachments was unexpectedly nil")
//            delegate?.forwardMessageFlowDidCancel()
//            return
//        }
//        
//        let conversations = selectedConversationsForConversationPicker
//        SendMediaNavigationController.sendApprovedMedia(conversations: conversations,
//                                                        approvalMessageText: self.approvalMessageText,
//                                                        approvedAttachments: approvedAttachments)
//            .done { threads in
//                self.delegate?.forwardMessageFlowDidComplete(threads: threads)
//            }.retainUntilComplete()
//    }
//}

// MARK: -

extension TSAttachmentStream {
    func asSignalAttachmentForSending() throws -> SignalAttachment {
        guard let sourceUrl = originalMediaURL else {
            throw OWSAssertionError("Missing originalMediaURL.")
        }
        guard let dataUTI = MIMETypeUtil.utiType(forMIMEType: contentType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }
        let newUrl = OWSFileSystem.temporaryFileUrl(fileExtension: sourceUrl.pathExtension)
        try FileManager.default.copyItem(at: sourceUrl, to: newUrl)

        let clonedDataSource = try DataSourcePath.dataSource(with: newUrl,
                                                             shouldDeleteOnDeallocation: true)
        clonedDataSource.sourceFilename = sourceFilename

        var signalAttachment: SignalAttachment
        if isVoiceMessage {
            signalAttachment = SignalAttachment.voiceMessageAttachment(dataSource: clonedDataSource, dataUTI: dataUTI)
        } else {
            signalAttachment = SignalAttachment.attachment(dataSource: clonedDataSource, dataUTI: dataUTI, imageQuality: .original)
        }
        signalAttachment.captionText = caption
        return signalAttachment
    }
}
