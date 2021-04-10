//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import PromiseKit

// MARK: -

@objc
class SharingThreadPickerViewController: ConversationPickerViewController {

    weak var shareViewDelegate: ShareViewDelegate?

    var attachments: [SignalAttachment]? {
        didSet { updateApprovalMode() }
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

    var outgoingMessages = [TSOutgoingMessage]() {
        didSet { AssertIsOnMainThread() }
    }

    var selectedConversations: [ConversationItem] = []

    @objc
    public init(shareViewDelegate: ShareViewDelegate) {
        self.shareViewDelegate = shareViewDelegate
        super.init()
        delegate = self
    }

    public func presentActionSheetOnNavigationController(_ alert: ActionSheetController) {
        if let navigationController = shareViewDelegate?.shareViewNavigationController {
            navigationController.presentActionSheet(alert)
        } else {
            super.presentActionSheet(alert)
        }
    }
}

// MARK: - Approval

extension SharingThreadPickerViewController {

    func approve() {
        do {
            let vc = try buildApprovalViewController()
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
        selectedConversations.append(conversationItem)
        return try buildApprovalViewController()
    }

    func buildApprovalViewController() throws -> UIViewController {
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
            guard let cnContact = Contact.cnContact(withVCardData: firstAttachment.data),
                  let contactShareRecord = OWSContacts.contact(forSystemContact: cnContact) else {
                throw OWSAssertionError("Missing or invalid contact data for contact share attachment")
            }

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
            let approvalView = ContactShareApprovalViewController(contactShare: contactShare)
            approvalVC = approvalView
            approvalView.delegate = self

        } else {
            let approvalView = AttachmentApprovalViewController(options: .hasCancel, sendButtonImageName: "send-solid-24", attachmentApprovalItems: attachments.map { AttachmentApprovalItem(attachment: $0, canSave: false) })
            approvalVC = approvalView
            approvalView.approvalDelegate = self
        }

        return approvalVC
    }
}

// MARK: - Sending

extension SharingThreadPickerViewController {

    func send() {
        do {
            try tryToSend()
        } catch {
            shareViewDelegate?.shareViewFailed(error: error)
        }
    }

    func tryToSend() throws {
        outgoingMessages.removeAll()

        if isTextMessage {
            guard let body = approvalMessageBody, body.text.count > 0 else {
                throw OWSAssertionError("Missing body.")
            }

            let linkPreviewDraft = approvalLinkPreviewDraft

            sendToThreads { thread in
                let (promise, resolver) = Promise<Void>.pending()

                let message = self.databaseStorage.read { transaction in
                    return ThreadUtil.sendMessageNonDurably(
                        body: body,
                        thread: thread,
                        quotedReplyModel: nil,
                        linkPreviewDraft: linkPreviewDraft,
                        transaction: transaction
                    ) { error in
                        if let error = error {
                            resolver.reject(error)
                        } else {
                            resolver.fulfill(())
                        }
                    }
                }

                self.outgoingMessages.append(message)

                return promise
            }
        } else if isContactShare {
            guard let contactShare = approvedContactShare else {
                throw OWSAssertionError("Missing contactShare.")
            }

            sendToThreads { thread in
                let (promise, resolver) = Promise<Void>.pending()

                if let avatarImage = contactShare.avatarImage {
                    self.databaseStorage.write { transaction in
                        contactShare.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
                    }
                }

                let message = ThreadUtil.sendMessageNonDurably(
                    contactShare: contactShare.dbRecord,
                    thread: thread
                ) { error in
                    if let error = error {
                        resolver.reject(error)
                    } else {
                        resolver.fulfill(())
                    }
                }

                self.outgoingMessages.append(message)

                return promise
            }
        } else {
            guard let approvedAttachments = approvedAttachments else {
                throw OWSAssertionError("Missing approvedAttachments.")
            }

            sendToConversations { conversations in
                return AttachmentMultisend.sendApprovedMediaNonDurably(
                    conversations: conversations,
                    approvalMessageBody: self.approvalMessageBody,
                    approvedAttachments: approvedAttachments,
                    messagesReadyToSend: { messages in
                        DispatchQueue.main.async { self.outgoingMessages = messages }
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
        progressLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        progressLabel.textColor = Theme.primaryTextColor
        progressLabel.text = NSLocalizedString("SHARE_EXTENSION_SENDING_IN_PROGRESS_TITLE", comment: "Alert title")

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

        let progressFormat = NSLocalizedString("SHARE_EXTENSION_SENDING_IN_PROGRESS_FORMAT",
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

    func sendToConversations(enqueueBlock: @escaping ([ConversationItem]) -> Promise<[TSThread]>) {
        AssertIsOnMainThread()

        let dismissSendProgress = showSendProgress()
        let conversations = self.selectedConversationsForConversationPicker
        firstly {
            enqueueBlock(conversations)
        }.done { threads in
            for thread in threads {
                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
            }

            dismissSendProgress {}
            self.shareViewDelegate?.shareViewWasCompleted()
        }.catch { error in
            dismissSendProgress { self.showSendFailure(error: error) }
        }
    }

    func sendToThreads(enqueueBlock: @escaping (TSThread) -> Promise<Void>) {
        AssertIsOnMainThread()

        let dismissSendProgress = showSendProgress()
        let conversations = self.selectedConversationsForConversationPicker
        firstly {
            self.threads(for: conversations)
        }.then { (threads: [TSThread]) -> Promise<Void> in
            var sendPromises = [Promise<Void>]()
            for thread in threads {
                sendPromises.append(enqueueBlock(thread))

                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
            }
            return when(fulfilled: sendPromises)
        }.done {
            dismissSendProgress {}
            self.shareViewDelegate?.shareViewWasCompleted()
        }.catch { error in
            dismissSendProgress { self.showSendFailure(error: error) }
        }
    }

    func threads(for conversationItems: [ConversationItem]) -> Promise<[TSThread]> {
        return firstly(on: .sharedUserInteractive) {
            guard conversationItems.count > 0 else {
                throw OWSAssertionError("No recipients.")
            }

            var threads: [TSThread] = []

            self.databaseStorage.write { transaction in
                for conversation in conversationItems {
                    guard let thread = conversation.thread(transaction: transaction) else {
                        owsFailDebug("Missing thread for conversation")
                        continue
                    }
                    threads.append(thread)
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
                for message in self.outgoingMessages {
                    // If we sent the message to anyone, mark it as failed
                    message.updateWithAllSendingRecipientsMarkedAsFailed(withTansaction: transaction)
                }
            }
            self.shareViewDelegate?.shareViewWasCancelled()
        }

        let failureTitle = NSLocalizedString("SHARE_EXTENSION_SENDING_FAILURE_TITLE", comment: "Alert title")

        let nsError = error as NSError
        if nsError.domain == OWSSignalServiceKitErrorDomain, nsError.code == OWSErrorCode.untrustedIdentity.rawValue {
            guard let untrustedAddress = nsError.userInfo[OWSErrorRecipientAddressKey] as? SignalServiceAddress else {
                return owsFailDebug("Missing address")
            }

            let failureFormat = NSLocalizedString("SHARE_EXTENSION_FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_FORMAT",
                                                  comment: "alert body when sharing file failed because of untrusted/changed identity keys")
            let displayName = self.contactsManager.displayName(for: untrustedAddress)
            let failureMessage = String(format: failureFormat, displayName)

            let actionSheet = ActionSheetController(title: failureTitle, message: failureMessage)
            actionSheet.addAction(cancelAction)

            let confirmAction = ActionSheetAction(
                title: SafetyNumberStrings.confirmSendButton,
                style: .default
            ) { [weak self] _ in
                guard let self = self else { return }

                // Confirm Identity
                self.databaseStorage.write { transaction in
                    let verificationState = self.identityManager.verificationState(
                        for: untrustedAddress,
                        transaction: transaction
                    )
                    switch verificationState {
                    case .default:
                        // If we learned of a changed SN during send, then we've already recorded the new identity
                        // and there's nothing else we need to do for the resend to succeed.
                        // We don't want to redundantly set status to "default" because we would create a
                        // "You marked Alice as unverified" notice, which wouldn't make sense if Alice was never
                        // marked as "Verified".
                        Logger.info("recipient has acceptable verification status. Next send will succeed.")
                    case .noLongerVerified:
                        Logger.info("marked recipient: \(untrustedAddress) as default verification status.")
                        guard let indentityKey = self.identityManager.identityKey(
                            for: untrustedAddress,
                            transaction: transaction
                        ) else { return owsFailDebug("missing identity key") }

                        self.identityManager.setVerificationState(
                            .default,
                            identityKey: indentityKey,
                            address: untrustedAddress,
                            isUserInitiatedChange: true,
                            transaction: transaction
                        )
                    case .verified:
                        owsFailDebug("Unexpected state")
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
        owsAssertDebug(!outgoingMessages.isEmpty)

        var promises = [Promise<Void>]()
        for message in outgoingMessages {
            promises.append(messageSender.sendMessage(.promise, message.asPreparer))
        }

        let dismissSendProgress = showSendProgress()
        when(fulfilled: promises).done {
            dismissSendProgress {}
            self.shareViewDelegate?.shareViewWasCompleted()
        }.catch { error in
            dismissSendProgress { self.showSendFailure(error: error) }
        }
    }
}

// MARK: -

extension SharingThreadPickerViewController: ConversationPickerDelegate {
    var selectedConversationsForConversationPicker: [ConversationItem] {
        return selectedConversations
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didSelectConversation conversation: ConversationItem) {
        selectedConversations.append(conversation)
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didDeselectConversation conversation: ConversationItem) {
        selectedConversations.removeAll { $0.messageRecipient == conversation.messageRecipient }
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
        return attachments?.isEmpty != false ? .loading : .next
    }
}

// MARK: -

extension SharingThreadPickerViewController: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?) {
        assert(messageBody?.text.count ?? 0 > 0)

        approvalMessageBody = messageBody
        approvalLinkPreviewDraft = linkPreviewDraft

        send()
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        shareViewDelegate?.shareViewWasCancelled()
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

extension SharingThreadPickerViewController: ContactShareApprovalViewControllerDelegate {
    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didApproveContactShare contactShare: ContactShareViewModel) {
        approvedContactShare = contactShare

        send()
    }

    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didCancelContactShare contactShare: ContactShareViewModel) {
        shareViewDelegate?.shareViewWasCancelled()
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

extension SharingThreadPickerViewController: AttachmentApprovalViewControllerDelegate {

    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageBody newMessageBody: MessageBody?) {
        self.approvalMessageBody = newMessageBody
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

    var attachmentApprovalTextInputContextIdentifier: String? {
        return nil
    }

    var attachmentApprovalRecipientNames: [String] {
        selectedConversationsForConversationPicker.map { $0.title }
    }

    var attachmentApprovalMentionableAddresses: [SignalServiceAddress] {
        guard selectedConversationsForConversationPicker.count == 1,
              case .group(let groupThreadId) = selectedConversationsForConversationPicker.first?.messageRecipient,
              let groupThread = databaseStorage.uiRead(block: { transaction in
                return TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: transaction)
              }),
              Mention.threadAllowsMentionSend(groupThread) else { return [] }
        return groupThread.recipientAddresses
    }
}
