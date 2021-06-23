//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

extension ConversationViewController: AttachmentApprovalViewControllerDelegate {

    public func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        // no-op
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                                   didApproveAttachments attachments: [SignalAttachment],
                                   messageBody: MessageBody?) {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        tryToSendAttachments(attachments, messageBody: messageBody)
        inputToolbar.clearTextMessage(animated: false)
        dismiss(animated: true, completion: nil)
        // We always want to scroll to the bottom of the conversation after the local user
        // sends a message.
        scrollToBottomOfConversation(animated: false)
    }

    public func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        dismiss(animated: true, completion: nil)
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                                   didChangeMessageBody newMessageBody: MessageBody?) {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }
        inputToolbar.setMessageBody(newMessageBody, animated: false)
    }

    @objc
    public var attachmentApprovalTextInputContextIdentifier: String? { textInputContextIdentifier }

    @objc
    public var attachmentApprovalRecipientNames: [String] {
        [ Self.contactsManager.displayNameWithSneakyTransaction(thread: thread) ]
    }

    @objc
    public var attachmentApprovalMentionableAddresses: [SignalServiceAddress] {
        supportsMentions ? thread.recipientAddresses : []
    }
}

// MARK: -

extension ConversationViewController: ContactsPickerDelegate {

    @objc
    public func contactsPicker(_: ContactsPicker, contactFetchDidFail error: NSError) {
        AssertIsOnMainThread()

        Logger.verbose("Error: \(error)")

        dismiss(animated: true, completion: nil)
    }

    @objc
    public func contactsPickerDidCancel(_: ContactsPicker) {
        AssertIsOnMainThread()

        Logger.verbose("")

        dismiss(animated: true, completion: nil)
    }

    @objc
    public func contactsPicker(_ contactsPicker: ContactsPicker, didSelectContact contact: Contact) {
        AssertIsOnMainThread()
        owsAssertDebug(contact.cnContactId != nil)

        guard let cnContact = contactsManager.cnContact(withId: contact.cnContactId) else {
            owsFailDebug("Could not load system contact.")
            return
        }

        Logger.verbose("Contact: \(contact)")

        guard let contactShareRecord = OWSContacts.contact(forSystemContact: cnContact) else {
            owsFailDebug("Could not convert system contact.")
            return
        }

        var isProfileAvatar = false
        var avatarImageData: Data? = contactsManager.avatarData(forCNContactId: cnContact.identifier)
        for address in contact.registeredAddresses() {
            if avatarImageData != nil {
                break
            }
            avatarImageData = contactsManagerImpl.profileImageDataForAddress(withSneakyTransaction: address)
            if avatarImageData != nil {
                isProfileAvatar = true
            }
        }
        contactShareRecord.isProfileAvatar = isProfileAvatar

        let contactShare = ContactShareViewModel(contactShareRecord: contactShareRecord,
                                                 avatarImageData: avatarImageData)

        let approveContactShare = ContactShareApprovalViewController(contactShare: contactShare)
        approveContactShare.delegate = self
        guard let navigationController = contactsPicker.navigationController else {
            owsFailDebug("Missing contactsPicker.navigationController.")
            return
        }
        navigationController.pushViewController(approveContactShare, animated: true)
    }

    @objc
    public func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) {
        AssertIsOnMainThread()

        owsFailDebug("Contacts: \(contacts)")

        dismiss(animated: true, completion: nil)
    }

    @objc
    public func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool {
        AssertIsOnMainThread()

        // Any reason to preclude contacts?
        return true
    }
}

// MARK: -

extension ConversationViewController: ContactShareApprovalViewControllerDelegate {

    @objc
    public func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                                    didApproveContactShare contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        Logger.info("")

        dismiss(animated: true) {
            self.send(contactShare: contactShare)
        }
    }

    private func send(contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        Logger.verbose("Sending contact share.")

        let thread = self.thread
        Self.databaseStorage.asyncWrite { transaction in
            let didAddToProfileWhitelist = ThreadUtil.addThread(toProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer: thread,
                                                                transaction: transaction)

            // TODO - in line with QuotedReply and other message attachments, saving should happen as part of sending
            // preparation rather than duplicated here and in the SAE
            if let avatarImage = contactShare.avatarImage {
                contactShare.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
            }

            transaction.addAsyncCompletion {
                let message = ThreadUtil.enqueueMessage(withContactShare: contactShare.dbRecord, thread: thread)
                self.messageWasSent(message)

                if didAddToProfileWhitelist {
                    self.ensureBannerState()
                }
            }
        }
    }

    @objc
    public func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                                    didCancelContactShare contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        Logger.info("")

        dismiss(animated: true, completion: nil)
    }

    @objc
    public func contactApprovalCustomTitle(_ contactApproval: ContactShareApprovalViewController) -> String? {
        AssertIsOnMainThread()

        return nil
    }

    @objc
    public func contactApprovalRecipientsDescription(_ contactApproval: ContactShareApprovalViewController) -> String? {
        AssertIsOnMainThread()

        Logger.info("")

        return databaseStorage.read { transaction in
            Self.contactsManager.displayName(for: self.thread, transaction: transaction)
        }
    }

    @objc
    public func contactApprovalMode(_ contactApproval: ContactShareApprovalViewController) -> ApprovalMode {
        AssertIsOnMainThread()

        return .send
    }
}

// MARK: -

extension ConversationViewController: ContactShareViewHelperDelegate {
    @objc
    public func didCreateOrEditContact() {
        AssertIsOnMainThread()

        Logger.info("")

        self.dismiss(animated: true, completion: nil)
    }
}

// MARK: -

extension ConversationViewController: ConversationHeaderViewDelegate {
    @objc
    public func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView) {
        AssertIsOnMainThread()

        showConversationSettings()
    }
}

// MARK: -

extension ConversationViewController: ConversationInputTextViewDelegate {
    @objc
    public func didPasteAttachment(_ attachment: SignalAttachment?) {
        AssertIsOnMainThread()

        guard let attachment = attachment else {
            owsFailDebug("Missing attachment.")
            return
        }

        // If the thing we pasted is sticker-like, send it immediately
        // and render it borderless.
        if attachment.isBorderless {
            tryToSendAttachments([ attachment ], messageBody: nil)
        } else {
            showApprovalDialog(forAttachment: attachment)
        }
    }

    @objc
    public func inputTextViewSendMessagePressed() {
        AssertIsOnMainThread()

        sendButtonPressed()
    }

    @objc
    public func textViewDidChange(_ textView: UITextView) {
        AssertIsOnMainThread()

        if textView.text.strippedOrNil != nil {
            typingIndicatorsImpl.didStartTypingOutgoingInput(inThread: thread)
        }
    }
}

// MARK: -

extension ConversationViewController: ConversationSearchControllerDelegate {
    @objc
    public func didDismissSearchController(_ searchController: UISearchController) {
        AssertIsOnMainThread()

        Logger.verbose("")

        // This method is called not only when the user taps "cancel" in the searchController, but also
        // called when the searchController was dismissed because we switched to another uiMode, like
        // "selection". We only want to revert to "normal" in the former case - when the user tapped
        // "cancel" in the search controller. Otherwise, if we're already in another mode, like
        // "selection", we want to stay in that mode.
        if uiMode == .search {
            uiMode = .normal
        }
    }

    @objc
    public func conversationSearchController(_ conversationSearchController: ConversationSearchController,
                                             didUpdateSearchResults resultSet: ConversationScreenSearchResultSet?) {
        AssertIsOnMainThread()

        Logger.verbose("conversationScreenSearchResultSet: \(resultSet.debugDescription)")

        self.lastSearchedText = resultSet?.searchText
        loadCoordinator.enqueueReload()

        if let resultSet = resultSet {
            BenchManager.completeEvent(eventId: resultSet.searchText)
        }
    }

    @objc
    public func conversationSearchController(_ conversationSearchController: ConversationSearchController,
                                             didSelectMessageId messageId: String) {
        AssertIsOnMainThread()

        Logger.verbose("messageId: \(messageId)")

        ensureInteractionLoadedThenScrollToInteraction(messageId,
                                                       onScreenPercentage: 1,
                                                       alignment: .centerIfNotEntirelyOnScreen,
                                                       isAnimated: true)
        BenchManager.completeEvent(eventId: String(format: "Conversation Search Nav: \(messageId)"))
    }
}

// MARK: -

extension ConversationViewController: UIDocumentMenuDelegate {
    @objc
    public func documentMenu(_ documentMenu: UIDocumentMenuViewController,
                             didPickDocumentPicker documentPicker: UIDocumentPickerViewController) {
        AssertIsOnMainThread()

        documentPicker.delegate = self
        dismissKeyBoard()
        presentFormSheet(documentPicker, animated: true)
    }
}

// MARK: -

extension ConversationViewController: InputAccessoryViewPlaceholderDelegate {
    @objc
    public func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval,
                                                              animationCurve: UIView.AnimationCurve) {
        AssertIsOnMainThread()

        handleKeyboardStateChange(animationDuration: animationDuration,
                                  animationCurve: animationCurve)
    }

    @objc
    public func inputAccessoryPlaceholderKeyboardDidPresent() {
        AssertIsOnMainThread()

        updateBottomBarPosition()
        updateContentInsets(animated: false)
    }

    @objc
    public func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval,
                                                              animationCurve: UIView.AnimationCurve) {
        AssertIsOnMainThread()

        handleKeyboardStateChange(animationDuration: animationDuration,
                                  animationCurve: animationCurve)
    }

    @objc
    public func inputAccessoryPlaceholderKeyboardDidDismiss() {
        AssertIsOnMainThread()

        updateBottomBarPosition()
        updateContentInsets(animated: false)
    }

    @objc
    public func inputAccessoryPlaceholderKeyboardIsDismissingInteractively() {
        AssertIsOnMainThread()

        // No animation, just follow along with the keyboard.
        self.isDismissingInteractively = true
        updateBottomBarPosition()
        self.isDismissingInteractively = false
    }

    private func handleKeyboardStateChange(animationDuration: TimeInterval,
                                           animationCurve: UIView.AnimationCurve) {
        AssertIsOnMainThread()

        if let transitionCoordinator = self.transitionCoordinator,
           transitionCoordinator.isInteractive {
            return
        }

        if shouldAnimateKeyboardChanges, animationDuration > 0 {
            if hasViewDidAppearEverCompleted {
                // Make note of when the keyboard animation will block
                // loads from landing during the keyboard animation.
                // It isn't safe to block loads for long, so we cap
                // how long they will be blocked for.
                let keyboardAnimationBlockLoadInterval: TimeInterval = kSecondInterval * 1.0
                let animationCompletionDate = Date().addingTimeInterval(keyboardAnimationBlockLoadInterval)
                let lastKeyboardAnimationDate = Date().addingTimeInterval(-1.0)
                if viewState.lastKeyboardAnimationDate == nil ||
                    viewState.lastKeyboardAnimationDate?.isBefore(lastKeyboardAnimationDate) == true {
                    viewState.lastKeyboardAnimationDate = animationCompletionDate
                }
            }

            // The animation curve provided by the keyboard notifications
            // is a private value not represented in UIViewAnimationOptions.
            // We don't use a block based animation here because it's not
            // possible to pass a curve directly to block animations.
            UIView.beginAnimations("keyboardStateChange", context: nil)
            UIView.setAnimationBeginsFromCurrentState(true)
            UIView.setAnimationCurve(animationCurve)
            UIView.setAnimationDuration(animationDuration)
            updateBottomBarPosition()
            UIView.commitAnimations()
            updateContentInsets(animated: true)
        } else {
            updateBottomBarPosition()
            updateContentInsets(animated: false)
        }
    }
}

// MARK: -

extension ConversationViewController: ConversationCollectionViewDelegate {
    @objc
    public func collectionViewWillChangeSize(from oldSize: CGSize, to newSize: CGSize) {
        AssertIsOnMainThread()

        // Do nothing.
    }

    @objc
    public func collectionViewDidChangeSize(from oldSize: CGSize, to newSize: CGSize) {
        AssertIsOnMainThread()

        if oldSize.width != newSize.width {
            resetForSizeOrOrientationChange()
        }

        updateScrollingContent()
    }

    @objc
    public func collectionViewWillAnimate() {
        AssertIsOnMainThread()

        scrollingAnimationDidStart()
    }

    @objc
    public func scrollingAnimationDidStart() {
        AssertIsOnMainThread()

        // scrollingAnimationStartDate blocks landing of loads, so we must ensure
        // that it is always cleared in a timely way, even if the animation
        // is cancelled. Wait no more than N seconds.
        scrollingAnimationCompletionTimer?.invalidate()
        scrollingAnimationCompletionTimer = Timer.weakScheduledTimer(withTimeInterval: 5,
                                                                     target: self,
                                                                     selector: #selector(scrollingAnimationCompletionTimerDidFire),
                                                                     userInfo: nil,
                                                                     repeats: false)
    }

    @objc
    private func scrollingAnimationCompletionTimerDidFire(_ timer: Timer) {
        AssertIsOnMainThread()

        owsFailDebug("Scrolling animation did not complete in a timely way.")

        // scrollingAnimationCompletionTimer should already have been cleared,
        // but we need to ensure that it is cleared in a timely way.
        scrollingAnimationDidComplete()
    }
}

// MARK: -

extension ConversationViewController {
    func scrollingAnimationDidComplete() {
        AssertIsOnMainThread()

        scrollingAnimationCompletionTimer?.invalidate()
        scrollingAnimationCompletionTimer = nil

        _ = autoLoadMoreIfNecessary()
    }

    func resetForSizeOrOrientationChange() {
        AssertIsOnMainThread()

        updateConversationStyle()
    }
}
