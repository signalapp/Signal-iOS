//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import Foundation
import SignalServiceKit
import SignalUI

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
    public let areAttachmentStoriesCompatPrecheck: Bool

    var attachments: [SignalAttachment]? {
        didSet {
            updateStoriesState()
            updateApprovalMode()
        }
    }

    var isTextMessage: Bool {
        guard let attachments = attachments, attachments.count == 1, let attachment = attachments.first else { return false }
        return attachment.isConvertibleToTextMessage && attachment.dataLength <= kOversizeTextMessageSizeThreshold
    }

    var isContactShare: Bool {
        guard let attachments = attachments, attachments.count == 1, let attachment = attachments.first else { return false }
        return attachment.isConvertibleToContactShare
    }

    var approvedAttachments: [SignalAttachment]?
    var approvedContactShare: ContactShareDraft?
    var approvalMessageBody: MessageBody?
    var approvalLinkPreviewDraft: OWSLinkPreviewDraft?

    var mentionCandidates: [SignalServiceAddress] = []

    var selectedConversations: [ConversationItem] { selection.conversations }

    public init(areAttachmentStoriesCompatPrecheck: Bool, shareViewDelegate: ShareViewDelegate) {
        self.areAttachmentStoriesCompatPrecheck = areAttachmentStoriesCompatPrecheck
        self.shareViewDelegate = shareViewDelegate

        super.init(selection: ConversationPickerSelection())

        shouldBatchUpdateIdentityKeys = true
        pickerDelegate = self

        self.updateStoriesState()
        self.updateApprovalMode()
    }

    public func presentActionSheetOnNavigationController(_ alert: ActionSheetController) {
        if let navigationController = shareViewDelegate?.shareViewNavigationController {
            navigationController.presentActionSheet(alert)
        } else {
            super.presentActionSheet(alert)
        }
    }

    private func updateMentionCandidates() {
        AssertIsOnMainThread()

        guard selectedConversations.count == 1,
              case .group(let groupThreadId) = selectedConversations.first?.messageRecipient else {
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

    private func updateStoriesState() {
        if areAttachmentStoriesCompatPrecheck == true {
            sectionOptions.insert(.stories)
        } else if let attachments = attachments, attachments.allSatisfy({ $0.isValidImage || $0.isValidVideo }) {
            sectionOptions.insert(.stories)
        } else if isTextMessage {
            sectionOptions.insert(.stories)
        } else {
            sectionOptions.remove(.stories)
        }
    }
}

// MARK: - Approval

extension SharingThreadPickerViewController {

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
        guard let attachments = attachments, let firstAttachment = attachments.first else {
            throw OWSAssertionError("Unexpectedly missing attachments")
        }

        let approvalVC: UIViewController

        if isTextMessage {
            guard let messageText = String(data: firstAttachment.data, encoding: .utf8)?.filterForDisplay else {
                throw OWSAssertionError("Missing or invalid message text for text attachment")
            }
            let approvalView = TextApprovalViewController(messageBody: MessageBody(text: messageText, ranges: .empty))
            approvalVC = approvalView
            approvalView.delegate = self

        } else if isContactShare {
            let cnContact = try SystemContact.parseVCardData(firstAttachment.data)

            let contactShareDraft = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return ContactShareDraft.load(
                    cnContact: cnContact,
                    signalContact: SystemContact(cnContact: cnContact),
                    contactManager: SSKEnvironment.shared.contactManagerRef,
                    phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef,
                    profileManager: SSKEnvironment.shared.profileManagerRef,
                    recipientManager: DependenciesBridge.shared.recipientManager,
                    tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                    tx: tx
                )
            }

            let approvalView = ContactShareViewController(contactShareDraft: contactShareDraft)
            approvalVC = approvalView
            approvalView.shareDelegate = self

        } else {
            let approvalItems = attachments.map { AttachmentApprovalItem(attachment: $0, canSave: false) }
            var approvalVCOptions: AttachmentApprovalViewControllerOptions = withCancelButton ? [ .hasCancel ] : []
            if self.selection.conversations.contains(where: \.isStory) {
                approvalVCOptions.insert(.disallowViewOnce)
            }
            let approvalView = AttachmentApprovalViewController(options: approvalVCOptions, attachmentApprovalItems: approvalItems)
            approvalVC = approvalView
            approvalView.approvalDelegate = self
            approvalView.approvalDataSource = self
        }

        return approvalVC
    }
}

// MARK: - Sending

extension SharingThreadPickerViewController {

    func send() {
        // Start presenting empty; the attachments will get set later.
        self.presentOrUpdateSendProgressSheet(attachmentIds: [])

        self.shareViewDelegate?.shareViewWillSend()

        Task {
            switch await tryToSend(
                selectedConversations: selectedConversations,
                isTextMessage: isTextMessage,
                isContactShare: isContactShare,
                messageBody: approvalMessageBody,
                attachments: approvedAttachments,
                linkPreviewDraft: approvalLinkPreviewDraft,
                contactShareDraft: approvedContactShare
            ) {
            case .success:
                self.dismissSendProgressSheet {}
                self.shareViewDelegate?.shareViewWasCompleted()
            case .failure(let error):
                self.dismissSendProgressSheet { self.showSendFailure(error: error) }
            }
        }
    }

    private struct SendError: Error {
        let outgoingMessages: [PreparedOutgoingMessage]
        let error: Error
    }

    private nonisolated func tryToSend(
        selectedConversations: [ConversationItem],
        isTextMessage: Bool,
        isContactShare: Bool,
        messageBody: MessageBody?,
        attachments: [SignalAttachment]?,
        linkPreviewDraft: OWSLinkPreviewDraft?,
        contactShareDraft: ContactShareDraft?
    ) async -> Result<Void, SendError> {
        if isTextMessage {
            guard let messageBody, !messageBody.text.isEmpty else {
                return .failure(.init(outgoingMessages: [], error: OWSAssertionError("Missing body.")))
            }

            let linkPreviewDataSource: LinkPreviewDataSource?
            if let linkPreviewDraft {
                linkPreviewDataSource = try? DependenciesBridge.shared.linkPreviewManager.buildDataSource(
                    from: linkPreviewDraft
                )
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
                        transaction: tx
                    )
                    return try unpreparedMessage.prepare(tx: tx)
                },
                storySendBlock: { storyConversations in
                    // Send the text message to any selected story recipients
                    // as a text story with default styling.
                    StorySharing.sendTextStory(
                        with: messageBody,
                        linkPreviewDraft: linkPreviewDraft,
                        to: storyConversations
                    )
                }
            )
        } else if isContactShare {
            guard let contactShareDraft else {
                return .failure(.init(outgoingMessages: [], error: OWSAssertionError("Missing contactShare.")))
            }
            let contactShareForSending: ContactShareDraft.ForSending
            do {
                contactShareForSending = try DependenciesBridge.shared.contactShareManager.validateAndPrepare(
                    draft: contactShareDraft
                )
            } catch {
                return .failure(.init(outgoingMessages: [], error: error))
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
                            tx: tx
                        )
                    )
                    let message = builder.build(transaction: tx)
                    let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
                        message,
                        contactShareDraft: contactShareForSending
                    )
                    return try unpreparedMessage.prepare(tx: tx)
                },
                // We don't send contact shares to stories
                storySendBlock: nil
            )
        } else {
            guard let attachments else {
                return .failure(.init(outgoingMessages: [], error: OWSAssertionError("Missing approvedAttachments.")))
            }

            // This method will also add threads to the profile whitelist.
            let sendResult = AttachmentMultisend.sendApprovedMedia(
                conversations: selectedConversations,
                approvedMessageBody: messageBody,
                approvedAttachments: attachments
            )

            let preparedMessages: [PreparedOutgoingMessage]
            do {
                preparedMessages = try await sendResult.preparedPromise.awaitable()
            } catch let error {
                return .failure(.init(outgoingMessages: [], error: error))
            }
            await MainActor.run {
                self.presentOrUpdateSendProgressSheet(outgoingMessages: preparedMessages)
            }

            do {
                _ = try await sendResult.sentPromise.awaitable()
            } catch let error {
                return .failure(.init(outgoingMessages: preparedMessages, error: error))
            }
            return .success(())
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
                delegate: self.shareViewDelegate
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

    private nonisolated func sendToOutgoingMessageThreads(
        selectedConversations: [ConversationItem],
        messageBody: MessageBody?,
        messageBlock: @escaping (AttachmentMultisend.Destination, DBWriteTransaction) throws -> PreparedOutgoingMessage,
        storySendBlock: (([ConversationItem]) -> AttachmentMultisend.Result?)?
    ) async -> Result<Void, SendError> {
        let conversations = selectedConversations.filter { $0.outgoingMessageType == .message }

        let preparedNonStoryMessages: [PreparedOutgoingMessage]
        let nonStorySendPromises: [Promise<Void>]

        do {
            let destinations = try await AttachmentMultisend.prepareForSending(
                messageBody,
                to: conversations,
                db: SSKEnvironment.shared.databaseStorageRef,
                attachmentValidator: DependenciesBridge.shared.attachmentContentValidator
            )

            (preparedNonStoryMessages, nonStorySendPromises) = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                let preparedMessages = try destinations.map { destination in
                    return try messageBlock(destination, tx)
                }

                // We're sending a message to this thread, approve any pending message request
                destinations.forEach { destination in
                    ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                        destination.thread,
                        setDefaultTimerIfNecessary: true,
                        tx: tx
                    )
                }

                let sendPromises = preparedMessages.map {
                    ThreadUtil.enqueueMessagePromise(
                        message: $0,
                        transaction: tx
                    )
                }
                return (preparedMessages, sendPromises)
            }
        } catch let error {
            return .failure(.init(outgoingMessages: [], error: error))
        }

        let storyConversations = selectedConversations.filter { $0.outgoingMessageType == .storyMessage }
        let storySendResult = storySendBlock?(storyConversations)

        let preparedStoryMessages: [PreparedOutgoingMessage]
        do {
            preparedStoryMessages = try await storySendResult?.preparedPromise.awaitable() ?? []
        } catch let error {
            return .failure(.init(outgoingMessages: [], error: error))
        }

        let preparedMessages = preparedNonStoryMessages + preparedStoryMessages
        await MainActor.run {
            self.presentOrUpdateSendProgressSheet(outgoingMessages: preparedMessages)
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                nonStorySendPromises.forEach { promise in
                    taskGroup.addTask(operation: {
                        try await promise.awaitable()
                    })
                }
                taskGroup.addTask(operation: {
                    try await _ = storySendResult?.sentPromise.awaitable()
                })
                try await taskGroup.waitForAll()
            }
            return .success(())
        } catch let error {
            return .failure(.init(outgoingMessages: preparedMessages, error: error))
        }
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

    private func showSendFailure(error: SendError) {
        AssertIsOnMainThread()

        owsFailDebug("Error: \(error.error)")

        let cancelAction = ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ) { [weak self] _ in
            guard let self = self else { return }
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                for message in error.outgoingMessages {
                    // If we sent the message to anyone, mark it as failed
                    message.updateWithAllSendingRecipientsMarkedAsFailed(tx: transaction)
                }
            }
            self.shareViewDelegate?.shareViewWasCancelled()
        }

        let failureTitle = OWSLocalizedString("SHARE_EXTENSION_SENDING_FAILURE_TITLE", comment: "Alert title")

        if let untrustedIdentityError = error as? UntrustedIdentityError {
            let untrustedServiceId = untrustedIdentityError.serviceId
            let failureFormat = OWSLocalizedString(
                "SHARE_EXTENSION_FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_FORMAT",
                comment: "alert body when sharing file failed because of untrusted/changed identity keys"
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
                style: .default
            ) { [weak self] _ in
                guard let self = self else { return }

                // Confirm Identity
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    let identityManager = DependenciesBridge.shared.identityManager
                    let verificationState = identityManager.verificationState(
                        for: SignalServiceAddress(untrustedServiceId),
                        tx: transaction
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
                            tx: transaction
                        )
                    }
                }

                // Resend
                self.resendMessages(error.outgoingMessages)
            }
            actionSheet.addAction(confirmAction)

            presentActionSheetOnNavigationController(actionSheet)
        } else {
            let actionSheet = ActionSheetController(title: failureTitle)
            actionSheet.addAction(cancelAction)

            let retryAction = ActionSheetAction(title: CommonStrings.retryButton, style: .default) { [weak self] _ in
                self?.resendMessages(error.outgoingMessages)
            }
            actionSheet.addAction(retryAction)

            presentActionSheetOnNavigationController(actionSheet)
        }
    }

    func resendMessages(_ outgoingMessages: [PreparedOutgoingMessage]) {
        AssertIsOnMainThread()
        owsAssertDebug(outgoingMessages.count > 0)

        var promises = [Promise<Void>]()
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            for message in outgoingMessages {
                promises.append(SSKEnvironment.shared.messageSenderJobQueueRef.add(
                    .promise,
                    message: message,
                    transaction: transaction
                ))
            }
        }

        self.presentOrUpdateSendProgressSheet(outgoingMessages: outgoingMessages)
        Promise.when(fulfilled: promises).done {
            self.dismissSendProgressSheet {}
            self.shareViewDelegate?.shareViewWasCompleted()
        }.catch { error in
            self.dismissSendProgressSheet {
                self.showSendFailure(error: .init(outgoingMessages: outgoingMessages, error: error))
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
        // Check if the attachments are compatible with sending to stories.
        let storySelections = selection.conversations.compactMap({ $0 as? StoryConversationItem })
        if !storySelections.isEmpty, let attachments = attachments {
            let areImagesOrVideos = attachments.allSatisfy({ $0.isValidImage || $0.isValidVideo })
            let isTextMessage = attachments.count == 1 && attachments.first.map {
                $0.isConvertibleToTextMessage && $0.dataLength <= kOversizeTextMessageSizeThreshold
            } ?? false
            if !areImagesOrVideos && !isTextMessage {
                // Can't send to stories!
                storySelections.forEach { self.selection.remove($0) }
                self.updateUIForCurrentSelection(animated: false)
                self.tableView.reloadData()
                let vc = ConversationPickerFailedRecipientsSheet(
                    failedAttachments: attachments,
                    failedStoryConversationItems: storySelections,
                    remainingConversationItems: self.selection.conversations,
                    onApprove: { [weak self] in
                        guard
                            let strongSelf = self,
                            strongSelf.selection.conversations.isEmpty.negated
                        else {
                            return
                        }
                        strongSelf.conversationPickerDidCompleteSelection(strongSelf)
                    })
                self.present(vc, animated: true)
                return
            }
        }

        approve()
    }

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool {
        return true
    }

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController) {
        shareViewDelegate?.shareViewWasCancelled()
    }

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        return attachments?.isEmpty != false ? .loading : .next
    }

    func conversationPickerDidBeginEditingText() {}

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}

// MARK: -

extension SharingThreadPickerViewController: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?) {
        assert(messageBody?.text.nilIfEmpty != nil)

        approvalMessageBody = messageBody
        approvalLinkPreviewDraft = linkPreviewDraft

        send()
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
        approvedContactShare = contactShare
        send()
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
        self.approvalMessageBody = newMessageBody
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeViewOnceState isViewOnce: Bool) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?) {
        self.approvedAttachments = attachments
        self.approvalMessageBody = messageBody

        send()
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

    func attachmentApprovalMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        mentionCandidates
    }

    func attachmentApprovalMentionCacheInvalidationKey() -> String {
        return "\(mentionCandidates.hashValue)"
    }
}
