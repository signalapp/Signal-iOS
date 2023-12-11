//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import Foundation
import SignalUI

class SharingThreadPickerViewController: ConversationPickerViewController {

    weak var shareViewDelegate: ShareViewDelegate?

    /// It can take a while to fully process attachments, and until we do we aren't
    /// fully sure if the attachments are stories-compatible. To speed things up,
    /// we do some fast pre-checks and store the result here.
    /// True if these pre-checks determine all attachments are stories-compatible.
    /// Once this is set, we show stories forever, even if the attachments end up being
    /// incompatible, because it would be weird to have the stories destinations disappear.
    /// Instead, we show an error when actually sending if stories are selected.
    public var areAttachmentStoriesCompatPrecheck: Bool? {
        didSet {
            // If we've already processed attachments, ignore the setting.
            guard attachments == nil else {
                areAttachmentStoriesCompatPrecheck = nil
                return
            }
            updateStoriesState()
            updateApprovalMode()
        }
    }

    var attachments: [SignalAttachment]? {
        didSet {
            updateStoriesState()
            updateApprovalMode()
        }
    }

    private var isViewOnce = false {
        didSet {
            updateStoriesState()
        }
    }

    lazy var isTextMessage: Bool = {
        guard let attachments = attachments, attachments.count == 1, let attachment = attachments.first else { return false }
        return attachment.isConvertibleToTextMessage && attachment.dataLength < kOversizeTextMessageSizeThreshold
    }()

    lazy var isContactShare: Bool = {
        guard let attachments = attachments, attachments.count == 1, let attachment = attachments.first else { return false }
        return attachment.isConvertibleToContactShare
    }()

    var approvedAttachments: [SignalAttachment]?
    var approvedContactShare: ContactShareViewModel?
    var approvalMessageBody: MessageBody?
    var approvalLinkPreviewDraft: OWSLinkPreviewDraft?

    var outgoingMessages = AtomicArray<TSOutgoingMessage>(lock: .init())

    var mentionCandidates: [SignalServiceAddress] = []

    var selectedConversations: [ConversationItem] { selection.conversations }

    public init(shareViewDelegate: ShareViewDelegate) {
        self.shareViewDelegate = shareViewDelegate

        super.init(selection: ConversationPickerSelection())

        shouldBatchUpdateIdentityKeys = true
        pickerDelegate = self
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

    private func updateStoriesState() {
        if isViewOnce {
            sectionOptions.remove(.stories)
        } else {
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
            guard let cnContact = Contact.cnContact(withVCardData: firstAttachment.data) else {
                throw OWSAssertionError("Missing or invalid contact data for contact share attachment")
            }

            let contactShareRecord = OWSContact(cnContact: cnContact)
            var avatarImageData = contactsManager.avatarData(forCNContactId: cnContact.identifier)

            if avatarImageData == nil {
                let contact = Contact(systemContact: cnContact)
                for address in contact.registeredAddresses() {
                    guard let data = contactsManagerImpl.profileImageDataForAddress(
                        withSneakyTransaction: address
                    ) else { continue }
                    avatarImageData = data
                    contactShareRecord.isProfileAvatar = true
                    break
                }
            }

            let contactShare = ContactShareViewModel(contactShareRecord: contactShareRecord, avatarImageData: avatarImageData)
            let approvalView = ContactShareViewController(contactShare: contactShare)
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
        let dismissSendProgress = showSendProgress()
        firstly {
            tryToSend()
        }.done {
            dismissSendProgress {}
            self.shareViewDelegate?.shareViewWasCompleted()
        }.catch { error in
            dismissSendProgress { self.showSendFailure(error: error) }
        }
    }

    func tryToSend() -> Promise<Void> {
        outgoingMessages.removeAll()

        if isTextMessage {
            guard let body = approvalMessageBody, !body.text.isEmpty else {
                return Promise(error: OWSAssertionError("Missing body."))
            }

            let linkPreviewDraft = approvalLinkPreviewDraft

            let nonStorySendPromise = sendToOutgoingMessageThreads { thread in
                return firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
                    return self.databaseStorage.write { transaction in
                        let preparer = OutgoingMessagePreparer(
                            messageBody: body,
                            thread: thread,
                            editTarget: nil,
                            transaction: transaction
                        )
                        preparer.insertMessage(linkPreviewDraft: linkPreviewDraft, transaction: transaction)
                        self.outgoingMessages.append(preparer.unpreparedMessage)
                        return ThreadUtil.enqueueMessagePromise(
                            message: preparer.unpreparedMessage,
                            transaction: transaction
                        )
                    }
                }
            }

            // Send the text message to any selected story recipients
            // as a text story with default styling.
            let storyConversations = selectedConversations.filter { $0.outgoingMessageClass == OutgoingStoryMessage.self }
            let storySendPromise = StorySharing.sendTextStoryFromShareExtension(
                with: body,
                linkPreviewDraft: linkPreviewDraft,
                to: storyConversations,
                messagesReadyToSend: { messages in
                    self.outgoingMessages.append(contentsOf: messages)
                }
            )

            return Promise<Void>.when(fulfilled: [nonStorySendPromise, storySendPromise])
        } else if isContactShare {
            guard let contactShare = approvedContactShare else {
                return Promise(error: OWSAssertionError("Missing contactShare."))
            }

            return sendToOutgoingMessageThreads { thread in
                return firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
                    return self.databaseStorage.write { transaction in
                        let builder = TSOutgoingMessageBuilder(thread: thread)
                        builder.contactShare = contactShare.dbRecord
                        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                        builder.expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)
                        let message = builder.build(transaction: transaction)
                        message.anyInsert(transaction: transaction)
                        self.outgoingMessages.append(message)
                        return ThreadUtil.enqueueMessagePromise(
                            message: message,
                            transaction: transaction
                        )
                    }
                }
            }
        } else {
            guard let approvedAttachments = approvedAttachments else {
                return Promise(error: OWSAssertionError("Missing approvedAttachments."))
            }

            return sendToConversations { conversations in
                return AttachmentMultisend.sendApprovedMediaFromShareExtension(
                    conversations: conversations,
                    approvalMessageBody: self.approvalMessageBody,
                    approvedAttachments: approvedAttachments,
                    messagesReadyToSend: { messages in
                        self.outgoingMessages.append(contentsOf: messages)
                    }
                )
            }
        }
    }

    func showSendProgress() -> (((() -> Void)?) -> Void) {
        AssertIsOnMainThread()

        let actionSheet = ActionSheetController()

        let headerWithProgress = UIView()
        headerWithProgress.backgroundColor = Theme.actionSheetBackgroundColor
        headerWithProgress.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let progressLabel = UILabel()
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 0
        progressLabel.lineBreakMode = .byWordWrapping
        progressLabel.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        progressLabel.textColor = Theme.primaryTextColor
        progressLabel.text = OWSLocalizedString("SHARE_EXTENSION_SENDING_IN_PROGRESS_TITLE", comment: "Alert title")

        headerWithProgress.addSubview(progressLabel)
        progressLabel.autoPinWidthToSuperviewMargins()
        progressLabel.autoPinTopToSuperviewMargin()

        let progressView = UIProgressView(progressViewStyle: .default)
        headerWithProgress.addSubview(progressView)
        progressView.autoPinWidthToSuperviewMargins()
        progressView.autoPinEdge(.top, to: .bottom, of: progressLabel, withOffset: 8)
        progressView.autoPinBottomToSuperviewMargin()

        actionSheet.customHeader = headerWithProgress

        let cancelAction = ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel) { [weak self] _ in
            self?.shareViewDelegate?.shareViewWasCancelled()
        }
        actionSheet.addAction(cancelAction)

        presentActionSheetOnNavigationController(actionSheet)

        let progressFormat = OWSLocalizedString("SHARE_EXTENSION_SENDING_IN_PROGRESS_FORMAT",
                                               comment: "Send progress for share extension. Embeds {{ %1$@ number of attachments uploaded, %2$@ total number of attachments}}")

        var progressPerAttachment = [String: Float]()
        let observer = NotificationCenter.default.addObserver(
            forName: .attachmentUploadProgress,
            object: nil,
            queue: nil
        ) { notification in
            // We can safely show the progress for just the first message,
            // all the messages share the same attachment upload progress.
            guard let attachmentIds = self.outgoingMessages.first?.attachmentIds else { return }

            // Populate the initial progress for all attachments at 0
            if progressPerAttachment.isEmpty {
                progressPerAttachment = Dictionary(uniqueKeysWithValues: attachmentIds.map { ($0, 0) })
            }

            guard let notificationAttachmentId = notification.userInfo?[kAttachmentUploadAttachmentIDKey] as? String else {
                owsFailDebug("Missing notificationAttachmentId.")
                return
            }
            guard let progress = notification.userInfo?[kAttachmentUploadProgressKey] as? NSNumber else {
                owsFailDebug("Missing progress.")
                return
            }

            guard attachmentIds.contains(notificationAttachmentId) else { return }

            progressPerAttachment[notificationAttachmentId] = progress.floatValue

            // Attachments can upload in parallel, so we show the progress
            // of the average of all the individual attachment's progress.
            progressView.progress = progressPerAttachment.values.reduce(0, +) / Float(attachmentIds.count)

            // In order to indicate approximately how many attachments remain
            // to upload, we look at the number that have had their progress
            // reach 100%.
            let totalCompleted = progressPerAttachment.values.filter { $0 == 1 }.count

            progressLabel.text = String(
                format: progressFormat,
                OWSFormat.formatInt(min(totalCompleted + 1, attachmentIds.count)),
                OWSFormat.formatInt(attachmentIds.count)
            )
        }

        return { completion in
            NotificationCenter.default.removeObserver(observer)
            actionSheet.dismiss(animated: true, completion: completion)
        }
    }

    func sendToConversations(enqueueBlock: @escaping ([ConversationItem]) -> Promise<[TSThread]>) -> Promise<Void> {
        AssertIsOnMainThread()

        let conversations = self.selectedConversations

        return firstly {
            enqueueBlock(conversations)
        }.done { threads in
            for thread in threads {
                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)
            }
        }
    }

    func sendToOutgoingMessageThreads(enqueueBlock: @escaping (TSThread) -> Promise<Void>) -> Promise<Void> {
        AssertIsOnMainThread()

        let conversations = self.selectedConversations.filter { $0.outgoingMessageClass == TSOutgoingMessage.self }
        return firstly {
            self.threads(for: conversations)
        }.then { (threads: [TSThread]) -> Promise<Void> in
            var sendPromises = [Promise<Void>]()
            for thread in threads {
                sendPromises.append(enqueueBlock(thread))

                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)
            }
            return Promise.when(fulfilled: sendPromises)
        }
    }

    func threads(for conversationItems: [ConversationItem]) -> Promise<[TSThread]> {
        return firstly(on: DispatchQueue.sharedUserInteractive) {
            var threads: [TSThread] = []
            if !conversationItems.isEmpty {
                self.databaseStorage.write { transaction in
                    for conversation in conversationItems {
                        guard let thread = conversation.getOrCreateThread(transaction: transaction) else {
                            owsFailDebug("Missing thread for conversation")
                            continue
                        }
                        threads.append(thread)
                    }
                }
            }
            return threads
        }
    }

    func showSendFailure(error: Error) {
        AssertIsOnMainThread()

        owsFailDebug("Error: \(error)")

        let cancelAction = ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ) { [weak self] _ in
            guard let self = self else { return }
            self.databaseStorage.write { transaction in
                for message in self.outgoingMessages.get() {
                    // If we sent the message to anyone, mark it as failed
                    message.updateWithAllSendingRecipientsMarkedAsFailed(with: transaction)
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
            let displayName = self.contactsManager.displayName(for: SignalServiceAddress(untrustedServiceId))
            let failureMessage = String(format: failureFormat, displayName)

            let actionSheet = ActionSheetController(title: failureTitle, message: failureMessage)
            actionSheet.addAction(cancelAction)

            // Capture the identity key before showing the prompt about it.
            let identityKey = databaseStorage.read { tx in
                let identityManager = DependenciesBridge.shared.identityManager
                return identityManager.identityKey(for: SignalServiceAddress(untrustedServiceId), tx: tx.asV2Read)
            }

            let confirmAction = ActionSheetAction(
                title: SafetyNumberStrings.confirmSendButton,
                style: .default
            ) { [weak self] _ in
                guard let self = self else { return }

                // Confirm Identity
                self.databaseStorage.write { transaction in
                    let identityManager = DependenciesBridge.shared.identityManager
                    let verificationState = identityManager.verificationState(
                        for: SignalServiceAddress(untrustedServiceId),
                        tx: transaction.asV2Write
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
                            tx: transaction.asV2Write
                        )
                    }
                }

                // Resend
                self.resendMessages()
            }
            actionSheet.addAction(confirmAction)

            presentActionSheetOnNavigationController(actionSheet)
        } else {
            let actionSheet = ActionSheetController(title: failureTitle)
            actionSheet.addAction(cancelAction)

            let retryAction = ActionSheetAction(title: CommonStrings.retryButton, style: .default) { [weak self] _ in
                self?.resendMessages()
            }
            actionSheet.addAction(retryAction)

            presentActionSheetOnNavigationController(actionSheet)
        }
    }

    func resendMessages() {
        AssertIsOnMainThread()
        owsAssertDebug(outgoingMessages.count > 0)

        var promises = [Promise<Void>]()
        databaseStorage.write { transaction in
            for message in outgoingMessages.get() {
                promises.append(SSKEnvironment.shared.messageSenderJobQueueRef.add(
                    .promise,
                    message: message.asPreparer,
                    transaction: transaction
                ))
            }
        }

        let dismissSendProgress = showSendProgress()
        Promise.when(fulfilled: promises).done {
            dismissSendProgress {}
            self.shareViewDelegate?.shareViewWasCompleted()
        }.catch { error in
            dismissSendProgress { self.showSendFailure(error: error) }
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
                $0.isConvertibleToTextMessage && $0.dataLength < kOversizeTextMessageSizeThreshold
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

    func contactShareViewController(_ viewController: ContactShareViewController, didApproveContactShare contactShare: ContactShareViewModel) {
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
        self.isViewOnce = isViewOnce
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?) {
        self.approvedAttachments = attachments
        self.approvalMessageBody = messageBody

        send()
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
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
