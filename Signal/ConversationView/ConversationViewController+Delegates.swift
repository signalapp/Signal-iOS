//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
public import LibSignalClient
public import SignalServiceKit
public import SignalUI

extension ConversationViewController: AttachmentApprovalViewControllerDelegate {

    public func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didApproveAttachments approvedAttachments: ApprovedAttachments,
        messageBody: MessageBody?,
    ) {
        Task { @MainActor in
            await self.sendAttachments(
                approvedAttachments,
                messageBody: messageBody,
                from: attachmentApproval,
            )
        }
    }

    public func attachmentApprovalDidCancel() {
        dismiss(animated: true, completion: nil)
        self.popKeyBoard()
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                                   didChangeMessageBody newMessageBody: MessageBody?) {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            return
        }
        inputToolbar.setMessageBody(newMessageBody, animated: false)
    }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachmentApprovalItem: AttachmentApprovalItem) { }

    public func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) { }

    public func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeViewOnceState isViewOnce: Bool) { }
}

extension ConversationViewController: AttachmentApprovalViewControllerDataSource {

    public var attachmentApprovalTextInputContextIdentifier: String? { textInputContextIdentifier }

    public var attachmentApprovalRecipientNames: [String] {
        let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx) }
        return [displayName]
    }

    public func attachmentApprovalMentionableAcis(tx: DBReadTransaction) -> [Aci] {
        supportsMentions ? thread.recipientAddresses(with: tx).compactMap(\.aci) : []
    }

    public func attachmentApprovalMentionCacheInvalidationKey() -> String {
        return thread.uniqueId
    }
}

extension ConversationViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        switch presentationController.presentedViewController {
        case is GifPickerNavigationViewController, is UIDocumentPickerViewController:
            self.openAttachmentKeyboard()
        case let navigationController as OWSNavigationController:
            switch navigationController.viewControllers.first {
            case is ContactPickerViewController, is LocationPicker:
                self.openAttachmentKeyboard()
            default:
                break
            }
        default:
            break
        }
    }
}

// MARK: -

extension ConversationViewController: ContactPickerDelegate {

    public func contactPickerDidCancel(_: ContactPickerViewController) {
        dismiss(animated: true, completion: nil)
        self.openAttachmentKeyboard()
    }

    public func contactPicker(_ contactPicker: ContactPickerViewController, didSelect systemContact: SystemContact) {
        AssertIsOnMainThread()

        guard let cnContact = SSKEnvironment.shared.contactManagerRef.cnContact(withId: systemContact.cnContactId) else {
            owsFailDebug("Could not load system contact.")
            return
        }

        let contactShareDraft = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return ContactShareDraft.load(
                cnContact: cnContact,
                signalContact: systemContact,
                contactManager: SSKEnvironment.shared.contactManagerRef,
                phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef,
                profileManager: SSKEnvironment.shared.profileManagerRef,
                recipientManager: DependenciesBridge.shared.recipientManager,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                tx: tx
            )
        }

        let approveContactShare = ContactShareViewController(contactShareDraft: contactShareDraft)
        approveContactShare.shareDelegate = self
        guard let navigationController = contactPicker.navigationController else {
            owsFailDebug("Missing contactsPicker.navigationController.")
            return
        }
        navigationController.pushViewController(approveContactShare, animated: true)
    }

    public func contactPicker(_: ContactPickerViewController, didSelectMultiple systemContacts: [SystemContact]) {
        owsFailDebug("Multiple selection not allowed.")
        dismiss(animated: true, completion: nil)
    }

    public func contactPicker(_: ContactPickerViewController, shouldSelect systemContact: SystemContact) -> Bool {
        // Any reason to preclude contacts?
        return true
    }
}

// MARK: -

extension ConversationViewController: ContactShareViewControllerDelegate {

    public func contactShareViewController(_ viewController: ContactShareViewController, didApproveContactShare contactShare:
        ContactShareDraft) {
        dismiss(animated: true) {
            self.send(contactShareDraft: contactShare)
        }
    }

    public func contactShareViewControllerDidCancel(_ viewController: ContactShareViewController) {
        dismiss(animated: true, completion: nil)
    }

    public func titleForContactShareViewController(_ viewController: ContactShareViewController) -> String? {
        return nil
    }

    public func recipientsDescriptionForContactShareViewController(_ viewController: ContactShareViewController) -> String? {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            SSKEnvironment.shared.contactManagerRef.displayName(for: self.thread, transaction: transaction)
        }
    }

    public func approvalModeForContactShareViewController(_ viewController: ContactShareViewController) -> ApprovalMode {
        return .send
    }

    private func send(contactShareDraft: ContactShareDraft) {
        let thread = self.thread
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            let didAddToProfileWhitelist = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                thread,
                setDefaultTimerIfNecessary: true,
                tx: transaction
            )
            transaction.addSyncCompletion {
                Task { @MainActor in
                    ThreadUtil.enqueueMessage(withContactShare: contactShareDraft, thread: thread)
                    self.messageWasSent()

                    if didAddToProfileWhitelist {
                        self.ensureBannerState()
                    }
                }
            }
        }
    }
}

// MARK: -

extension ConversationViewController: ConversationHeaderViewDelegate {
    func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView) {
        AssertIsOnMainThread()

        showConversationSettings()
    }

    func didTapConversationHeaderViewAvatar(_ conversationHeaderView: ConversationHeaderView) {
        AssertIsOnMainThread()

        if conversationHeaderView.avatarView.configuration.hasStoriesToDisplay {
            let vc = StoryPageViewController(
                context: thread.storyContext,
                spoilerState: spoilerState
            )
            present(vc, animated: true)
        } else {
            showConversationSettings()
        }
    }
}

// MARK: -

extension ConversationViewController: ConversationInputTextViewDelegate {
    public func didAttemptAttachmentPaste() {
        // If trying to paste a sticker, forego anything async since
        // the pasteboard will be cleared as soon as paste() exits.
        if PasteboardAttachment.hasStickerAttachment() {
            do {
                self.didPasteAttachments([try PasteboardAttachment.loadPreviewableStickerAttachment()].compacted())
            } catch {
                self.showErrorAlert(attachmentError: error as? SignalAttachmentError)
            }
            return
        }

        ModalActivityIndicatorViewController.present(fromViewController: self, asyncBlock: { modal in
            do {
                let attachments = try await PasteboardAttachment.loadPreviewableAttachments()
                modal.dismiss {
                    // Note: attachment array might be nil at this point; that's fine.
                    self.didPasteAttachments(attachments)
                }
            } catch {
                modal.dismiss {
                    self.showErrorAlert(attachmentError: error as? SignalAttachmentError)
                }
            }
        })
    }

    func didPasteAttachments(_ attachments: [PreviewableAttachment]?) {
        AssertIsOnMainThread()

        guard let attachments, attachments.count > 0 else {
            owsFailDebug("Missing attachments")
            return
        }

        // If the thing we pasted is sticker-like, send it immediately
        // and render it borderless.
        if attachments.count == 1, let a = attachments.first, a.rawValue.isBorderless {
            Task {
                await self.sendAttachments(
                    ApprovedAttachments(nonViewOnceAttachments: [a], imageQuality: .standard),
                    messageBody: nil,
                    from: self,
                )
            }
        } else {
            dismissKeyBoard()
            showApprovalDialog(forAttachments: attachments)
        }
    }

    public func inputTextViewSendMessagePressed() {
        AssertIsOnMainThread()

        sendButtonPressed()
    }

    public func textViewDidChange(_ textView: UITextView) {
        AssertIsOnMainThread()

        if textView.text.strippedOrNil != nil {
            SSKEnvironment.shared.typingIndicatorsRef.didStartTypingOutgoingInput(inThread: thread)
        }
    }
}

// MARK: -

extension ConversationViewController: ConversationSearchControllerDelegate {
    public func didDismissSearchController(_ searchController: UISearchController) {
        AssertIsOnMainThread()

        // This method is called not only when the user taps "cancel" in the searchController, but also
        // called when the searchController was dismissed because we switched to another uiMode, like
        // "selection". We only want to revert to "normal" in the former case - when the user tapped
        // "cancel" in the search controller. Otherwise, if we're already in another mode, like
        // "selection", we want to stay in that mode.
        if uiMode == .search {
            uiMode = .normal
        }
    }

    public func conversationSearchController(_ conversationSearchController: ConversationSearchController,
                                             didUpdateSearchResults resultSet: ConversationScreenSearchResultSet?) {
        AssertIsOnMainThread()

        self.lastSearchedText = resultSet?.searchText
        loadCoordinator.enqueueReload()
    }

    public func conversationSearchController(
        _ conversationSearchController: ConversationSearchController,
        didSelectMessageId messageId: String
    ) {
        AssertIsOnMainThread()

        ensureInteractionLoadedThenScrollToInteraction(
            messageId,
            onScreenPercentage: 1,
            alignment: .centerIfNotEntirelyOnScreen,
            isAnimated: true
        )
    }
}

// MARK: -

extension ConversationViewController: ConversationCollectionViewDelegate {
    public func collectionViewWillChangeSize(from oldSize: CGSize, to newSize: CGSize) {
        AssertIsOnMainThread()

        // Do nothing.
    }

    public func collectionViewDidChangeSize(from oldSize: CGSize, to newSize: CGSize) {
        AssertIsOnMainThread()

        if oldSize.width != newSize.width {
            resetForSizeOrOrientationChange()
        }

        updateScrollingContent()
    }

    public func collectionViewWillAnimate() {
        AssertIsOnMainThread()

        scrollingAnimationDidStart()
    }

    public func collectionViewShouldRecognizeSimultaneously(with otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return otherGestureRecognizer == collectionViewContextMenuGestureRecognizer
    }

    public func scrollingAnimationDidStart() {
        AssertIsOnMainThread()

        // scrollingAnimationStartDate blocks landing of loads, so we must ensure
        // that it is always cleared in a timely way, even if the animation
        // is cancelled. Wait no more than N seconds.
        scrollingAnimationCompletionTimer?.invalidate()
        scrollingAnimationCompletionTimer = .scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.scrollingAnimationCompletionTimerDidFire()
        }
    }

    private func scrollingAnimationCompletionTimerDidFire() {
        AssertIsOnMainThread()

        Logger.warn("Scrolling animation did not complete in a timely way.")

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

        autoLoadMoreIfNecessary()

        performMessageHighlightAnimationIfNeeded()
   }

    func resetForSizeOrOrientationChange() {
        AssertIsOnMainThread()

        updateConversationStyle()
    }
}
