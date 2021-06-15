//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

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
