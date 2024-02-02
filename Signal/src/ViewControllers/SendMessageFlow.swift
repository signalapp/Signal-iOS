//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

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
    case text(messageBody: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft?)
    case contactShare(contactShare: ContactShareViewModel)
    case installedSticker(stickerMetadata: StickerMetadata)
    case uninstalledSticker(stickerMetadata: StickerMetadata, stickerData: Data)
    case genericAttachment(signalAttachmentProvider: SignalAttachmentProvider)
    case borderlessMedia(signalAttachmentProvider: SignalAttachmentProvider)
    case media(signalAttachments: [SignalAttachment], messageBody: MessageBody?)
}

// MARK: -

class SendMessageFlow: Dependencies {

    private let flowType: SendMessageFlowType

    private let useConversationComposeForSingleRecipient: Bool

    private weak var delegate: SendMessageDelegate?

    private weak var navigationController: UINavigationController?

    var unapprovedContent: SendMessageUnapprovedContent

    var mentionCandidates: [SignalServiceAddress] = []

    private let selection = ConversationPickerSelection()
    var selectedConversations: [ConversationItem] { selection.conversations }

    public init(flowType: SendMessageFlowType,
                unapprovedContent: SendMessageUnapprovedContent,
                useConversationComposeForSingleRecipient: Bool,
                navigationController: UINavigationController,
                delegate: SendMessageDelegate) {
        self.flowType = flowType
        self.unapprovedContent = unapprovedContent
        self.useConversationComposeForSingleRecipient = useConversationComposeForSingleRecipient
        self.navigationController = navigationController
        self.delegate = delegate

        let conversationPicker = ConversationPickerViewController(selection: selection)
        conversationPicker.pickerDelegate = self

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

    private func updateMentionCandidates() {
        AssertIsOnMainThread()

        guard selectedConversations.count == 1,
              case .group(let groupThreadId) = selectedConversations.first?.messageRecipient else {
            mentionCandidates = []
            return
        }

        let groupThread = databaseStorage.read { readTx in
            TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: readTx)
        }

        owsAssertDebug(groupThread != nil)
        if let groupThread = groupThread, groupThread.allowsMentionSend {
            mentionCandidates = groupThread.recipientAddressesWithSneakyTransaction
        } else {
            mentionCandidates = []
        }
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
        if useConversationComposeForSingleRecipient,
            selectedConversations.count == 1,
            case .text(let messageBody) = unapprovedContent {
            showConversationComposeForSingleRecipient(messageBody: messageBody)
            return
        }

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

    private func showConversationComposeForSingleRecipient(messageBody: MessageBody) {
        let conversations = self.selectedConversations

        firstly { () -> Promise<[TSThread]> in
            self.threads(for: conversations)
        }.map(on: DispatchQueue.global()) { (threads: [TSThread]) -> TSThread in
            guard threads.count == 1,
                let thread = threads.first else {
                    throw OWSAssertionError("Unexpected thread state.")
            }
            return self.databaseStorage.write { transaction -> TSThread in
                thread.update(withDraft: messageBody,
                              replyInfo: nil,
                              editTargetTimestamp: nil,
                              transaction: transaction)
                return thread
            }
        }.done { (thread: TSThread) in
            Logger.info("Transitioning to single thread.")
            SignalApp.shared.dismissAllModals(animated: true) {
                SignalApp.shared.presentConversationForThread(thread, action: .updateDraft, animated: true)
            }
        }.catch { error in
            owsFailDebug("Error: \(error)")
            self.showSendFailedAlert()
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
            let approvalView = ContactShareViewController(contactShare: newContactShare)
            approvalView.shareDelegate = self
            pushViewController(approvalView, animated: true)
        case .media(let signalAttachmentProviders, let messageBody):
            let options: AttachmentApprovalViewControllerOptions = .hasCancel
            let attachmentApprovalItems = try signalAttachmentProviders.map { signalAttachmentProvider -> AttachmentApprovalItem in
                let signalAttachment = try signalAttachmentProvider.buildAttachmentForSending()
                return AttachmentApprovalItem(attachment: signalAttachment, canSave: false)
            }
            let approvalViewController = AttachmentApprovalViewController(options: options, attachmentApprovalItems: attachmentApprovalItems)
            approvalViewController.approvalDelegate = self
            approvalViewController.approvalDataSource = self
            approvalViewController.stickerSheetDelegate = self
            approvalViewController.setMessageBody(messageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)

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
            self.showSendFailedAlert()
        }
    }

    private func showSendFailedAlert() {
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        guard let viewController = navigationController.topViewController else {
            owsFailDebug("Missing topViewController.")
            return
        }

        let message = OWSLocalizedString("ERROR_DESCRIPTION_CLIENT_SENDING_FAILURE",
                                        comment: "Generic notice when message failed to send.")
        let actionSheet = ActionSheetController(title: CommonStrings.errorAlertTitle,
                                                message: message)
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okayButton) { [weak self] _ in
            self?.fireCancelled()
        })
        viewController.presentActionSheet(actionSheet)
    }

    func tryToSend(approvedContent: SendMessageApprovedContent) throws -> Promise<[TSThread]> {
        switch approvedContent {
        case .text(let messageBody, let linkPreviewDraft):
            guard !messageBody.text.isEmpty else {
                throw OWSAssertionError("Missing messageBody.")
            }
            return sendInEachThread { thread in
                self.send(messageBody: messageBody, linkPreviewDraft: linkPreviewDraft, thread: thread)
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

    func send(messageBody: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft?, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(body: messageBody,
                                      thread: thread,
                                      linkPreviewDraft: linkPreviewDraft,
                                      transaction: transaction)
        }
    }

    func send(contactShare: ContactShareViewModel, thread: TSThread) {
        ThreadUtil.enqueueMessage(withContactShare: contactShare.dbRecord, thread: thread)
    }

    func send(messageBody: MessageBody?, attachment: SignalAttachment, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(body: messageBody,
                                      mediaAttachments: [attachment],
                                      thread: thread,
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
                ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)
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
                    guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                        owsFailDebug("Missing thread for conversation")
                        continue
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

    func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {
        updateMentionCandidates()
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

    func conversationPickerDidBeginEditingText() {}

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}

// MARK: -

extension SendMessageFlow: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?) {
        assert(messageBody?.text.nilIfEmpty != nil)

        guard let messageBody = messageBody else {
            owsFailDebug("Missing messageBody.")
            fireCancelled()
            return
        }

        send(approvedContent: .text(messageBody: messageBody, linkPreviewDraft: linkPreviewDraft))
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        fireCancelled()
    }

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String? {
        switch flowType {
        case .`default`:
            return OWSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE", comment: "Title for the 'message approval' dialog.")
        case .forward:
            return OWSLocalizedString("FORWARD_MESSAGE", comment: "Label and title for 'message forwarding' views.")
        }
    }

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String? {
        let conversations = selectedConversations
        guard conversations.count > 0 else {
            return nil
        }
        return conversations.map { $0.titleWithSneakyTransaction }.joined(separator: ", ")
    }

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode {
        return .send
    }
}

// MARK: -

extension SendMessageFlow: ContactShareViewControllerDelegate {

    func contactShareViewController(_ viewController: ContactShareViewController, didApproveContactShare contactShare: ContactShareViewModel) {
        send(approvedContent: .contactShare(contactShare: contactShare))
    }

    func contactShareViewControllerDidCancel(_ viewController: ContactShareViewController) {
        fireCancelled()
    }

    func titleForContactShareViewController(_ viewController: ContactShareViewController) -> String? {
        switch flowType {
        case .`default`:
            return nil
        case .forward:
            return OWSLocalizedString("FORWARD_CONTACT", comment: "Label and title for 'contact forwarding' views.")
        }
    }

    func recipientsDescriptionForContactShareViewController(_ viewController: ContactShareViewController) -> String? {
        let conversations = selectedConversations
        guard conversations.count > 0 else {
            return nil
        }
        return conversations.map { $0.titleWithSneakyTransaction }.joined(separator: ", ")
    }

    func approvalModeForContactShareViewController(_ viewController: ContactShareViewController) -> ApprovalMode {
        return .send
    }
}

// MARK: -

extension SendMessageFlow: AttachmentApprovalViewControllerDelegate {

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

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeViewOnceState isViewOnce: Bool) {
        // We can ignore this event.
    }
}

// MARK: -

extension SendMessageFlow: AttachmentApprovalViewControllerDataSource {

    var attachmentApprovalTextInputContextIdentifier: String? {
        return nil
    }

    var attachmentApprovalRecipientNames: [String] {
        []
    }

    func attachmentApprovalMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        mentionCandidates
    }

    func attachmentApprovalMentionCacheInvalidationKey() -> String {
        return "\(mentionCandidates.hashValue)"
    }
}

// MARK: - StickerPickerSheetDelegate

extension SendMessageFlow: StickerPickerSheetDelegate {
    func makeManageStickersViewController() -> UIViewController {
        let manageStickersView = ManageStickersViewController()
        let navigationController = OWSNavigationController(rootViewController: manageStickersView)
        return navigationController
    }
}

// MARK: -

public class SendMessageController: SendMessageDelegate {

    private weak var fromViewController: UIViewController?

    let sendMessageFlow = AtomicOptional<SendMessageFlow>(nil)

    public required init(fromViewController: UIViewController) {
        self.fromViewController = fromViewController
    }

    public func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow.set(nil)

        guard let fromViewController = fromViewController else {
            return
        }

        if threads.count == 1,
           let thread = threads.first {
            SignalApp.shared.presentConversationForThread(thread, animated: true)
        } else {
            fromViewController.navigationController?.popToViewController(fromViewController, animated: true)
        }
    }

    public func sendMessageFlowDidCancel() {
        AssertIsOnMainThread()

        sendMessageFlow.set(nil)

        guard let fromViewController = fromViewController else {
            return
        }

        fromViewController.navigationController?.popToViewController(fromViewController, animated: true)
    }
}
