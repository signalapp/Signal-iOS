//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc
public protocol ForwardMessageDelegate: AnyObject {
    func forwardMessageFlowDidComplete(viewItem: ConversationViewItem,
                                       threads: [TSThread])
    func forwardMessageFlowDidCancel()
}

// MARK: -

@objc
class ForwardMessageNavigationController: OWSNavigationController {

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

        super.init()

        let pickerVC = ConversationPickerViewController()
        pickerVC.delegate = self

        setViewControllers([
            pickerVC
            ], animated: false)
    }

    @objc
    public class func present(for viewItem: ConversationViewItem,
                              from fromViewController: UIViewController,
                              delegate: ForwardMessageDelegate) {
        let modal = ForwardMessageNavigationController(conversationViewItem: viewItem)
        modal.forwardMessageDelegate = delegate
        fromViewController.presentFormSheet(modal, animated: true)
    }
}

// MARK: - Approval

extension ForwardMessageNavigationController {

    func approve() {
        guard needsApproval else {
            // Skip approval for these message types.
            send()
            return
        }

        do {
            try showApprovalUI()
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    private var needsApproval: Bool {
        guard ![.audio,
                 .genericAttachment,
                 .stickerMessage].contains(conversationViewItem.messageCellType) else { return false }

        guard !isBorderless else { return false }

        return true
    }

    private var isBorderless: Bool {
        guard let mediaAlbumItems = conversationViewItem.mediaAlbumItems else { return false }

        return mediaAlbumItems.count == 1 && mediaAlbumItems.first?.attachmentStream?.isBorderless == true
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
            throw OWSAssertionError("Message type does not need approval.")
        case .mediaMessage:
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
                let signalAttachment = try attachmentStream.cloneAsSignalAttachment()
                let attachmentApprovalItem = AttachmentApprovalItem(attachment: signalAttachment, canSave: false)
                attachmentApprovalItems.append(attachmentApprovalItem)
            }
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

            send { thread in
                self.send(body: body, thread: thread)
            }
        case .contactShare:
            guard let contactShare = approvedContactShare else {
                throw OWSAssertionError("Missing contactShare.")
            }

            send { thread in
                let contactShareCopy = contactShare.copyForResending()

                if let avatarImage = contactShareCopy.avatarImage {
                    self.databaseStorage.write { transaction in
                        contactShareCopy.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
                    }
                }

                self.send(contactShare: contactShareCopy, thread: thread)
            }
        case .stickerMessage:
            guard let stickerInfo = conversationViewItem.stickerInfo else {
                throw OWSAssertionError("Missing stickerInfo.")
            }

            if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
                send { thread in
                    self.send(installedSticker: stickerInfo, thread: thread)
                }
            } else {
                guard let stickerAttachment = conversationViewItem.stickerAttachment else {
                    owsFailDebug("Missing stickerAttachment.")
                    return
                }
                let stickerData = try stickerAttachment.readDataFromFile()
                send { thread in
                    self.send(uninstalledSticker: stickerInfo, stickerData: stickerData, thread: thread)
                }
            }
        case .audio,
             .genericAttachment:

            guard let attachmentStream = conversationViewItem.attachmentStream else {
                throw OWSAssertionError("Missing attachmentStream.")
            }

            send { thread in
                let attachment = try attachmentStream.cloneAsSignalAttachment()
                self.send(body: nil, attachment: attachment, thread: thread)
            }
        case .mediaMessage:
            if isBorderless {
                guard let attachmentStream = conversationViewItem.firstValidAlbumAttachment() else {
                    throw OWSAssertionError("Missing attachmentStream.")
                }

                send { thread in
                    let attachment = try attachmentStream.cloneAsSignalAttachment()
                    self.send(body: nil, attachment: attachment, thread: thread)
                }
            } else {
                guard let approvedAttachments = approvedAttachments else {
                    throw OWSAssertionError("Missing approvedAttachments.")
                }

                let conversations = selectedConversationsForConversationPicker
                firstly {
                    AttachmentMultisend.sendApprovedMedia(conversations: conversations,
                                                          approvalMessageText: self.approvalMessageText,
                                                          approvedAttachments: approvedAttachments)
                }.done { threads in
                    self.forwardMessageDelegate?.forwardMessageFlowDidComplete(viewItem: self.conversationViewItem,
                                                                               threads: threads)
                }.catch { error in
                    owsFailDebug("Error: \(error)")
                    // TODO: Do we need to call a delegate method?
                }
            }
        case .unknown,
             .oversizeTextDownloading,
             .viewOnce:
            throw OWSAssertionError("Invalid message type.")
        }
    }

    func send(body: String, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(withText: body, thread: thread, quotedReplyModel: nil, linkPreviewDraft: nil, transaction: transaction)
        }
    }

    func send(contactShare: ContactShareViewModel, thread: TSThread) {
        ThreadUtil.enqueueMessage(withContactShare: contactShare.dbRecord, thread: thread)
    }

    func send(body: String?, attachment: SignalAttachment, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(withText: body,
                                      mediaAttachments: [attachment],
                                      thread: thread,
                                      quotedReplyModel: nil,
                                      linkPreviewDraft: nil,
                                      transaction: transaction)
        }
    }

    func send(installedSticker stickerInfo: StickerInfo, thread: TSThread) {
        ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, thread: thread)
    }

    func send(uninstalledSticker stickerInfo: StickerInfo, stickerData: Data, thread: TSThread) {
        ThreadUtil.enqueueMessage(withUninstalledSticker: stickerInfo, stickerData: stickerData, thread: thread)
    }

    func send(enqueueBlock: @escaping (TSThread) throws -> Void) {
        AssertIsOnMainThread()

        let conversations = self.selectedConversationsForConversationPicker
        firstly {
            self.threads(for: conversations)
        }.done { (threads: [TSThread]) in
            for thread in threads {
                try enqueueBlock(thread)

                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
            }

            self.forwardMessageDelegate?.forwardMessageFlowDidComplete(viewItem: self.conversationViewItem,
                                                                       threads: threads)
        }.catch { error in
            owsFailDebug("Error: \(error)")
            // TODO: Do we need to call a delegate methoad?
        }
    }

    func threads(for conversationItems: [ConversationItem]) -> Promise<[TSThread]> {
        return DispatchQueue.global().async(.promise) {
            guard conversationItems.count > 0 else {
                throw OWSAssertionError("No recipients.")
            }

            var threads: [TSThread] = []

            self.databaseStorage.write { transaction in
                for conversation in conversationItems {
                    let thread: TSThread
                    switch conversation.messageRecipient {
                    case .contact(let address):
                        thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                                   transaction: transaction)
                    case .group(let groupThread):
                        thread = groupThread
                    }

                    threads.append(thread)
                }
            }
            return threads
        }
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

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool {
        return true
    }

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        return needsApproval ? .next : .send
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

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String? {
        return NSLocalizedString("FORWARD_MESSAGE", comment: "Label and title for 'message forwarding' views.")
    }

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String? {
        let conversations = selectedConversationsForConversationPicker
        guard conversations.count > 0 else {
            return nil
        }
        return conversations.map { $0.title }.joined(separator: ", ")
    }

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode {
        return .send
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

    func contactApprovalCustomTitle(_ contactApproval: ContactShareApprovalViewController) -> String? {
        return NSLocalizedString("FORWARD_CONTACT", comment: "Label and title for 'contact forwarding' views.")
    }

    func contactApprovalRecipientsDescription(_ contactApproval: ContactShareApprovalViewController) -> String? {
        let conversations = selectedConversationsForConversationPicker
        guard conversations.count > 0 else {
            return nil
        }
        return conversations.map { $0.title }.joined(separator: ", ")
    }

    func contactApprovalMode(_ contactApproval: ContactShareApprovalViewController) -> ApprovalMode {
        return .send
    }
}

// MARK: -

extension ForwardMessageNavigationController: AttachmentApprovalViewControllerDelegate {

    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
        self.approvalMessageText = newMessageText
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
        // We can ignore this event.
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

    var attachmentApprovalRecipientNames: [String] {
        selectedConversationsForConversationPicker.map { $0.title }
    }
}

// MARK: -

extension TSAttachmentStream {
    func cloneAsSignalAttachment() throws -> SignalAttachment {
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
        signalAttachment.isBorderless = isBorderless
        return signalAttachment
    }
}
