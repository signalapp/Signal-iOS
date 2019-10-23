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
            self.pushViewController(approvalView, animated: true)
        case .contactShare:
            guard let oldContactShare = conversationViewItem.contactShare else {
                throw OWSAssertionError("Missing contactShareViewModel.")
            }
            let newContactShare = oldContactShare.copyForResending()
            let approvalView = ContactShareApprovalViewController(contactShare: newContactShare)
            approvalView.delegate = self
            self.pushViewController(approvalView, animated: true)
        case .audio,
             .genericAttachment,
             .stickerMessage:
            // Skip approval for these message types.
            send()
        case .mediaMessage:
            throw OWSAssertionError("Invalid message type.")
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
                guard let sourceUrl = attachmentStream.originalMediaURL else {
                    throw OWSAssertionError("Missing originalMediaURL.")
                }
                guard let dataUTI = MIMETypeUtil.utiType(forMIMEType: attachmentStream.contentType) else {
                    throw OWSAssertionError("Missing dataUTI.")
                }
                let newUrl = OWSFileSystem.temporaryFileUrl(fileExtension: sourceUrl.pathExtension)
                try FileManager.default.copyItem(at: sourceUrl, to: newUrl)

                let clonedDataSource = try DataSourcePath.dataSource(with: newUrl,
                                                                     shouldDeleteOnDeallocation: true)
                clonedDataSource.sourceFilename = attachmentStream.sourceFilename

                var attachment: SignalAttachment
                if attachmentStream.isVoiceMessage {
                    attachment = SignalAttachment.voiceMessageAttachment(dataSource: clonedDataSource, dataUTI: dataUTI)
                } else {
                    attachment = SignalAttachment.attachment(dataSource: clonedDataSource, dataUTI: dataUTI, imageQuality: .original)
                }
                self.send(body: "", attachment: attachment, thread: thread, transaction: transaction)
            }
        case .mediaMessage:
            throw OWSAssertionError("Invalid message type.")
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

    var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
        return AppEnvironment.shared.broadcastMediaMessageJobQueue
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
