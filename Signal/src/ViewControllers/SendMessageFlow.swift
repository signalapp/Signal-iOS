//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc
public protocol SendMessageDelegate: AnyObject {
    func sendMessageFlowDidComplete(threads: [TSThread])
    func sendMessageFlowDidCancel()
}

// MARK: -

protocol SignalAttachmentProvider {
    func buildAttachmentForSending() throws -> SignalAttachment
    var isBorderless: Bool { get }
}

// MARK: -

// This can be used to forward an existing attachment stream.
struct TSAttachmentStreamCloner: SignalAttachmentProvider {
    let attachmentStream: TSAttachmentStream

    func buildAttachmentForSending() throws -> SignalAttachment {
        try attachmentStream.cloneAsSignalAttachment()
    }

    var isBorderless: Bool {
        attachmentStream.isBorderless
    }
}

// MARK: -

public enum SendMessageFlowType {
    case `default`
    case forward
}

// MARK: -

public enum SendMessageFlowError: Error {
    case invalidContent
}

// MARK: -

enum SendMessageUnapprovedContent {
    case text(messageBody: MessageBody)
    case contactShare(contactShare: ContactShareViewModel)
    // stickerAttachment is required if the sticker is not installed.
    case sticker(stickerMetadata: StickerMetadata, stickerAttachment: TSAttachmentStream?)
    case genericAttachment(signalAttachmentProvider: SignalAttachmentProvider)
    case media(signalAttachmentProviders: [SignalAttachmentProvider], messageBody: MessageBody?)

    fileprivate var needsApproval: Bool {
        switch self {
        case .text:
            return true
        case .contactShare:
            return true
        case .sticker:
            return false
        case .genericAttachment:
            return false
        case .media:
            return !isBorderless
        }
    }

    fileprivate var isBorderless: Bool {
        switch self {
        case .media(let attachmentStreamProviders, _):
            guard attachmentStreamProviders.count == 1,
                let attachmentStreamProvider = attachmentStreamProviders.first,
                attachmentStreamProvider.isBorderless else {
                    return false
            }
            return true
        default:
            return false
        }
    }

    // Some content types don't need approval.
    fileprivate func tryToBuildContentWithoutApproval() throws -> SendMessageApprovedContent? {
        switch self {
        case .text:
            owsAssertDebug(needsApproval)
            return nil
        case .contactShare:
            owsAssertDebug(needsApproval)
            return nil
        case .sticker(let stickerMetadata, let stickerAttachment):
            owsAssertDebug(!needsApproval)
            let stickerInfo = stickerMetadata.stickerInfo
            if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
                return .installedSticker(stickerMetadata: stickerMetadata)
            } else {
                guard let stickerAttachment = stickerAttachment else {
                    throw SendMessageFlowError.invalidContent
                }
                let stickerData = try stickerAttachment.readDataFromFile()
                return .uninstalledSticker(stickerMetadata: stickerMetadata, stickerData: stickerData)
            }
        case .genericAttachment(let signalAttachmentProvider):
            owsAssertDebug(!needsApproval)
            return .genericAttachment(signalAttachmentProvider: signalAttachmentProvider)
        case .media(let signalAttachmentProviders, let messageBody):
            guard signalAttachmentProviders.count == 1,
                let signalAttachmentProvider = signalAttachmentProviders.first,
                signalAttachmentProvider.isBorderless else {
                    owsAssertDebug(needsApproval)
                    return nil
            }
            owsAssertDebug(!needsApproval)
            owsAssertDebug(messageBody == nil)
            return .borderlessMedia(signalAttachmentProvider: signalAttachmentProvider)
        }
    }
}

// MARK: -

enum SendMessageApprovedContent {
    case text(messageBody: MessageBody)
    case contactShare(contactShare: ContactShareViewModel)
    case installedSticker(stickerMetadata: StickerMetadata)
    case uninstalledSticker(stickerMetadata: StickerMetadata, stickerData: Data)
    case genericAttachment(signalAttachmentProvider: SignalAttachmentProvider)
    case borderlessMedia(signalAttachmentProvider: SignalAttachmentProvider)
    case media(signalAttachments: [SignalAttachment], messageBody: MessageBody?)
}

// MARK: -

@objc
class SendMessageFlow: NSObject {

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    // MARK: -

    private let flowType: SendMessageFlowType

    private weak var delegate: SendMessageDelegate?

    private weak var navigationController: UINavigationController?

    var unapprovedContent: SendMessageUnapprovedContent

    var selectedConversations: [ConversationItem] = []

    public init(flowType: SendMessageFlowType,
                unapprovedContent: SendMessageUnapprovedContent,
                navigationController: UINavigationController,
                delegate: SendMessageDelegate) {
        self.flowType = flowType
        self.unapprovedContent = unapprovedContent
        self.navigationController = navigationController
        self.delegate = delegate

        super.init()

        let conversationPicker = ConversationPickerViewController()
        conversationPicker.delegate = self

        if navigationController.viewControllers.isEmpty {
            navigationController.setViewControllers([
                conversationPicker
            ], animated: false)
        } else {
            navigationController.pushViewController(conversationPicker, animated: true)
        }
    }

    fileprivate func fireComplete(threads: [TSThread]) {
        delegate?.sendMessageFlowDidComplete(threads: threads)
    }

    fileprivate func fireCancelled() {
        delegate?.sendMessageFlowDidCancel()
    }
}

// MARK: - Approval

extension SendMessageFlow {

    private func pushViewController(_ viewController: UIViewController, animated: Bool) {
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        navigationController.pushViewController(viewController, animated: animated)
    }

    func approve() {
        do {
            if let approvedContent = try unapprovedContent.tryToBuildContentWithoutApproval() {
                owsAssertDebug(!unapprovedContent.needsApproval)
                send(approvedContent: approvedContent)
                return
            }
            owsAssertDebug(unapprovedContent.needsApproval)
            try showApprovalUI()
        } catch {
            owsFailDebug("Error: \(error)")

            self.fireCancelled()
        }
    }

    func showApprovalUI() throws {
        switch unapprovedContent {
        case .text(let messageBody):
            guard !messageBody.text.isEmpty else {
                throw OWSAssertionError("Missing messageBody.")
            }
            let approvalView = TextApprovalViewController(messageBody: messageBody)
            approvalView.delegate = self
            pushViewController(approvalView, animated: true)
        case .contactShare(let oldContactShare):
            let newContactShare = oldContactShare.copyForResending()
            let approvalView = ContactShareApprovalViewController(contactShare: newContactShare)
            approvalView.delegate = self
            pushViewController(approvalView, animated: true)
        case .media(let signalAttachmentProviders, let messageBody):
            let options: AttachmentApprovalViewControllerOptions = .hasCancel
            let sendButtonImageName = "send-solid-24"

            let attachmentApprovalItems = try signalAttachmentProviders.map { signalAttachmentProvider -> AttachmentApprovalItem in
                let signalAttachment = try signalAttachmentProvider.buildAttachmentForSending()
                return AttachmentApprovalItem(attachment: signalAttachment, canSave: false)
            }
            let approvalViewController = AttachmentApprovalViewController(options: options,
                                                                          sendButtonImageName: sendButtonImageName,
                                                                          attachmentApprovalItems: attachmentApprovalItems)
            approvalViewController.approvalDelegate = self
            approvalViewController.messageBody = messageBody

            pushViewController(approvalViewController, animated: true)
        default:
            throw OWSAssertionError("Invalid message type or message type does not need approval.")
        }
    }
}

// MARK: - Sending

extension SendMessageFlow {

    func send(approvedContent: SendMessageApprovedContent) {
        firstly {
            try tryToSend(approvedContent: approvedContent)
        }.done { (threads: [TSThread]) in
            self.fireComplete(threads: threads)
        }.catch { error in
            owsFailDebug("Error: \(error)")
            // TODO: We could show an error alert.
            self.fireCancelled()
        }
    }

    func tryToSend(approvedContent: SendMessageApprovedContent) throws -> Promise<[TSThread]> {
        switch approvedContent {
        case .text(let messageBody):
            guard !messageBody.text.isEmpty else {
                throw OWSAssertionError("Missing messageBody.")
            }
            return sendInEachThread { thread in
                self.send(messageBody: messageBody, thread: thread)
            }
        case .contactShare(let contactShare):
            return sendInEachThread { thread in
                let contactShareCopy = contactShare.copyForResending()
                if let avatarImage = contactShareCopy.avatarImage {
                    self.databaseStorage.write { transaction in
                        contactShareCopy.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
                    }
                }

                self.send(contactShare: contactShareCopy, thread: thread)
            }
        case .installedSticker(let stickerMetadata):
            let stickerInfo = stickerMetadata.stickerInfo
            return sendInEachThread { thread in
                ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, thread: thread)
            }
        case .uninstalledSticker(let stickerMetadata, let stickerData):
            return sendInEachThread { thread in
                ThreadUtil.enqueueMessage(withUninstalledSticker: stickerMetadata, stickerData: stickerData, thread: thread)
            }
        case .genericAttachment(let signalAttachmentProvider):
            return sendInEachThread { thread in
                let signalAttachment = try signalAttachmentProvider.buildAttachmentForSending()
                self.send(messageBody: nil, attachment: signalAttachment, thread: thread)
            }
        case .borderlessMedia(let signalAttachmentProvider):
            return sendInEachThread { thread in
                let signalAttachment = try signalAttachmentProvider.buildAttachmentForSending()
                self.send(messageBody: nil, attachment: signalAttachment, thread: thread)
            }
        case .media(let signalAttachments, let messageBody):
            let conversations = selectedConversations
            return AttachmentMultisend.sendApprovedMedia(conversations: conversations,
                                                         approvalMessageBody: messageBody,
                                                         approvedAttachments: signalAttachments)
        }
    }

    func send(messageBody: MessageBody, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(with: messageBody,
                                      thread: thread,
                                      quotedReplyModel: nil,
                                      linkPreviewDraft: nil,
                                      transaction: transaction)
        }
    }

    func send(contactShare: ContactShareViewModel, thread: TSThread) {
        ThreadUtil.enqueueMessage(withContactShare: contactShare.dbRecord, thread: thread)
    }

    func send(messageBody: MessageBody?, attachment: SignalAttachment, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(with: messageBody,
                                      mediaAttachments: [attachment],
                                      thread: thread,
                                      quotedReplyModel: nil,
                                      linkPreviewDraft: nil,
                                      transaction: transaction)
        }
    }

    func sendInEachThread(enqueueBlock: @escaping (TSThread) throws -> Void) -> Promise<[TSThread]> {
        AssertIsOnMainThread()

        let conversations = self.selectedConversations
        return firstly {
            self.threads(for: conversations)
        }.map { (threads: [TSThread]) -> [TSThread] in
            // TODO: Move off main thread?
            for thread in threads {
                try enqueueBlock(thread)

                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
            }
            return threads
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

extension SendMessageFlow: ConversationPickerDelegate {
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
        fireCancelled()
    }

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        return unapprovedContent.needsApproval ? .next : .send
    }
}

// MARK: -

extension SendMessageFlow: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?) {
        assert(messageBody?.text.count ?? 0 > 0)

        guard let messageBody = messageBody else {
            owsFailDebug("Missing messageBody.")
            fireCancelled()
            return
        }

        send(approvedContent: .text(messageBody: messageBody))
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        fireCancelled()
    }

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String? {
        switch flowType {
        case .`default`:
            return NSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE", comment: "Title for the 'message approval' dialog.")
        case .forward:
            return NSLocalizedString("FORWARD_MESSAGE", comment: "Label and title for 'message forwarding' views.")
        }
    }

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String? {
        let conversations = selectedConversations
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

extension SendMessageFlow: ContactShareApprovalViewControllerDelegate {
    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didApproveContactShare contactShare: ContactShareViewModel) {

        send(approvedContent: .contactShare(contactShare: contactShare))
    }

    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didCancelContactShare contactShare: ContactShareViewModel) {
        fireCancelled()
    }

    func contactApprovalCustomTitle(_ contactApproval: ContactShareApprovalViewController) -> String? {
        switch flowType {
        case .`default`:
            return nil
        case .forward:
            return NSLocalizedString("FORWARD_CONTACT", comment: "Label and title for 'contact forwarding' views.")
        }
    }

    func contactApprovalRecipientsDescription(_ contactApproval: ContactShareApprovalViewController) -> String? {
        let conversations = selectedConversations
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

extension SendMessageFlow: AttachmentApprovalViewControllerDelegate {

    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageBody newMessageBody: MessageBody?) {
        // TODO: We could update unapprovedContent to reflect newMessageBody.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?) {

        send(approvedContent: .media(signalAttachments: attachments, messageBody: messageBody))
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        fireCancelled()
    }

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
        // TODO: Extend SendMessageFlow to handle camera first capture flow, share extension.
        owsFailDebug("Cannot add more to message forwards.")
    }

    var attachmentApprovalTextInputContextIdentifier: String? {
        return nil
    }

    var attachmentApprovalRecipientNames: [String] {
        selectedConversations.map { $0.title }
    }

    var attachmentApprovalMentionableAddresses: [SignalServiceAddress] {
        guard selectedConversations.count == 1,
            case .group(let groupThread) = selectedConversations.first?.messageRecipient,
            Mention.threadAllowsMentionSend(groupThread) else { return [] }
        return groupThread.recipientAddresses
    }
}
