//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit
import SignalUI
import UIKit

class SharingThreadPickerViewController: ConversationPickerViewController {

    weak var shareViewDelegate: ShareViewDelegate?

    private var sendProgressSheet: SharingThreadPickerProgressSheet?

    /// It can take a while to fully process attachments, and until we do, we
    /// aren't fully sure if the attachments are stories-compatible. To speed
    /// things up, we do some fast pre-checks and store the result here.
    ///
    /// True if these pre-checks determine all attachments are
    /// stories-compatible. If this is true, we show stories forever, even if
    /// the attachments end up being incompatible, because it would be weird to
    /// have the stories destinations disappear. Instead, we show an error when
    /// actually sending if stories are selected.
    let areAttachmentStoriesCompatPrecheck: Bool

    var typedItems: [TypedItem] {
        didSet {
            owsPrecondition(typedItems.count <= 1 || typedItems.allSatisfy(\.isVisualMedia))
            updateStoriesState()
            updateApprovalMode()
        }
    }

    private var mentionCandidates: [Aci] = []

    private var selectedConversations: [ConversationItem] { selection.conversations }

    init(areAttachmentStoriesCompatPrecheck: Bool, shareViewDelegate: ShareViewDelegate) {
        self.typedItems = []
        self.areAttachmentStoriesCompatPrecheck = areAttachmentStoriesCompatPrecheck
        self.shareViewDelegate = shareViewDelegate

        super.init(selection: ConversationPickerSelection())

        shouldBatchUpdateIdentityKeys = true
        pickerDelegate = self

        self.updateStoriesState()
        self.updateApprovalMode()
    }

    func presentActionSheetOnNavigationController(_ alert: ActionSheetController) {
        if let navigationController = shareViewDelegate?.shareViewNavigationController {
            navigationController.presentActionSheet(alert)
        } else {
            self.presentActionSheet(alert)
        }
    }

    private func updateMentionCandidates() {
        AssertIsOnMainThread()

        guard
            selectedConversations.count == 1,
            case .group(let groupThreadId) = selectedConversations.first?.messageRecipient
        else {
            mentionCandidates = []
            return
        }

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        self.mentionCandidates = databaseStorage.read { tx in
            let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: tx)
            owsAssertDebug(groupThread != nil)
            if let groupThread, groupThread.allowsMentionSend {
                return groupThread.recipientAddresses(with: tx).compactMap(\.aci)
            } else {
                return []
            }
        }
    }

    private func updateStoriesState() {
        if areAttachmentStoriesCompatPrecheck || canSendTypedItemsToStory() {
            sectionOptions.insert(.stories)
        } else {
            sectionOptions.remove(.stories)
        }
    }

    private func canSendTypedItemsToStory() -> Bool {
        return !typedItems.isEmpty && typedItems.allSatisfy(\.isStoriesCompatible)
    }

    // MARK: - Approval

    func approve() {
        do {
            let vc = try buildApprovalViewController(withCancelButton: false)
            navigationController?.pushViewController(vc, animated: true)
        } catch {
            shareViewDelegate?.shareViewFailed(error: error)
        }
    }

    func buildApprovalViewController(for thread: TSThread) throws -> UIViewController {
        AssertIsOnMainThread()
        loadViewIfNeeded()
        guard let conversationItem = conversation(for: thread) else {
            throw OWSAssertionError("Unexpectedly missing conversation for selected thread")
        }
        selection.add(conversationItem)
        return try buildApprovalViewController(withCancelButton: true)
    }

    func buildApprovalViewController(withCancelButton: Bool) throws -> UIViewController {
        guard let anyItem = typedItems.first else {
            throw OWSAssertionError("Unexpectedly missing attachments")
        }

        let approvalVC: UIViewController

        switch anyItem {
        case .text(let inlineMessageText):
            let approvalView = TextApprovalViewController(
                messageBody: MessageBody(text: inlineMessageText.filteredValue.rawValue, ranges: .empty),
            )
            approvalVC = approvalView
            approvalView.delegate = self

        case .contact(let contactData):
            let cnContact = try SystemContact.parseVCardData(contactData)
            let contactShareDraft = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return ContactShareDraft.load(
                    cnContact: cnContact,
                    signalContact: SystemContact(cnContact: cnContact),
                    contactManager: SSKEnvironment.shared.contactManagerRef,
                    phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef,
                    profileManager: SSKEnvironment.shared.profileManagerRef,
                    recipientManager: DependenciesBridge.shared.recipientManager,
                    tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                    tx: tx,
                )
            }
            let approvalView = ContactShareViewController(contactShareDraft: contactShareDraft)
            approvalVC = approvalView
            approvalView.shareDelegate = self

        case .other:
            // We know that the first element of typedItems isn't .text or .contact
            // (see prior cases); the others must be visual media (see the precondition
            // on `typedItems`), so they also can't be .text or .contact.
            let approvalItems = typedItems.map {
                switch $0 {
                case .text, .contact:
                    owsFail("not possible")
                case .other(let attachment):
                    return AttachmentApprovalItem(attachment: attachment, canSave: false)
                }
            }
            var approvalVCOptions: AttachmentApprovalViewControllerOptions = withCancelButton ? [.hasCancel] : []
            if self.selection.conversations.contains(where: \.isStory) {
                approvalVCOptions.insert(.disallowViewOnce)
            }
            let approvalView = AttachmentApprovalViewController.loadWithSneakyTransaction(attachmentApprovalItems: approvalItems, options: approvalVCOptions)
            approvalVC = approvalView
            approvalView.approvalDelegate = self
            approvalView.approvalDataSource = self
        }

        return approvalVC
    }

    // MARK: - Sending

    private enum ApprovedSend {
        case text(messageBody: MessageBody, linkPreview: OWSLinkPreviewDraft?)
        case contact(contactShare: ContactShareDraft)
        case other(attachments: ApprovedAttachments, messageBody: MessageBody?)
    }

    private func send(_ approvedSend: ApprovedSend) {
        // Start presenting empty; the attachments will get set later.
        self.presentOrUpdateSendProgressSheet(attachmentIds: [])

        self.shareViewDelegate?.shareViewWillSend()

        Task {
            switch await tryToSend(
                selectedConversations: selectedConversations,
                approvedSend: approvedSend,
            ) {
            case nil:
                self.dismissSendProgressSheet {}
                self.shareViewDelegate?.shareViewWasCompleted()
            case .some(let failure):
                self.dismissSendProgressSheet { self.showSendFailure(failure) }
            }
        }
    }

    private struct SendFailure {
        let outgoingMessages: [PreparedOutgoingMessage]
        let error: Error
    }

    private func tryToSend(
        selectedConversations: [ConversationItem],
        approvedSend: ApprovedSend,
    ) async -> SendFailure? {
        switch approvedSend {
        case .text(let messageBody, let linkPreview):
            guard !messageBody.text.isEmpty else {
                return SendFailure(outgoingMessages: [], error: OWSAssertionError("Missing body."))
            }

            let linkPreviewDataSource: LinkPreviewDataSource?
            if let linkPreview {
                let linkPreviewManager = DependenciesBridge.shared.linkPreviewManager
                linkPreviewDataSource = try? await linkPreviewManager.buildDataSource(from: linkPreview)
            } else {
                linkPreviewDataSource = nil
            }

            return await self.sendToOutgoingMessageThreads(
                selectedConversations: selectedConversations,
                messageBody: messageBody,
                messageBlock: { destination, tx in
                    let unpreparedMessage = UnpreparedOutgoingMessage.build(
                        thread: destination.thread,
                        messageBody: destination.messageBody,
                        quotedReplyDraft: nil,
                        linkPreviewDataSource: linkPreviewDataSource,
                        transaction: tx,
                    )
                    return try unpreparedMessage.prepare(tx: tx)
                },
                enqueueStory: { conversations in
                    // Send the text message to any selected story recipients
                    // as a text story with default styling.
                    try await StorySharing.enqueueTextStory(
                        with: messageBody,
                        linkPreviewDraft: linkPreview,
                        to: conversations,
                    )
                },
            )
        case .contact(let contactShare):
            let contactShareForSending: ContactShareDraft.ForSending
            do {
                let contactShareManager = DependenciesBridge.shared.contactShareManager
                contactShareForSending = try await contactShareManager.validateAndPrepare(draft: contactShare)
            } catch {
                return SendFailure(outgoingMessages: [], error: error)
            }
            return await self.sendToOutgoingMessageThreads(
                selectedConversations: selectedConversations,
                messageBody: nil,
                messageBlock: { destination, tx in
                    let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                    let builder: TSOutgoingMessageBuilder = .withDefaultValues(
                        thread: destination.thread,
                        expiresInSeconds: dmConfigurationStore.durationSeconds(
                            for: destination.thread,
                            tx: tx,
                        ),
                    )
                    let message = builder.build(transaction: tx)
                    let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
                        message,
                        body: nil,
                        contactShareDraft: contactShareForSending,
                    )
                    return try unpreparedMessage.prepare(tx: tx)
                },
                // We don't send contact shares to stories
                enqueueStory: { _ in [] },
            )
        case .other(let attachments, let messageBody):
            // This method will also add threads to the profile whitelist.
            let enqueueResults: [AttachmentMultisend.EnqueueResult]
            do {
                enqueueResults = try await AttachmentMultisend.enqueueApprovedMedia(
                    conversations: selectedConversations,
                    approvedMessageBody: messageBody,
                    approvedAttachments: attachments,
                )
            } catch {
                return SendFailure(outgoingMessages: [], error: error)
            }

            self.presentOrUpdateSendProgressSheet(outgoingMessages: enqueueResults.map(\.preparedMessage))

            do {
                try await withThrowingTaskGroup { taskGroup in
                    for sendPromise in enqueueResults.map(\.sendPromise) {
                        taskGroup.addTask { try await sendPromise.awaitable() }
                    }
                    try await taskGroup.waitForAll()
                }
            } catch {
                return SendFailure(outgoingMessages: enqueueResults.map(\.preparedMessage), error: error)
            }

            return nil
        }
    }

    private func presentOrUpdateSendProgressSheet(outgoingMessages: [PreparedOutgoingMessage]) {
        let attachmentIds = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return outgoingMessages.attachmentIdsForUpload(tx: tx)
        }
        presentOrUpdateSendProgressSheet(attachmentIds: attachmentIds)
    }

    private func presentOrUpdateSendProgressSheet(attachmentIds: [Attachment.IDType]) {
        AssertIsOnMainThread()

        if let sendProgressSheet {
            // Update the existing sheet.
            sendProgressSheet.updateSendingAttachmentIds(attachmentIds)
            return
        } else {
            let actionSheet = SharingThreadPickerProgressSheet(
                attachmentIds: attachmentIds,
                delegate: self.shareViewDelegate,
            )
            presentActionSheetOnNavigationController(actionSheet)
            self.sendProgressSheet = actionSheet
        }
    }

    private func dismissSendProgressSheet(_ completion: (() -> Void)?) {
        if let sendProgressSheet {
            sendProgressSheet.dismiss(animated: true, completion: completion)
            self.sendProgressSheet = nil
        } else {
            completion?()
        }
    }

    private func sendToOutgoingMessageThreads(
        selectedConversations: [ConversationItem],
        messageBody: MessageBody?,
        messageBlock: (AttachmentMultisend.Destination, DBWriteTransaction) throws -> PreparedOutgoingMessage,
        enqueueStory: (_ conversations: [ConversationItem]) async throws -> [AttachmentMultisend.EnqueueResult],
    ) async -> SendFailure? {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        let conversations = selectedConversations.filter { $0.outgoingMessageType == .message }

        let preparedNonStoryMessages: [PreparedOutgoingMessage]
        let nonStorySendPromises: [Promise<Void>]
        do {
            let destinations = try await AttachmentMultisend.prepareDestinations(
                forSendingMessageBody: messageBody,
                toConversations: conversations,
            )

            (preparedNonStoryMessages, nonStorySendPromises) = try await databaseStorage.awaitableWrite { tx in
                let preparedMessages = try destinations.map { destination in
                    return try messageBlock(destination, tx)
                }

                // We're sending a message to this thread, approve any pending message request
                destinations.forEach { destination in
                    ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                        destination.thread,
                        setDefaultTimerIfNecessary: true,
                        tx: tx,
                    )
                }

                let sendPromises = preparedMessages.map {
                    ThreadUtil.enqueueMessagePromise(
                        message: $0,
                        transaction: tx,
                    )
                }
                return (preparedMessages, sendPromises)
            }
        } catch {
            return SendFailure(outgoingMessages: [], error: error)
        }

        let enqueueStoryResults: [AttachmentMultisend.EnqueueResult]
        do {
            enqueueStoryResults = try await enqueueStory(selectedConversations)
        } catch let error {
            return SendFailure(outgoingMessages: [], error: error)
        }

        let preparedMessages = preparedNonStoryMessages + enqueueStoryResults.map(\.preparedMessage)
        self.presentOrUpdateSendProgressSheet(outgoingMessages: preparedMessages)

        do {
            try await withThrowingTaskGroup { taskGroup in
                for sendPromise in nonStorySendPromises + enqueueStoryResults.map(\.sendPromise) {
                    taskGroup.addTask { try await sendPromise.awaitable() }
                }
                try await taskGroup.waitForAll()
            }
        } catch {
            return SendFailure(outgoingMessages: preparedMessages, error: error)
        }

        return nil
    }

    private nonisolated func threads(for conversationItems: [ConversationItem], tx: DBWriteTransaction) -> [TSThread] {
        return conversationItems.compactMap { conversation in
            guard let thread = conversation.getOrCreateThread(transaction: tx) else {
                owsFailDebug("Missing thread for conversation")
                return nil
            }
            return thread
        }
    }

    private func showSendFailure(_ failure: SendFailure) {
        AssertIsOnMainThread()

        Logger.warn("\(failure.error)")

        let cancelAction = ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
        ) { [weak self] _ in
            guard let self else { return }
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                for message in failure.outgoingMessages {
                    // If we sent the message to anyone, mark it as failed
                    message.updateWithAllSendingRecipientsMarkedAsFailed(tx: transaction)
                }
            }
            self.shareViewDelegate?.shareViewWasCancelled()
        }

        let failureTitle = OWSLocalizedString("SHARE_EXTENSION_SENDING_FAILURE_TITLE", comment: "Alert title")

        if let untrustedIdentityError = failure.error as? UntrustedIdentityError {
            let untrustedServiceId = untrustedIdentityError.serviceId
            let failureFormat = OWSLocalizedString(
                "SHARE_EXTENSION_FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_FORMAT",
                comment: "alert body when sharing file failed because of untrusted/changed identity keys",
            )
            let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(untrustedServiceId), tx: tx).resolvedValue()
            }
            let failureMessage = String(format: failureFormat, displayName)

            let actionSheet = ActionSheetController(title: failureTitle, message: failureMessage)
            actionSheet.addAction(cancelAction)

            // Capture the identity key before showing the prompt about it.
            let identityKey = SSKEnvironment.shared.databaseStorageRef.read { tx in
                let identityManager = DependenciesBridge.shared.identityManager
                return identityManager.identityKey(for: SignalServiceAddress(untrustedServiceId), tx: tx)
            }

            let confirmAction = ActionSheetAction(
                title: SafetyNumberStrings.confirmSendButton,
                style: .default,
            ) { [weak self] _ in
                guard let self else { return }

                // Confirm Identity
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    let identityManager = DependenciesBridge.shared.identityManager
                    let verificationState = identityManager.verificationState(
                        for: SignalServiceAddress(untrustedServiceId),
                        tx: transaction,
                    )
                    switch verificationState {
                    case .verified:
                        owsFailDebug("Unexpected state")
                    case .noLongerVerified, .implicit(isAcknowledged: _):
                        Logger.info("marked recipient: \(untrustedServiceId) as default verification status.")
                        guard let identityKey else {
                            owsFailDebug("Can't be untrusted unless there's already an identity key.")
                            return
                        }
                        _ = identityManager.setVerificationState(
                            .implicit(isAcknowledged: true),
                            of: identityKey,
                            for: SignalServiceAddress(untrustedServiceId),
                            isUserInitiatedChange: true,
                            tx: transaction,
                        )
                    }
                }

                // Resend
                self.resendMessages(failure.outgoingMessages)
            }
            actionSheet.addAction(confirmAction)

            presentActionSheetOnNavigationController(actionSheet)
        } else {
            let actionSheet = ActionSheetController(title: failureTitle)
            actionSheet.addAction(cancelAction)

            let retryAction = ActionSheetAction(title: CommonStrings.retryButton, style: .default) { [weak self] _ in
                self?.resendMessages(failure.outgoingMessages)
            }
            actionSheet.addAction(retryAction)

            presentActionSheetOnNavigationController(actionSheet)
        }
    }

    func resendMessages(_ outgoingMessages: [PreparedOutgoingMessage]) {
        AssertIsOnMainThread()
        owsAssertDebug(!outgoingMessages.isEmpty)

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef

        var promises = [Promise<Void>]()
        databaseStorage.write { tx in
            for message in outgoingMessages {
                promises.append(messageSenderJobQueue.add(.promise, message: message, transaction: tx))
            }
        }

        self.presentOrUpdateSendProgressSheet(outgoingMessages: outgoingMessages)
        Promise.when(fulfilled: promises).done {
            self.dismissSendProgressSheet {}
            self.shareViewDelegate?.shareViewWasCompleted()
        }.catch { error in
            self.dismissSendProgressSheet {
                self.showSendFailure(SendFailure(outgoingMessages: outgoingMessages, error: error))
            }
        }
    }
}

// MARK: -

extension SharingThreadPickerViewController: ConversationPickerDelegate {
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
        shareViewDelegate?.shareViewWasCancelled()
    }

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        return typedItems.isEmpty ? .loading : .next
    }

    func conversationPickerDidBeginEditingText() {}

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}

// MARK: -

extension SharingThreadPickerViewController: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft?) {
        assert(messageBody.text.nilIfEmpty != nil)
        send(.text(messageBody: messageBody, linkPreview: linkPreviewDraft))
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        shareViewDelegate?.shareViewWasCancelled()
    }

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String? {
        return nil
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

extension SharingThreadPickerViewController: ContactShareViewControllerDelegate {

    func contactShareViewController(_ viewController: ContactShareViewController, didApproveContactShare contactShare: ContactShareDraft) {
        send(.contact(contactShare: contactShare))
    }

    func contactShareViewControllerDidCancel(_ viewController: ContactShareViewController) {
        shareViewDelegate?.shareViewWasCancelled()
    }

    func titleForContactShareViewController(_ viewController: ContactShareViewController) -> String? {
        return nil
    }

    func recipientsDescriptionForContactShareViewController(_ viewController: ContactShareViewController) -> String? {
        let conversations = selectedConversations
        guard conversations.count > 0 else {
            return nil
        }
        return conversations.map { $0.titleWithSneakyTransaction }.joined(separator: ", ")
    }

    func approvalModeForContactShareViewController(_ viewController: ContactShareViewController) -> SignalUI.ApprovalMode {
        return .send
    }
}

// MARK: -

extension SharingThreadPickerViewController: AttachmentApprovalViewControllerDelegate {

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageBody newMessageBody: MessageBody?) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeViewOnceState isViewOnce: Bool) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachmentApprovalItem: AttachmentApprovalItem) {
        // We can ignore this event.
    }

    func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didApproveAttachments approvedAttachments: ApprovedAttachments,
        messageBody: MessageBody?,
    ) {
        send(.other(attachments: approvedAttachments, messageBody: messageBody))
    }

    func attachmentApprovalDidCancel() {
        shareViewDelegate?.shareViewWasCancelled()
    }

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
        owsFailDebug("Cannot add more to message forwards.")
    }
}

// MARK: -

extension SharingThreadPickerViewController: AttachmentApprovalViewControllerDataSource {

    var attachmentApprovalTextInputContextIdentifier: String? {
        return nil
    }

    var attachmentApprovalRecipientNames: [String] {
        selectedConversations.map { $0.titleWithSneakyTransaction }
    }

    func attachmentApprovalMentionableAcis(tx: DBReadTransaction) -> [Aci] {
        mentionCandidates
    }

    func attachmentApprovalMentionCacheInvalidationKey() -> String {
        return "\(mentionCandidates.hashValue)"
    }
}
