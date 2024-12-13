//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import SignalUI

public protocol SendMessageDelegate: AnyObject {
    func sendMessageFlowDidComplete(threads: [TSThread])
    func sendMessageFlowWillShowConversation()
    func sendMessageFlowDidCancel()
}

// MARK: -

struct SendMessageUnapprovedContent {
    let messageBody: MessageBody
    init?(messageBody: MessageBody) {
        if messageBody.text.isEmpty {
            return nil
        }
        self.messageBody = messageBody
    }
}

// MARK: -

struct SendMessageApprovedContent {
    let messageBody: MessageBody
    let linkPreviewDraft: OWSLinkPreviewDraft?
    init?(messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?) {
        guard let messageBody, !messageBody.text.isEmpty else {
            return nil
        }
        self.messageBody = messageBody
        self.linkPreviewDraft = linkPreviewDraft
    }
}

// MARK: -

class SendMessageFlow {

    private weak var delegate: SendMessageDelegate?

    private let unapprovedContent: SendMessageUnapprovedContent

    private var mentionCandidates: [SignalServiceAddress] = []

    private let selection = ConversationPickerSelection()
    private var selectedConversations: [ConversationItem] { selection.conversations }

    private let presentationStyle: PresentationStyle

    enum PresentationStyle {
      case pushOnto(UINavigationController)
      case presentFrom(UIViewController)
    }

    private weak var navigationController: UINavigationController?

    public init(
        unapprovedContent: SendMessageUnapprovedContent,
        presentationStyle: PresentationStyle,
        delegate: SendMessageDelegate
    ) {
        self.unapprovedContent = unapprovedContent
        self.presentationStyle = presentationStyle
        self.delegate = delegate

        let conversationPicker = ConversationPickerViewController(selection: selection)
        let navigationController: UINavigationController

        switch presentationStyle {
        case .pushOnto(let navController):
            navigationController = navController
        case .presentFrom:
            navigationController = OWSNavigationController(rootViewController: conversationPicker)
        }

        conversationPicker.pickerDelegate = self

        switch presentationStyle {
        case .pushOnto:
            if navigationController.viewControllers.isEmpty {
                navigationController.setViewControllers([
                    conversationPicker
                ], animated: false)
            } else {
                navigationController.pushViewController(conversationPicker, animated: true)
            }
        case .presentFrom(let viewController):
            viewController.present(navigationController, animated: true)
        }

        self.navigationController = navigationController
    }

    func dismissNavigationController(animated: Bool) {
        navigationController?.dismiss(animated: animated)
    }

    fileprivate func fireComplete(threads: [TSThread]) {
        delegate?.sendMessageFlowDidComplete(threads: threads)
    }

    fileprivate func fireWillShowConversation() {
        delegate?.sendMessageFlowWillShowConversation()
    }

    fileprivate func fireCancelled() {
        delegate?.sendMessageFlowDidCancel()
    }

    private func updateMentionCandidates() {
        AssertIsOnMainThread()

        guard selectedConversations.count == 1, case .group(let groupThreadId) = selectedConversations.first?.messageRecipient else {
            mentionCandidates = []
            return
        }

        let groupThread = SSKEnvironment.shared.databaseStorageRef.read { readTx in
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
        if let selectedConversation = selectedConversations.first, selectedConversations.count == 1 {
            showConversationComposeForSingleRecipient(conversationItem: selectedConversation, messageBody: unapprovedContent.messageBody)
        } else {
            showApprovalUI()
        }
    }

    private func showConversationComposeForSingleRecipient(conversationItem: ConversationItem, messageBody: MessageBody) {
        self.fireWillShowConversation()

        Task { @MainActor in
            let thread = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction -> TSThread in
                guard let thread = conversationItem.getOrCreateThread(transaction: transaction) else {
                    owsFail("Couldn't get thread that must exist.")
                }
                thread.updateWithDraft(
                    draftMessageBody: messageBody,
                    replyInfo: nil,
                    editTargetTimestamp: nil,
                    transaction: transaction
                )
                return thread
            }
            Logger.info("Transitioning to single thread.")
            SignalApp.shared.dismissAllModals(animated: true) {
                SignalApp.shared.presentConversationForThread(thread, action: .updateDraft, animated: true)
            }
        }
    }

    func showApprovalUI() {
        let approvalView = TextApprovalViewController(messageBody: unapprovedContent.messageBody)
        approvalView.delegate = self
        pushViewController(approvalView, animated: true)
    }
}

// MARK: - Sending

extension SendMessageFlow {

    private func send(approvedContent: SendMessageApprovedContent) {
        let selectedConversations = self.selectedConversations
        Task { @MainActor in
            let sentToThreads = await self.enqueueSend(toConversations: selectedConversations, approvedContent: approvedContent)
            self.fireComplete(threads: sentToThreads)
        }
    }

    func enqueueSend(toConversations conversations: [ConversationItem], approvedContent: SendMessageApprovedContent) async -> [TSThread] {
        let threads = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            return conversations.map { conversation -> TSThread in
                guard let thread = conversation.getOrCreateThread(transaction: tx) else {
                    owsFail("Couldn't get thread that must exist.")
                }
                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(thread, setDefaultTimerIfNecessary: true, tx: tx)
                return thread
            }
        }
        await withTaskGroup(of: Void.self) { taskGroup in
            for thread in threads {
                taskGroup.addTask {
                    await self.enqueueSend(toThread: thread, approvedContent: approvedContent)
                }
            }
        }
        return threads
    }

    func enqueueSend(toThread thread: TSThread, approvedContent: SendMessageApprovedContent) async {
        await withCheckedContinuation { continuation in
            ThreadUtil.enqueueMessage(body: approvedContent.messageBody, thread: thread, linkPreviewDraft: approvedContent.linkPreviewDraft, persistenceCompletionHandler: {
                continuation.resume()
            })
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
        return .next
    }

    func conversationPickerDidBeginEditingText() {}

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}

// MARK: -

extension SendMessageFlow: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?) {
        guard let approvedContent = SendMessageApprovedContent(messageBody: messageBody, linkPreviewDraft: linkPreviewDraft) else {
            owsFailDebug("Missing messageBody.")
            fireCancelled()
            return
        }

        send(approvedContent: approvedContent)
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        fireCancelled()
    }

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String? {
        return OWSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE", comment: "Title for the 'message approval' dialog.")
    }

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String? {
        return selectedConversations.map { $0.titleWithSneakyTransaction }.joined(separator: ", ").nilIfEmpty
    }

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode {
        return .send
    }
}

// MARK: -

public class SendMessageController: SendMessageDelegate {

    private weak var fromViewController: UIViewController?

    let sendMessageFlow = AtomicOptional<SendMessageFlow>(nil, lock: .sharedGlobal)

    public init(fromViewController: UIViewController) {
        self.fromViewController = fromViewController
    }

    public func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow.set(nil)

        guard let fromViewController = fromViewController else {
            return
        }

        fromViewController.navigationController?.popToViewController(fromViewController, animated: true)
    }

    public func sendMessageFlowWillShowConversation() {
        AssertIsOnMainThread()

        sendMessageFlow.set(nil)

        // Don't pop anything -- the callee will do that.
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
