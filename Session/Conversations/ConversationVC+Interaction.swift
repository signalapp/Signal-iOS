// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import CoreServices
import Photos
import PhotosUI
import Sodium
import PromiseKit
import GRDB
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

extension ConversationVC:
    InputViewDelegate,
    MessageCellDelegate,
    ContextMenuActionDelegate,
    ScrollToBottomButtonDelegate,
    SendMediaNavDelegate,
    UIDocumentPickerDelegate,
    AttachmentApprovalViewControllerDelegate,
    GifPickerViewControllerDelegate
{
    @objc func handleTitleViewTapped() {
        // Don't take the user to settings for unapproved threads
        guard viewModel.threadData.threadRequiresApproval == false else { return }

        openSettings()
    }

    @objc func openSettings() {
        let settingsVC: OWSConversationSettingsViewController = OWSConversationSettingsViewController()
        settingsVC.configure(
            withThreadId: viewModel.threadData.threadId,
            threadName: viewModel.threadData.displayName,
            isClosedGroup: (viewModel.threadData.threadVariant == .closedGroup),
            isOpenGroup: (viewModel.threadData.threadVariant == .openGroup),
            isNoteToSelf: viewModel.threadData.threadIsNoteToSelf
        )
        settingsVC.conversationSettingsViewDelegate = self
        navigationController?.pushViewController(settingsVC, animated: true, completion: nil)
    }
    
    // MARK: - ScrollToBottomButtonDelegate

    func handleScrollToBottomButtonTapped() {
        // The table view's content size is calculated by the estimated height of cells,
        // so the result may be inaccurate before all the cells are loaded. Use this
        // to scroll to the last row instead.
        scrollToBottom(isAnimated: true)
    }
    
    // MARK: - Call
    
    @objc func startCall(_ sender: Any?) {
        guard SessionCall.isEnabled else { return }
        guard Storage.shared[.areCallsEnabled] else {
            let callPermissionRequestModal = CallPermissionRequestModal()
            self.navigationController?.present(callPermissionRequestModal, animated: true, completion: nil)
            return
        }
        
        requestMicrophonePermissionIfNeeded { }
        
        let threadId: String = self.viewModel.threadData.threadId
        
        guard AVAudioSession.sharedInstance().recordPermission == .granted else { return }
        guard self.viewModel.threadData.threadVariant == .contact else { return }
        guard AppEnvironment.shared.callManager.currentCall == nil else { return }
        guard let call: SessionCall = Storage.shared.read({ db in SessionCall(db, for: threadId, uuid: UUID().uuidString.lowercased(), mode: .offer, outgoing: true) }) else {
            return
        }
        
        let callVC = CallVC(for: call)
        callVC.conversationVC = self
        hideInputAccessoryView()
        
        present(callVC, animated: true, completion: nil)
    }

    // MARK: - Blocking
    
    @objc func unblock() {
        self.showBlockedModalIfNeeded()
    }

    @discardableResult func showBlockedModalIfNeeded() -> Bool {
        guard self.viewModel.threadData.threadIsBlocked == true else { return false }
        
        let blockedModal = BlockedModal(publicKey: viewModel.threadData.threadId)
        blockedModal.modalPresentationStyle = .overFullScreen
        blockedModal.modalTransitionStyle = .crossDissolve
        present(blockedModal, animated: true, completion: nil)
        
        return true
    }

    // MARK: - SendMediaNavDelegate

    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
        dismiss(animated: true, completion: nil)
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], forThreadId threadId: String, messageText: String?) {
        sendAttachments(attachments, with: messageText ?? "")
        self.snInputView.text = ""
        resetMentions()
        dismiss(animated: true) { }
    }

    func sendMediaNavInitialMessageText(_ sendMediaNavigationController: SendMediaNavigationController) -> String? {
        return snInputView.text
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageText newMessageText: String?) {
        snInputView.text = (newMessageText ?? "")
    }

    // MARK: - AttachmentApprovalViewControllerDelegate
    
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], forThreadId threadId: String, messageText: String?) {
        sendAttachments(attachments, with: messageText ?? "") { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }

        scrollToBottom(isAnimated: false)
        self.snInputView.text = ""
        resetMentions()
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        dismiss(animated: true, completion: nil)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
        snInputView.text = newMessageText ?? ""
    }
    
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
    }

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
    }

    // MARK: - ExpandingAttachmentsButtonDelegate

    func handleGIFButtonTapped() {
        let gifVC = GifPickerViewController()
        gifVC.delegate = self
        
        let navController = OWSNavigationController(rootViewController: gifVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true) { }
    }

    func handleDocumentButtonTapped() {
        // UIDocumentPickerModeImport copies to a temp file within our container.
        // It uses more memory than "open" but lets us avoid working with security scoped URLs.
        let documentPickerVC = UIDocumentPickerViewController(documentTypes: [ kUTTypeItem as String ], in: UIDocumentPickerMode.import)
        documentPickerVC.delegate = self
        documentPickerVC.modalPresentationStyle = .fullScreen
        SNAppearance.switchToDocumentPickerAppearance()
        present(documentPickerVC, animated: true, completion: nil)
    }
    
    func handleLibraryButtonTapped() {
        let threadId: String = self.viewModel.threadData.threadId
        
        requestLibraryPermissionIfNeeded { [weak self] in
            DispatchQueue.main.async {
                let sendMediaNavController = SendMediaNavigationController.showingMediaLibraryFirst(
                    threadId: threadId
                )
                sendMediaNavController.sendMediaNavDelegate = self
                sendMediaNavController.modalPresentationStyle = .fullScreen
                self?.present(sendMediaNavController, animated: true, completion: nil)
            }
        }
    }
    
    func handleCameraButtonTapped() {
        guard requestCameraPermissionIfNeeded() else { return }
        
        requestMicrophonePermissionIfNeeded { }
        
        if AVAudioSession.sharedInstance().recordPermission != .granted {
            SNLog("Proceeding without microphone access. Any recorded video will be silent.")
        }
        
        let sendMediaNavController = SendMediaNavigationController.showingCameraFirst(threadId: self.viewModel.threadData.threadId)
        sendMediaNavController.sendMediaNavDelegate = self
        sendMediaNavController.modalPresentationStyle = .fullScreen
        
        present(sendMediaNavController, animated: true, completion: nil)
    }
    
    // MARK: - GifPickerViewControllerDelegate
    
    func gifPickerDidSelect(attachment: SignalAttachment) {
        showAttachmentApprovalDialog(for: [ attachment ])
    }
    
    // MARK: - UIDocumentPickerDelegate

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        SNAppearance.switchToSessionAppearance() // Switch back to the correct appearance
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        SNAppearance.switchToSessionAppearance()
        guard let url = urls.first else { return } // TODO: Handle multiple?
        
        let urlResourceValues: URLResourceValues
        do {
            urlResourceValues = try url.resourceValues(forKeys: [ .typeIdentifierKey, .isDirectoryKey, .nameKey ])
        }
        catch {
            DispatchQueue.main.async { [weak self] in
                let alert = UIAlertController(title: "Session", message: "An error occurred.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                
                self?.present(alert, animated: true, completion: nil)
            }
            return
        }
        
        let type = urlResourceValues.typeIdentifier ?? (kUTTypeData as String)
        guard urlResourceValues.isDirectory != true else {
            DispatchQueue.main.async {
                OWSAlerts.showAlert(
                    title: "ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE".localized(),
                    message: "ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY".localized()
                )
            }
            return
        }
        
        let fileName = urlResourceValues.name ?? NSLocalizedString("ATTACHMENT_DEFAULT_FILENAME", comment: "")
        guard let dataSource = DataSourcePath.dataSource(with: url, shouldDeleteOnDeallocation: false) else {
            DispatchQueue.main.async {
                OWSAlerts.showAlert(title: "ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE".localized())
            }
            return
        }
        dataSource.sourceFilename = fileName
        
        // Although we want to be able to send higher quality attachments through the document picker
        // it's more imporant that we ensure the sent format is one all clients can accept (e.g. *not* quicktime .mov)
        guard !SignalAttachment.isInvalidVideo(dataSource: dataSource, dataUTI: type) else {
            return showAttachmentApprovalDialogAfterProcessingVideo(at: url, with: fileName)
        }
        
        // "Document picker" attachments _SHOULD NOT_ be resized
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: type, imageQuality: .original)
        showAttachmentApprovalDialog(for: [ attachment ])
    }

    func showAttachmentApprovalDialog(for attachments: [SignalAttachment]) {
        let navController = AttachmentApprovalViewController.wrappedInNavController(
            threadId: self.viewModel.threadData.threadId,
            attachments: attachments,
            approvalDelegate: self
        )
        
        present(navController, animated: true, completion: nil)
    }

    func showAttachmentApprovalDialogAfterProcessingVideo(at url: URL, with fileName: String) {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: true, message: nil) { [weak self] modalActivityIndicator in
            let dataSource = DataSourcePath.dataSource(with: url, shouldDeleteOnDeallocation: false)!
            dataSource.sourceFilename = fileName
            
            SignalAttachment
                .compressVideoAsMp4(
                    dataSource: dataSource,
                    dataUTI: kUTTypeMPEG4 as String
                )
                .attachmentPromise
                .done { attachment in
                    guard
                        !modalActivityIndicator.wasCancelled,
                        let attachment = attachment as? SignalAttachment
                    else { return }
                    
                    modalActivityIndicator.dismiss {
                        guard !attachment.hasError else {
                            self?.showErrorAlert(for: attachment, onDismiss: nil)
                            return
                        }
                        
                        self?.showAttachmentApprovalDialog(for: [ attachment ])
                    }
                }
                .retainUntilComplete()
        }
    }
    
    // MARK: - InputViewDelegate

    // MARK: --Message Sending
    
    func handleSendButtonTapped() {
        sendMessage()
    }

    func sendMessage(hasPermissionToSendSeed: Bool = false) {
        guard !showBlockedModalIfNeeded() else { return }

        let text = replaceMentions(in: snInputView.text.trimmingCharacters(in: .whitespacesAndNewlines))
        
        guard !text.isEmpty else { return }

        if text.contains(mnemonic) && !viewModel.threadData.threadIsNoteToSelf && !hasPermissionToSendSeed {
            // Warn the user if they're about to send their seed to someone
            let modal = SendSeedModal()
            modal.modalPresentationStyle = .overFullScreen
            modal.modalTransitionStyle = .crossDissolve
            modal.proceed = { self.sendMessage(hasPermissionToSendSeed: true) }
            return present(modal, animated: true, completion: nil)
        }
        
        // Clearing this out immediately (even though it already happens in 'messageSent') to prevent
        // "double sending" if the user rapidly taps the send button
        DispatchQueue.main.async { [weak self] in
            self?.snInputView.text = ""
            self?.snInputView.quoteDraftInfo = nil

            self?.resetMentions()
        }

        // Note: 'shouldBeVisible' is set to true the first time a thread is saved so we can
        // use it to determine if the user is creating a new thread and update the 'isApproved'
        // flags appropriately
        let threadId: String = self.viewModel.threadData.threadId
        let oldThreadShouldBeVisible: Bool = (self.viewModel.threadData.threadShouldBeVisible == true)
        let sentTimestampMs: Int64 = Int64(floor((Date().timeIntervalSince1970 * 1000)))
        let linkPreviewDraft: LinkPreviewDraft? = snInputView.linkPreviewInfo?.draft
        let quoteModel: QuotedReplyModel? = snInputView.quoteDraftInfo?.model
        
        // If this was a message request then approve it
        approveMessageRequestIfNeeded(
            for: threadId,
            threadVariant: self.viewModel.threadData.threadVariant,
            isNewThread: !oldThreadShouldBeVisible,
            timestampMs: (sentTimestampMs - 1)  // Set 1ms earlier as this is used for sorting
        )
        
        // Send the message
        Storage.shared.writeAsync(
            updates: { [weak self] db in
                guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else {
                    return
                }
                
                // Let the viewModel know we are about to send a message
                self?.viewModel.sentMessageBeforeUpdate = true
                
                // Update the thread to be visible
                _ = try SessionThread
                    .filter(id: threadId)
                    .updateAll(db, SessionThread.Columns.shouldBeVisible.set(to: true))
                
                // Create the interaction
                let interaction: Interaction = try Interaction(
                    threadId: threadId,
                    authorId: getUserHexEncodedPublicKey(db),
                    variant: .standardOutgoing,
                    body: text,
                    timestampMs: sentTimestampMs,
                    hasMention: Interaction.isUserMentioned(db, threadId: threadId, body: text),
                    expiresInSeconds: try? DisappearingMessagesConfiguration
                        .select(.durationSeconds)
                        .filter(id: threadId)
                        .filter(DisappearingMessagesConfiguration.Columns.isEnabled == true)
                        .asRequest(of: TimeInterval.self)
                        .fetchOne(db),
                    linkPreviewUrl: linkPreviewDraft?.urlString
                ).inserted(db)
                
                // If there is a LinkPreview and it doesn't match an existing one then add it now
                if
                    let linkPreviewDraft: LinkPreviewDraft = linkPreviewDraft,
                    (try? interaction.linkPreview.isEmpty(db)) == true
                {
                    try LinkPreview(
                        url: linkPreviewDraft.urlString,
                        title: linkPreviewDraft.title,
                        attachmentId: LinkPreview.saveAttachmentIfPossible(
                            db,
                            imageData: linkPreviewDraft.jpegImageData,
                            mimeType: OWSMimeTypeImageJpeg
                        )
                    ).insert(db)
                }
                
                // If there is a Quote the insert it now
                if let interactionId: Int64 = interaction.id, let quoteModel: QuotedReplyModel = quoteModel {
                    try Quote(
                        interactionId: interactionId,
                        authorId: quoteModel.authorId,
                        timestampMs: quoteModel.timestampMs,
                        body: quoteModel.body,
                        attachmentId: quoteModel.generateAttachmentThumbnailIfNeeded(db)
                    ).insert(db)
                }
                
                try MessageSender.send(
                    db,
                    interaction: interaction,
                    in: thread
                )
            },
            completion: { [weak self] _, _ in
                self?.handleMessageSent()
            }
        )
    }

    func sendAttachments(_ attachments: [SignalAttachment], with text: String, onComplete: (() -> ())? = nil) {
        guard !showBlockedModalIfNeeded() else { return }
        
        for attachment in attachments {
            if attachment.hasError {
                return showErrorAlert(for: attachment, onDismiss: onComplete)
            }
        }
        
        let text = replaceMentions(in: snInputView.text.trimmingCharacters(in: .whitespacesAndNewlines))

        // Note: 'shouldBeVisible' is set to true the first time a thread is saved so we can
        // use it to determine if the user is creating a new thread and update the 'isApproved'
        // flags appropriately
        let threadId: String = self.viewModel.threadData.threadId
        let oldThreadShouldBeVisible: Bool = (self.viewModel.threadData.threadShouldBeVisible == true)
        let sentTimestampMs: Int64 = Int64(floor((Date().timeIntervalSince1970 * 1000)))

        // If this was a message request then approve it
        approveMessageRequestIfNeeded(
            for: threadId,
            threadVariant: self.viewModel.threadData.threadVariant,
            isNewThread: !oldThreadShouldBeVisible,
            timestampMs: (sentTimestampMs - 1)  // Set 1ms earlier as this is used for sorting
        )
        
        // Send the message
        Storage.shared.writeAsync(
            updates: { [weak self] db in
                guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else {
                    return
                }
                
                // Let the viewModel know we are about to send a message
                self?.viewModel.sentMessageBeforeUpdate = true
                
                // Update the thread to be visible
                _ = try SessionThread
                    .filter(id: threadId)
                    .updateAll(db, SessionThread.Columns.shouldBeVisible.set(to: true))
                
                // Create the interaction
                let interaction: Interaction = try Interaction(
                    threadId: threadId,
                    authorId: getUserHexEncodedPublicKey(db),
                    variant: .standardOutgoing,
                    body: text,
                    timestampMs: sentTimestampMs,
                    hasMention: Interaction.isUserMentioned(db, threadId: threadId, body: text),
                    expiresInSeconds: try? DisappearingMessagesConfiguration
                        .select(.durationSeconds)
                        .filter(id: threadId)
                        .filter(DisappearingMessagesConfiguration.Columns.isEnabled == true)
                        .asRequest(of: TimeInterval.self)
                        .fetchOne(db)
                ).inserted(db)

                try MessageSender.send(
                    db,
                    interaction: interaction,
                    with: attachments,
                    in: thread
                )
            },
            completion: { [weak self] _, _ in
                self?.handleMessageSent()
                
                // Attachment successfully sent - dismiss the screen
                DispatchQueue.main.async {
                    onComplete?()
                }
            }
        )
    }

    func handleMessageSent() {
        DispatchQueue.main.async { [weak self] in
            self?.snInputView.text = ""
            self?.snInputView.quoteDraftInfo = nil
            
            self?.resetMentions()
        }

        if Storage.shared[.playNotificationSoundInForeground] {
            let soundID = Preferences.Sound.systemSoundId(for: .messageSent, quiet: true)
            AudioServicesPlaySystemSound(soundID)
        }
        
        let threadId: String = self.viewModel.threadData.threadId
        
        Storage.shared.writeAsync { db in
            TypingIndicators.didStopTyping(db, threadId: threadId, direction: .outgoing)
            
            _ = try SessionThread
                .filter(id: threadId)
                .updateAll(db, SessionThread.Columns.messageDraft.set(to: ""))
        }
    }

    func showLinkPreviewSuggestionModal() {
        let linkPreviewModel = LinkPreviewModal() { [weak self] in
            self?.snInputView.autoGenerateLinkPreview()
        }
        linkPreviewModel.modalPresentationStyle = .overFullScreen
        linkPreviewModel.modalTransitionStyle = .crossDissolve
        present(linkPreviewModel, animated: true, completion: nil)
    }
    
    func inputTextViewDidChangeContent(_ inputTextView: InputTextView) {
        let newText: String = (inputTextView.text ?? "")
        
        if !newText.isEmpty {
            let threadId: String = self.viewModel.threadData.threadId
            let threadVariant: SessionThread.Variant = self.viewModel.threadData.threadVariant
            let threadIsMessageRequest: Bool = (self.viewModel.threadData.threadIsMessageRequest == true)
            let needsToStartTypingIndicator: Bool = TypingIndicators.didStartTypingNeedsToStart(
                threadId: threadId,
                threadVariant: threadVariant,
                threadIsMessageRequest: threadIsMessageRequest,
                direction: .outgoing,
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
            )
            
            if needsToStartTypingIndicator {
                Storage.shared.writeAsync { db in
                    TypingIndicators.start(db, threadId: threadId, direction: .outgoing)
                }
            }
        }
        
        updateMentions(for: newText)
    }
    
    // MARK: --Attachments
    
    func didPasteImageFromPasteboard(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else { return }
        
        let dataSource = DataSourceValue.dataSource(with: imageData, utiType: kUTTypeJPEG as String)
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeJPEG as String, imageQuality: .medium)

        let approvalVC = AttachmentApprovalViewController.wrappedInNavController(
            threadId: self.viewModel.threadData.threadId,
            attachments: [ attachment ],
            approvalDelegate: self
        )
        approvalVC.modalPresentationStyle = .fullScreen
        
        self.present(approvalVC, animated: true, completion: nil)
    }

    // MARK: --Mentions
    
    func handleMentionSelected(_ mentionInfo: ConversationViewModel.MentionInfo, from view: MentionSelectionView) {
        guard let currentMentionStartIndex = currentMentionStartIndex else { return }
        
        mentions.append(mentionInfo)
        
        let newText: String = snInputView.text.replacingCharacters(
            in: currentMentionStartIndex...,
            with: "@\(mentionInfo.profile.displayName(for: self.viewModel.threadData.threadVariant)) "
        )
        
        snInputView.text = newText
        self.currentMentionStartIndex = nil
        snInputView.hideMentionsUI()
        
        mentions = mentions.filter { mentionInfo -> Bool in
            newText.contains(mentionInfo.profile.displayName(for: self.viewModel.threadData.threadVariant))
        }
    }
    
    func updateMentions(for newText: String) {
        guard !newText.isEmpty else {
            if currentMentionStartIndex != nil {
                snInputView.hideMentionsUI()
            }
            
            resetMentions()
            return
        }
        
        let lastCharacterIndex = newText.index(before: newText.endIndex)
        let lastCharacter = newText[lastCharacterIndex]
        
        // Check if there is whitespace before the '@' or the '@' is the first character
        let isCharacterBeforeLastWhiteSpaceOrStartOfLine: Bool
        if newText.count == 1 {
            isCharacterBeforeLastWhiteSpaceOrStartOfLine = true // Start of line
        }
        else {
            let characterBeforeLast = newText[newText.index(before: lastCharacterIndex)]
            isCharacterBeforeLastWhiteSpaceOrStartOfLine = characterBeforeLast.isWhitespace
        }
        
        if lastCharacter == "@" && isCharacterBeforeLastWhiteSpaceOrStartOfLine {
            currentMentionStartIndex = lastCharacterIndex
            snInputView.showMentionsUI(for: self.viewModel.mentions())
        }
        else if lastCharacter.isWhitespace || lastCharacter == "@" { // the lastCharacter == "@" is to check for @@
            currentMentionStartIndex = nil
            snInputView.hideMentionsUI()
        }
        else {
            if let currentMentionStartIndex = currentMentionStartIndex {
                let query = String(newText[newText.index(after: currentMentionStartIndex)...]) // + 1 to get rid of the @
                snInputView.showMentionsUI(for: self.viewModel.mentions(for: query))
            }
        }
    }

    func resetMentions() {
        currentMentionStartIndex = nil
        mentions = []
    }

    func replaceMentions(in text: String) -> String {
        var result = text
        for mention in mentions {
            guard let range = result.range(of: "@\(mention.profile.displayName(for: mention.threadVariant))") else { continue }
            result = result.replacingCharacters(in: range, with: "@\(mention.profile.id)")
        }
        
        return result
    }
    
    func hideInputAccessoryView() {
        self.inputAccessoryView?.isHidden = true
        self.inputAccessoryView?.alpha = 0
    }
    
    func showInputAccessoryView() {
        UIView.animate(withDuration: 0.25, animations: {
            self.inputAccessoryView?.isHidden = false
            self.inputAccessoryView?.alpha = 1
        })
    }

    // MARK: MessageCellDelegate

    func handleItemLongPressed(_ cellViewModel: MessageViewModel) {
        // Show the context menu if applicable
        guard
            // FIXME: Need to update this when an appropriate replacement is added (see https://teng.pub/technical/2021/11/9/uiapplication-key-window-replacement)
            let keyWindow: UIWindow = UIApplication.shared.keyWindow,
            let sectionIndex: Int = self.viewModel.interactionData
                .firstIndex(where: { $0.model == .messages }),
            let index = self.viewModel.interactionData[sectionIndex]
                .elements
                .firstIndex(of: cellViewModel),
            let cell = tableView.cellForRow(at: IndexPath(row: index, section: sectionIndex)) as? VisibleMessageCell,
            let snapshot = cell.bubbleView.snapshotView(afterScreenUpdates: false),
            contextMenuWindow == nil,
            let actions: [ContextMenuVC.Action] = ContextMenuVC.actions(
                for: cellViewModel,
                recentEmojis: (self.viewModel.threadData.recentReactionEmoji ?? []).compactMap { EmojiWithSkinTones(rawValue: $0) },
                currentUserIsOpenGroupModerator: OpenGroupManager.isUserModeratorOrAdmin(
                    self.viewModel.threadData.currentUserPublicKey,
                    for: self.viewModel.threadData.openGroupRoomToken,
                    on: self.viewModel.threadData.openGroupServer
                ),
                currentThreadIsMessageRequest: (self.viewModel.threadData.threadIsMessageRequest == true),
                delegate: self
            )
        else { return }
        
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        self.contextMenuWindow = ContextMenuWindow()
        self.contextMenuVC = ContextMenuVC(
            snapshot: snapshot,
            frame: cell.convert(cell.bubbleView.frame, to: keyWindow),
            cellViewModel: cellViewModel,
            actions: actions
        ) { [weak self] in
            self?.contextMenuWindow?.isHidden = true
            self?.contextMenuVC = nil
            self?.contextMenuWindow = nil
            self?.scrollButton.alpha = 0
            
            UIView.animate(withDuration: 0.25) {
                self?.scrollButton.alpha = (self?.getScrollButtonOpacity() ?? 0)
                self?.unreadCountView.alpha = (self?.scrollButton.alpha ?? 0)
            }
        }
        
        self.contextMenuWindow?.backgroundColor = .clear
        self.contextMenuWindow?.rootViewController = self.contextMenuVC
        self.contextMenuWindow?.overrideUserInterfaceStyle = (isDarkMode ? .dark : .light)
        self.contextMenuWindow?.makeKeyAndVisible()
    }

    func handleItemTapped(_ cellViewModel: MessageViewModel, gestureRecognizer: UITapGestureRecognizer) {
        guard cellViewModel.variant != .standardOutgoing || cellViewModel.state != .failed else {
            // Show the failed message sheet
            showFailedMessageSheet(for: cellViewModel)
            return
        }
        
        // For call info messages show the "call missed" modal
        guard cellViewModel.variant != .infoCall else {
            let callMissedTipsModal: CallMissedTipsModal = CallMissedTipsModal(caller: cellViewModel.authorName)
            present(callMissedTipsModal, animated: true, completion: nil)
            return
        }
        
        // If it's an incoming media message and the thread isn't trusted then show the placeholder view
        if cellViewModel.cellType != .textOnlyMessage && cellViewModel.variant == .standardIncoming && !cellViewModel.threadIsTrusted {
            let modal = DownloadAttachmentModal(profile: cellViewModel.profile)
            modal.modalPresentationStyle = .overFullScreen
            modal.modalTransitionStyle = .crossDissolve
            
            present(modal, animated: true, completion: nil)
            return
        }
        
        switch cellViewModel.cellType {
            case .audio: viewModel.playOrPauseAudio(for: cellViewModel)
            
            case .mediaMessage:
                guard
                    let sectionIndex: Int = self.viewModel.interactionData
                        .firstIndex(where: { $0.model == .messages }),
                    let messageIndex: Int = self.viewModel.interactionData[sectionIndex]
                        .elements
                        .firstIndex(where: { $0.id == cellViewModel.id }),
                    let cell = tableView.cellForRow(at: IndexPath(row: messageIndex, section: sectionIndex)) as? VisibleMessageCell,
                    let albumView: MediaAlbumView = cell.albumView
                else { return }
                
                let locationInCell: CGPoint = gestureRecognizer.location(in: cell)
                
                // Figure out which of the media views was tapped
                let locationInAlbumView: CGPoint = cell.convert(locationInCell, to: albumView)
                guard let mediaView = albumView.mediaView(forLocation: locationInAlbumView) else { return }
                
                switch mediaView.attachment.state {
                    case .pendingDownload, .downloading, .uploading, .invalid: break
                    
                    // Failed uploads should be handled via the "resend" process instead
                    case .failedUpload: break
                        
                    case .failedDownload:
                        let threadId: String = self.viewModel.threadData.threadId
                        
                        // Retry downloading the failed attachment
                        Storage.shared.writeAsync { db in
                            JobRunner.add(
                                db,
                                job: Job(
                                    variant: .attachmentDownload,
                                    threadId: threadId,
                                    interactionId: cellViewModel.id,
                                    details: AttachmentDownloadJob.Details(
                                        attachmentId: mediaView.attachment.id
                                    )
                                )
                            )
                        }
                        break
                        
                    default:
                        // Ignore invalid media
                        guard mediaView.attachment.isValid else { return }
                        
                        let viewController: UIViewController? = MediaGalleryViewModel.createDetailViewController(
                            for: self.viewModel.threadData.threadId,
                            threadVariant: self.viewModel.threadData.threadVariant,
                            interactionId: cellViewModel.id,
                            selectedAttachmentId: mediaView.attachment.id,
                            options: [ .sliderEnabled, .showAllMediaButton ]
                        )
                        
                        if let viewController: UIViewController = viewController {
                            /// Delay becoming the first responder to make the return transition a little nicer (allows
                            /// for the footer on the detail view to slide out rather than instantly vanish)
                            self.delayFirstResponder = true
                            
                            /// Dismiss the input before starting the presentation to make everything look smoother
                            self.resignFirstResponder()
                            
                            /// Delay the actual presentation to give the 'resignFirstResponder' call the chance to complete
                            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                                /// Lock the contentOffset of the tableView so the transition doesn't look buggy
                                self?.tableView.lockContentOffset = true
                                
                                self?.present(viewController, animated: true) { [weak self] in
                                    // Unlock the contentOffset so everything will be in the right
                                    // place when we return
                                    self?.tableView.lockContentOffset = false
                                }
                            }
                        }
                }
                
            case .genericAttachment:
                guard
                    let attachment: Attachment = cellViewModel.attachments?.first,
                    let originalFilePath: String = attachment.originalFilePath
                else { return }
                
                let fileUrl: URL = URL(fileURLWithPath: originalFilePath)
                
                // Open a preview of the document for text, pdf or microsoft files
                if
                    attachment.isText ||
                    attachment.isMicrosoftDoc ||
                    attachment.contentType == OWSMimeTypeApplicationPdf
                {
                    
                    let interactionController: UIDocumentInteractionController = UIDocumentInteractionController(url: fileUrl)
                    interactionController.delegate = self
                    interactionController.presentPreview(animated: true)
                    return
                }
                
                // Otherwise share the file
                let shareVC = UIActivityViewController(activityItems: [ fileUrl ], applicationActivities: nil)
                
                if UIDevice.current.isIPad {
                    shareVC.excludedActivityTypes = []
                    shareVC.popoverPresentationController?.permittedArrowDirections = []
                    shareVC.popoverPresentationController?.sourceView = self.view
                    shareVC.popoverPresentationController?.sourceRect = self.view.bounds
                }
                
                navigationController?.present(shareVC, animated: true, completion: nil)
                
            case .textOnlyMessage:
                if let quote: Quote = cellViewModel.quote {
                    // Scroll to the original quoted message
                    let maybeOriginalInteractionId: Int64? = Storage.shared.read { db in
                        try quote.originalInteraction
                            .select(.id)
                            .asRequest(of: Int64.self)
                            .fetchOne(db)
                    }
                    
                    guard let interactionId: Int64 = maybeOriginalInteractionId else { return }
                    
                    self.scrollToInteractionIfNeeded(with: interactionId, highlight: true)
                }
                else if let linkPreview: LinkPreview = cellViewModel.linkPreview {
                    switch linkPreview.variant {
                        case .standard: openUrl(linkPreview.url)
                        case .openGroupInvitation: joinOpenGroup(name: linkPreview.title, url: linkPreview.url)
                    }
                }
                
            default: break
        }
    }
    
    func handleItemDoubleTapped(_ cellViewModel: MessageViewModel) {
        switch cellViewModel.cellType {
            // The user can double tap a voice message when it's playing to speed it up
            case .audio: self.viewModel.speedUpAudio(for: cellViewModel)
            default: break
        }
    }

    func handleItemSwiped(_ cellViewModel: MessageViewModel, state: SwipeState) {
        switch state {
            case .began: tableView.isScrollEnabled = false
            case .ended, .cancelled: tableView.isScrollEnabled = true
        }
    }
    
    func openUrl(_ urlString: String) {
        guard let url: URL = URL(string: urlString) else { return }
        
        // URLs can be unsafe, so always ask the user whether they want to open one
        let alertVC = UIAlertController.init(
            title: "modal_open_url_title".localized(),
            message: String(format: "modal_open_url_explanation".localized(), url.absoluteString),
            preferredStyle: .actionSheet
        )
        alertVC.addAction(UIAlertAction.init(title: "modal_open_url_button_title".localized(), style: .default) { [weak self] _ in
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            self?.showInputAccessoryView()
        })
        alertVC.addAction(UIAlertAction.init(title: "modal_copy_url_button_title".localized(), style: .default) { [weak self] _ in
            UIPasteboard.general.string = url.absoluteString
            self?.showInputAccessoryView()
        })
        alertVC.addAction(UIAlertAction.init(title: "cancel".localized(), style: .cancel) { [weak self] _ in
            self?.showInputAccessoryView()
        })
        
        self.presentAlert(alertVC)
    }
    
    func handleReplyButtonTapped(for cellViewModel: MessageViewModel) {
        reply(cellViewModel)
    }
    
    func showUserDetails(for profile: Profile) {
        let userDetailsSheet = UserDetailsSheet(for: profile)
        userDetailsSheet.modalPresentationStyle = .overFullScreen
        userDetailsSheet.modalTransitionStyle = .crossDissolve
        
        present(userDetailsSheet, animated: true, completion: nil)
    }
    
    func startThread(with sessionId: String, openGroupServer: String?, openGroupPublicKey: String?) {
        guard SessionId.Prefix(from: sessionId) == .blinded else {
            Storage.shared.write { db in
                try SessionThread.fetchOrCreate(db, id: sessionId, variant: .contact)
            }
            
            let conversationVC: ConversationVC = ConversationVC(threadId: sessionId, threadVariant: .contact)
                
            self.navigationController?.pushViewController(conversationVC, animated: true)
            return
        }
        
        // If the sessionId is blinded then check if there is an existing un-blinded thread with the contact
        // and use that, otherwise just use the blinded id
        guard let openGroupServer: String = openGroupServer, let openGroupPublicKey: String = openGroupPublicKey else {
            return
        }
        
        let targetThreadId: String? = Storage.shared.write { db in
            let lookup: BlindedIdLookup = try BlindedIdLookup
                .fetchOrCreate(
                    db,
                    blindedId: sessionId,
                    openGroupServer: openGroupServer,
                    openGroupPublicKey: openGroupPublicKey,
                    isCheckingForOutbox: false
                )
            
            return try SessionThread
                .fetchOrCreate(db, id: (lookup.sessionId ?? lookup.blindedId), variant: .contact)
                .id
        }
        
        guard let threadId: String = targetThreadId else { return }
        
        let conversationVC: ConversationVC = ConversationVC(threadId: threadId, threadVariant: .contact)
        self.navigationController?.pushViewController(conversationVC, animated: true)
    }
    
    func showReactionList(_ cellViewModel: MessageViewModel, selectedReaction: EmojiWithSkinTones?) {
        guard
            cellViewModel.reactionInfo?.isEmpty == false &&
            (
                self.viewModel.threadData.threadVariant == .closedGroup ||
                self.viewModel.threadData.threadVariant == .openGroup
            ),
            let allMessages: [MessageViewModel] = self.viewModel.interactionData
                .first(where: { $0.model == .messages })?
                .elements
        else { return }
        
        let reactionListSheet: ReactionListSheet = ReactionListSheet(for: cellViewModel.id) { [weak self] in
            self?.currentReactionListSheet = nil
        }
        reactionListSheet.delegate = self
        reactionListSheet.handleInteractionUpdates(
            allMessages,
            selectedReaction: selectedReaction,
            initialLoad: true,
            shouldShowClearAllButton: OpenGroupManager.isUserModeratorOrAdmin(
                self.viewModel.threadData.currentUserPublicKey,
                for: self.viewModel.threadData.openGroupRoomToken,
                on: self.viewModel.threadData.openGroupServer
            )
        )
        reactionListSheet.modalPresentationStyle = .overFullScreen
        present(reactionListSheet, animated: true, completion: nil)
        
        // Store so we can updated the content based on the current VC
        self.currentReactionListSheet = reactionListSheet
    }
    
    func needsLayout(for cellViewModel: MessageViewModel, expandingReactions: Bool) {
        guard
            let messageSectionIndex: Int = self.viewModel.interactionData
                .firstIndex(where: { $0.model == .messages }),
            let targetMessageIndex = self.viewModel.interactionData[messageSectionIndex]
                .elements
                .firstIndex(where: { $0.id == cellViewModel.id })
        else { return }
        
        if expandingReactions {
            self.viewModel.expandReactions(for: cellViewModel.id)
        }
        else {
            self.viewModel.collapseReactions(for: cellViewModel.id)
        }
        
        UIView.setAnimationsEnabled(false)
        tableView.reloadRows(
            at: [IndexPath(row: targetMessageIndex, section: messageSectionIndex)],
            with: .none
        )
        UIView.setAnimationsEnabled(true)
    }
    
    func react(_ cellViewModel: MessageViewModel, with emoji: EmojiWithSkinTones) {
        react(cellViewModel, with: emoji.rawValue, remove: false)
    }
    
    func removeReact(_ cellViewModel: MessageViewModel, for emoji: EmojiWithSkinTones) {
        react(cellViewModel, with: emoji.rawValue, remove: true)
    }
    
    func removeAllReactions(_ cellViewModel: MessageViewModel, for emoji: String) {
        guard cellViewModel.threadVariant == .openGroup else { return }
        
        Storage.shared
            .read { db -> Promise<Void> in
                guard
                    let openGroup: OpenGroup = try? OpenGroup
                        .fetchOne(db, id: cellViewModel.threadId),
                    let openGroupServerMessageId: Int64 = try? Interaction
                        .select(.openGroupServerMessageId)
                        .filter(id: cellViewModel.id)
                        .asRequest(of: Int64.self)
                        .fetchOne(db)
                else {
                    return Promise(error: StorageError.objectNotFound)
                }
                
                let pendingChange = OpenGroupManager
                    .addPendingReaction(
                        emoji: emoji,
                        id: openGroupServerMessageId,
                        in: openGroup.roomToken,
                        on: openGroup.server,
                        type: .removeAll
                    )
                
                return OpenGroupAPI
                    .reactionDeleteAll(
                        db,
                        emoji: emoji,
                        id: openGroupServerMessageId,
                        in: openGroup.roomToken,
                        on: openGroup.server
                    )
                    .map { _, response in
                        OpenGroupManager
                            .updatePendingChange(
                                pendingChange,
                                seqNo: response.seqNo
                            )
                    }
            }
            .done { _ in
                Storage.shared.writeAsync { db in
                    _ = try Reaction
                        .filter(Reaction.Columns.interactionId == cellViewModel.id)
                        .filter(Reaction.Columns.emoji == emoji)
                        .deleteAll(db)
                }
            }
            .retainUntilComplete()
    }
    
    func react(_ cellViewModel: MessageViewModel, with emoji: String, remove: Bool) {
        guard cellViewModel.variant == .standardIncoming || cellViewModel.variant == .standardOutgoing else {
            return
        }
        
        let threadIsMessageRequest: Bool = (self.viewModel.threadData.threadIsMessageRequest == true)
        guard !threadIsMessageRequest else { return }
        
        // Perform local rate limiting (don't allow more than 20 reactions within 60 seconds)
        let sentTimestamp: Int64 = Int64(floor(Date().timeIntervalSince1970 * 1000))
        let recentReactionTimestamps: [Int64] = General.cache.wrappedValue.recentReactionTimestamps
        
        guard
            recentReactionTimestamps.count < 20 ||
            (sentTimestamp - (recentReactionTimestamps.first ?? sentTimestamp)) > (60 * 1000)
        else { return }
        
        General.cache.mutate {
            $0.recentReactionTimestamps = Array($0.recentReactionTimestamps
                .suffix(19))
                .appending(sentTimestamp)
        }
        
        // Perform the sending logic
        Storage.shared.writeAsync(
            updates: { db in
                guard let thread: SessionThread = try SessionThread.fetchOne(db, id: cellViewModel.threadId) else {
                    return
                }
                
                // Update the thread to be visible
                _ = try SessionThread
                    .filter(id: thread.id)
                    .updateAll(db, SessionThread.Columns.shouldBeVisible.set(to: true))
                
                let pendingReaction: Reaction? = {
                    if remove {
                        return try? Reaction
                            .filter(Reaction.Columns.interactionId == cellViewModel.id)
                            .filter(Reaction.Columns.authorId == cellViewModel.currentUserPublicKey)
                            .filter(Reaction.Columns.emoji == emoji)
                            .fetchOne(db)
                    } else {
                        let sortId = Reaction.getSortId(
                            db,
                            interactionId: cellViewModel.id,
                            emoji: emoji
                        )
                        
                        return Reaction(
                            interactionId: cellViewModel.id,
                            serverHash: nil,
                            timestampMs: sentTimestamp,
                            authorId: cellViewModel.currentUserPublicKey,
                            emoji: emoji,
                            count: 1,
                            sortId: sortId
                        )
                    }
                }()
                
                // Update the database
                if remove {
                    try pendingReaction?.delete(db)
                }
                else {
                    try pendingReaction?.insert(db)
                    
                    // Add it to the recent list
                    Emoji.addRecent(db, emoji: emoji)
                }
                
                if let openGroup: OpenGroup = try? OpenGroup.fetchOne(db, id: cellViewModel.threadId),
                   OpenGroupManager.isOpenGroupSupport(.reactions, on: openGroup.server)
                {
                    // Send reaction to open groups
                    guard
                        let openGroupServerMessageId: Int64 = try? Interaction
                            .select(.openGroupServerMessageId)
                            .filter(id: cellViewModel.id)
                            .asRequest(of: Int64.self)
                            .fetchOne(db)
                    else { return }
                    
                    if remove {
                        let pendingChange = OpenGroupManager
                            .addPendingReaction(
                                emoji: emoji,
                                id: openGroupServerMessageId,
                                in: openGroup.roomToken,
                                on: openGroup.server,
                                type: .remove
                            )
                        OpenGroupAPI
                            .reactionDelete(
                                db,
                                emoji: emoji,
                                id: openGroupServerMessageId,
                                in: openGroup.roomToken,
                                on: openGroup.server
                            )
                            .map { _, response in
                                OpenGroupManager
                                    .updatePendingChange(
                                        pendingChange,
                                        seqNo: response.seqNo
                                    )
                            }
                            .catch { [weak self] _ in
                                OpenGroupManager.removePendingChange(pendingChange)
                                
                                self?.handleReactionSentFailure(
                                    pendingReaction,
                                    remove: remove
                                )
                                
                            }
                            .retainUntilComplete()
                    } else {
                        let pendingChange = OpenGroupManager
                            .addPendingReaction(
                                emoji: emoji,
                                id: openGroupServerMessageId,
                                in: openGroup.roomToken,
                                on: openGroup.server,
                                type: .add
                            )
                        OpenGroupAPI
                            .reactionAdd(
                                db,
                                emoji: emoji,
                                id: openGroupServerMessageId,
                                in: openGroup.roomToken,
                                on: openGroup.server
                            )
                            .map { _, response in
                                OpenGroupManager
                                    .updatePendingChange(
                                        pendingChange,
                                        seqNo: response.seqNo
                                    )
                            }
                            .catch { [weak self] _ in
                                OpenGroupManager.removePendingChange(pendingChange)
                                
                                self?.handleReactionSentFailure(
                                    pendingReaction,
                                    remove: remove
                                )
                            }
                            .retainUntilComplete()
                    }
                    
                } else {
                    // Send the actual message
                    try MessageSender.send(
                        db,
                        message: VisibleMessage(
                            sentTimestamp: UInt64(sentTimestamp),
                            text: nil,
                            reaction: VisibleMessage.VMReaction(
                                timestamp: UInt64(cellViewModel.timestampMs),
                                publicKey: {
                                    guard cellViewModel.variant == .standardIncoming else {
                                        return cellViewModel.currentUserPublicKey
                                    }
                                    
                                    return cellViewModel.authorId
                                }(),
                                emoji: emoji,
                                kind: (remove ? .remove : .react)
                            )
                        ),
                        interactionId: cellViewModel.id,
                        in: thread
                    )
                }
            }
        )
    }
    
    func handleReactionSentFailure(_ pendingReaction: Reaction?, remove: Bool) {
        Storage.shared.writeAsync { db in
            // Reverse the database
            if remove {
                try pendingReaction?.insert(db)
            }
            else {
                try pendingReaction?.delete(db)
            }
        }
    }
    
    func showFullEmojiKeyboard(_ cellViewModel: MessageViewModel) {
        hideInputAccessoryView()
        
        let emojiPicker = EmojiPickerSheet(
            completionHandler: { [weak self] emoji in
                guard let emoji: EmojiWithSkinTones = emoji else { return }
                
                self?.react(cellViewModel, with: emoji)
            },
            dismissHandler: { [weak self] in
                self?.showInputAccessoryView()
            }
        )
        emojiPicker.modalPresentationStyle = .overFullScreen
        present(emojiPicker, animated: true, completion: nil)
    }
    
    func contextMenuDismissed() {
        recoverInputView()
    }
    
    // MARK: --action handling
    
    func showFailedMessageSheet(for cellViewModel: MessageViewModel) {
        let sheet = UIAlertController(title: cellViewModel.mostRecentFailureText, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            Storage.shared.writeAsync { db in
                try Interaction
                    .filter(id: cellViewModel.id)
                    .deleteAll(db)
            }
        }))
        sheet.addAction(UIAlertAction(title: "Resend", style: .default, handler: { _ in
            Storage.shared.writeAsync { [weak self] db in
                guard
                    let threadId: String = self?.viewModel.threadData.threadId,
                    let interaction: Interaction = try? Interaction.fetchOne(db, id: cellViewModel.id),
                    let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId)
                else { return }
                
                try MessageSender.send(
                    db,
                    interaction: interaction,
                    in: thread
                )
            }
        }))
        
        // HACK: Extracting this info from the error string is pretty dodgy
        let prefix: String = "HTTP request failed at destination (Service node "
        if let mostRecentFailureText: String = cellViewModel.mostRecentFailureText, mostRecentFailureText.hasPrefix(prefix) {
            let rest = mostRecentFailureText.substring(from: prefix.count)
            
            if let index = rest.firstIndex(of: ")") {
                let snodeAddress = String(rest[rest.startIndex..<index])
                
                sheet.addAction(UIAlertAction(title: "Copy Service Node Info", style: .default) { _ in
                    UIPasteboard.general.string = snodeAddress
                })
            }
        }
        
        present(sheet, animated: true, completion: nil)
    }
    
    func joinOpenGroup(name: String?, url: String) {
        // Open groups can be unsafe, so always ask the user whether they want to join one
        let joinOpenGroupModal: JoinOpenGroupModal = JoinOpenGroupModal(name: name, url: url)
        joinOpenGroupModal.modalPresentationStyle = .overFullScreen
        joinOpenGroupModal.modalTransitionStyle = .crossDissolve
        
        present(joinOpenGroupModal, animated: true, completion: nil)
    }
    
    // MARK: - ContextMenuActionDelegate

    func reply(_ cellViewModel: MessageViewModel) {
        let maybeQuoteDraft: QuotedReplyModel? = QuotedReplyModel.quotedReplyForSending(
            threadId: self.viewModel.threadData.threadId,
            authorId: cellViewModel.authorId,
            variant: cellViewModel.variant,
            body: cellViewModel.body,
            timestampMs: cellViewModel.timestampMs,
            attachments: cellViewModel.attachments,
            linkPreviewAttachment: cellViewModel.linkPreviewAttachment
        )
        
        guard let quoteDraft: QuotedReplyModel = maybeQuoteDraft else { return }
        
        snInputView.quoteDraftInfo = (
            model: quoteDraft,
            isOutgoing: (cellViewModel.variant == .standardOutgoing)
        )
        snInputView.becomeFirstResponder()
    }

    func copy(_ cellViewModel: MessageViewModel) {
        switch cellViewModel.cellType {
            case .typingIndicator: break
            
            case .textOnlyMessage:
                UIPasteboard.general.string = cellViewModel.body
            
            case .audio, .genericAttachment, .mediaMessage:
                guard
                    cellViewModel.attachments?.count == 1,
                    let attachment: Attachment = cellViewModel.attachments?.first,
                    attachment.isValid,
                    (
                        attachment.state == .downloaded ||
                        attachment.state == .uploaded
                    ),
                    let utiType: String = MIMETypeUtil.utiType(forMIMEType: attachment.contentType),
                    let originalFilePath: String = attachment.originalFilePath,
                    let data: Data = try? Data(contentsOf: URL(fileURLWithPath: originalFilePath))
                else { return }
            
                UIPasteboard.general.setData(data, forPasteboardType: utiType)
        }
    }

    func copySessionID(_ cellViewModel: MessageViewModel) {
        guard cellViewModel.variant == .standardIncoming || cellViewModel.variant == .standardIncomingDeleted else {
            return
        }
        
        UIPasteboard.general.string = cellViewModel.authorId
    }

    func delete(_ cellViewModel: MessageViewModel) {
        // Only allow deletion on incoming and outgoing messages
        guard cellViewModel.variant == .standardIncoming || cellViewModel.variant == .standardOutgoing else {
            return
        }
        
        let threadId: String = self.viewModel.threadData.threadId
        let threadName: String = self.viewModel.threadData.displayName
        let userPublicKey: String = getUserHexEncodedPublicKey()
        
        // Remote deletion logic
        func deleteRemotely(from viewController: UIViewController?, request: Promise<Void>, onComplete: (() -> ())?) {
            // Show a loading indicator
            let (promise, seal) = Promise<Void>.pending()
            
            ModalActivityIndicatorViewController.present(fromViewController: viewController, canCancel: false) { _ in
                seal.fulfill(())
            }
            
            promise
                .then { _ -> Promise<Void> in request }
                .done { _ in
                    // Delete the interaction (and associated data) from the database
                    Storage.shared.writeAsync { db in
                        _ = try Interaction
                            .filter(id: cellViewModel.id)
                            .deleteAll(db)
                    }
                }
                .ensure {
                    DispatchQueue.main.async { [weak self] in
                        if self?.presentedViewController is ModalActivityIndicatorViewController {
                            self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                        }
                        
                        onComplete?()
                    }
                }
                .retainUntilComplete()
        }
        
        // How we delete the message differs depending on the type of thread
        switch cellViewModel.threadVariant {
            // Handle open group messages the old way
            case .openGroup:
                // If it's an incoming message the user must have moderator status
                let result: (openGroupServerMessageId: Int64?, openGroup: OpenGroup?)? = Storage.shared.read { db -> (Int64?, OpenGroup?) in
                    (
                        try Interaction
                            .select(.openGroupServerMessageId)
                            .filter(id: cellViewModel.id)
                            .asRequest(of: Int64.self)
                            .fetchOne(db),
                        try OpenGroup.fetchOne(db, id: threadId)
                    )
                }
                
                guard
                    let openGroup: OpenGroup = result?.openGroup,
                    let openGroupServerMessageId: Int64 = result?.openGroupServerMessageId, (
                        cellViewModel.variant != .standardIncoming ||
                        OpenGroupManager.isUserModeratorOrAdmin(
                            userPublicKey,
                            for: openGroup.roomToken,
                            on: openGroup.server
                        )
                    )
                else {
                    // If the message hasn't been sent yet then just delete locally
                    guard cellViewModel.state == .sending || cellViewModel.state == .failed else {
                        return
                    }
                    
                    // Retrieve any message send jobs for this interaction
                    let jobs: [Job] = Storage.shared
                        .read { db in
                            try? Job
                                .filter(Job.Columns.variant == Job.Variant.messageSend)
                                .filter(Job.Columns.interactionId == cellViewModel.id)
                                .fetchAll(db)
                        }
                        .defaulting(to: [])
                    
                    // If the job is currently running then wait until it's done before triggering
                    // the deletion
                    let targetJob: Job? = jobs.first(where: { JobRunner.isCurrentlyRunning($0) })
                    
                    guard targetJob == nil else {
                        JobRunner.afterCurrentlyRunningJob(targetJob) { [weak self] result in
                            switch result {
                                // If it succeeded then we'll need to delete from the server so re-run
                                // this function (if we still don't have the server id for some reason
                                // then this would result in a local-only deletion which should be fine
                                case .succeeded: self?.delete(cellViewModel)
                                    
                                // Otherwise we just need to cancel the pending job (in case it retries)
                                // and delete the interaction
                                default:
                                    JobRunner.removePendingJob(targetJob)
                                    
                                    Storage.shared.writeAsync { db in
                                        _ = try Interaction
                                            .filter(id: cellViewModel.id)
                                            .deleteAll(db)
                                    }
                            }
                        }
                        return
                    }
                    
                    // If it's not currently running then remove any pending jobs (just to be safe) and
                    // delete the interaction locally
                    jobs.forEach { JobRunner.removePendingJob($0) }
                    
                    Storage.shared.writeAsync { db in
                        _ = try Interaction
                            .filter(id: cellViewModel.id)
                            .deleteAll(db)
                    }
                    return
                }
                
                // Delete the message from the open group
                deleteRemotely(
                    from: self,
                    request: Storage.shared.read { db in
                        OpenGroupAPI.messageDelete(
                            db,
                            id: openGroupServerMessageId,
                            in: openGroup.roomToken,
                            on: openGroup.server
                        )
                        .map { _ in () }
                    }
                ) { [weak self] in
                    self?.showInputAccessoryView()
                }
                
            case .contact, .closedGroup:
                let serverHash: String? = Storage.shared.read { db -> String? in
                    try Interaction
                        .select(.serverHash)
                        .filter(id: cellViewModel.id)
                        .asRequest(of: String.self)
                        .fetchOne(db)
                }
                let unsendRequest: UnsendRequest = UnsendRequest(
                    timestamp: UInt64(cellViewModel.timestampMs),
                    author: (cellViewModel.variant == .standardOutgoing ?
                        userPublicKey :
                        cellViewModel.authorId
                    )
                )
                
                // For incoming interactions or interactions with no serverHash just delete them locally
                guard cellViewModel.variant == .standardOutgoing, let serverHash: String = serverHash else {
                    Storage.shared.writeAsync { db in
                        _ = try Interaction
                            .filter(id: cellViewModel.id)
                            .deleteAll(db)
                        
                        // No need to send the unsendRequest if there is no serverHash (ie. the message
                        // was outgoing but never got to the server)
                        guard serverHash != nil else { return }
                        
                        MessageSender
                            .send(
                                db,
                                message: unsendRequest,
                                threadId: threadId,
                                interactionId: nil,
                                to: .contact(publicKey: userPublicKey)
                            )
                    }
                    return
                }
                
                let alertVC = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
                alertVC.addAction(UIAlertAction(title: "delete_message_for_me".localized(), style: .destructive) { [weak self] _ in
                    Storage.shared.writeAsync { db in
                        _ = try Interaction
                            .filter(id: cellViewModel.id)
                            .deleteAll(db)
                        
                        MessageSender
                            .send(
                                db,
                                message: unsendRequest,
                                threadId: threadId,
                                interactionId: nil,
                                to: .contact(publicKey: userPublicKey)
                            )
                    }
                    self?.showInputAccessoryView()
                })
                
                alertVC.addAction(UIAlertAction(
                    title: (cellViewModel.threadVariant == .closedGroup ?
                        "delete_message_for_everyone".localized() :
                        String(format: "delete_message_for_me_and_recipient".localized(), threadName)
                    ),
                    style: .destructive
                ) { [weak self] _ in
                    deleteRemotely(
                        from: self,
                        request: SnodeAPI
                            .deleteMessage(
                                publicKey: threadId,
                                serverHashes: [serverHash]
                            )
                            .map { _ in () }
                    ) { [weak self] in
                        Storage.shared.writeAsync { db in
                            guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else {
                                return
                            }
                            
                            try MessageSender
                                .send(
                                    db,
                                    message: unsendRequest,
                                    interactionId: nil,
                                    in: thread
                                )
                        }
                        
                        self?.showInputAccessoryView()
                    }
                })

                alertVC.addAction(UIAlertAction.init(title: "TXT_CANCEL_TITLE".localized(), style: .cancel) { [weak self] _ in
                    self?.showInputAccessoryView()
                })

                self.inputAccessoryView?.isHidden = true
                self.inputAccessoryView?.alpha = 0
                self.presentAlert(alertVC)
        }
    }

    func save(_ cellViewModel: MessageViewModel) {
        guard cellViewModel.cellType == .mediaMessage else { return }
        
        let mediaAttachments: [(Attachment, String)] = (cellViewModel.attachments ?? [])
            .filter { attachment in
                attachment.isValid &&
                attachment.isVisualMedia && (
                    attachment.state == .downloaded ||
                    attachment.state == .uploaded
                )
            }
            .compactMap { attachment in
                guard let originalFilePath: String = attachment.originalFilePath else { return nil }
                
                return (attachment, originalFilePath)
            }
        
        guard !mediaAttachments.isEmpty else { return }
    
        mediaAttachments.forEach { attachment, originalFilePath in
            PHPhotoLibrary.shared().performChanges(
                {
                    if attachment.isImage || attachment.isAnimated {
                        PHAssetChangeRequest.creationRequestForAssetFromImage(
                            atFileURL: URL(fileURLWithPath: originalFilePath)
                        )
                    }
                    else if attachment.isVideo {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(
                            atFileURL: URL(fileURLWithPath: originalFilePath)
                        )
                    }
                },
                completionHandler: { _, _ in }
            )
        }
        
        // Send a 'media saved' notification if needed
        guard self.viewModel.threadData.threadVariant == .contact, cellViewModel.variant == .standardIncoming else {
            return
        }
        
        let threadId: String = self.viewModel.threadData.threadId
        
        Storage.shared.writeAsync { db in
            guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else { return }
            
            try MessageSender.send(
                db,
                message: DataExtractionNotification(
                    kind: .mediaSaved(timestamp: UInt64(cellViewModel.timestampMs))
                ),
                interactionId: nil,
                in: thread
            )
        }
    }

    func ban(_ cellViewModel: MessageViewModel) {
        guard cellViewModel.threadVariant == .openGroup else { return }
        
        let threadId: String = self.viewModel.threadData.threadId
        let alert: UIAlertController = UIAlertController(
            title: "Session",
            message: "This will ban the selected user from this room. It won't ban them from other rooms.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            Storage.shared
                .read { db -> Promise<Void> in
                    guard let openGroup: OpenGroup = try OpenGroup.fetchOne(db, id: threadId) else {
                        return Promise(error: StorageError.objectNotFound)
                    }
                    
                    return OpenGroupAPI
                        .userBan(
                            db,
                            sessionId: cellViewModel.authorId,
                            from: [openGroup.roomToken],
                            on: openGroup.server
                        )
                        .map { _ in () }
                }
                .catch(on: DispatchQueue.main) { _ in
                    OWSAlerts.showErrorAlert(message: "context_menu_ban_user_error_alert_message".localized())
                }
                .retainUntilComplete()
            
            self?.becomeFirstResponder()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { [weak self] _ in
            self?.becomeFirstResponder()
        }))
        
        present(alert, animated: true, completion: nil)
    }

    func banAndDeleteAllMessages(_ cellViewModel: MessageViewModel) {
        guard cellViewModel.threadVariant == .openGroup else { return }
        
        let threadId: String = self.viewModel.threadData.threadId
        let alert: UIAlertController = UIAlertController(
            title: "Session",
            message: "This will ban the selected user from this room and delete all messages sent by them. It won't ban them from other rooms or delete the messages they sent there.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            Storage.shared
                .read { db -> Promise<Void> in
                    guard let openGroup: OpenGroup = try OpenGroup.fetchOne(db, id: threadId) else {
                        return Promise(error: StorageError.objectNotFound)
                    }
                
                    return OpenGroupAPI
                        .userBanAndDeleteAllMessages(
                            db,
                            sessionId: cellViewModel.authorId,
                            in: openGroup.roomToken,
                            on: openGroup.server
                        )
                        .map { _ in () }
                }
                .catch(on: DispatchQueue.main) { _ in
                    OWSAlerts.showErrorAlert(message: "context_menu_ban_user_error_alert_message".localized())
                }
                .retainUntilComplete()
            
            self?.becomeFirstResponder()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { [weak self] _ in
            self?.becomeFirstResponder()
        }))
        
        present(alert, animated: true, completion: nil)
    }

    // MARK: - VoiceMessageRecordingViewDelegate

    func startVoiceMessageRecording() {
        // Request permission if needed
        requestMicrophonePermissionIfNeeded() { [weak self] in
            self?.cancelVoiceMessageRecording()
        }
        
        // Keep screen on
        UIApplication.shared.isIdleTimerDisabled = false
        guard AVAudioSession.sharedInstance().recordPermission == .granted else { return }
        
        // Cancel any current audio playback
        self.viewModel.stopAudio()
        
        // Create URL
        let directory: String = OWSTemporaryDirectory()
        let fileName: String = "\(Int64(floor(Date().timeIntervalSince1970 * 1000))).m4a"
        let url: URL = URL(fileURLWithPath: directory).appendingPathComponent(fileName)
        
        // Set up audio session
        let isConfigured = (Environment.shared?.audioSession.startAudioActivity(recordVoiceMessageActivity) == true)
        guard isConfigured else {
            return cancelVoiceMessageRecording()
        }
        
        // Set up audio recorder
        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
                    AVSampleRateKey: NSNumber(value: 44100),
                    AVNumberOfChannelsKey: NSNumber(value: 2),
                    AVEncoderBitRateKey: NSNumber(value: 128 * 1024)
                ]
            )
            audioRecorder.isMeteringEnabled = true
            self.audioRecorder = audioRecorder
        }
        catch {
            SNLog("Couldn't start audio recording due to error: \(error).")
            return cancelVoiceMessageRecording()
        }
        
        // Limit voice messages to a minute
        audioTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false, block: { [weak self] _ in
            self?.snInputView.hideVoiceMessageUI()
            self?.endVoiceMessageRecording()
        })
        
        // Prepare audio recorder
        guard audioRecorder.prepareToRecord() else {
            SNLog("Couldn't prepare audio recorder.")
            return cancelVoiceMessageRecording()
        }
        
        // Start recording
        guard audioRecorder.record() else {
            SNLog("Couldn't record audio.")
            return cancelVoiceMessageRecording()
        }
    }

    func endVoiceMessageRecording() {
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Hide the UI
        snInputView.hideVoiceMessageUI()
        
        // Cancel the timer
        audioTimer?.invalidate()
        
        // Check preconditions
        guard let audioRecorder = audioRecorder else { return }
        
        // Get duration
        let duration = audioRecorder.currentTime
        
        // Stop the recording
        stopVoiceMessageRecording()
        
        // Check for user misunderstanding
        guard duration > 1 else {
            self.audioRecorder = nil
            
            OWSAlerts.showAlert(
                title: "VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE".localized(),
                message: "VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE".localized()
            )
            return
        }
        
        // Get data
        let dataSourceOrNil = DataSourcePath.dataSource(with: audioRecorder.url, shouldDeleteOnDeallocation: true)
        self.audioRecorder = nil
        
        guard let dataSource = dataSourceOrNil else { return SNLog("Couldn't load recorded data.") }
        
        // Create attachment
        let fileName = ("VOICE_MESSAGE_FILE_NAME".localized() as NSString).appendingPathExtension("m4a")
        dataSource.sourceFilename = fileName
        
        let attachment = SignalAttachment.voiceMessageAttachment(dataSource: dataSource, dataUTI: kUTTypeMPEG4Audio as String)
        
        guard !attachment.hasError else {
            return showErrorAlert(for: attachment, onDismiss: nil)
        }
        
        // Send attachment
        sendAttachments([ attachment ], with: "")
    }

    func cancelVoiceMessageRecording() {
        snInputView.hideVoiceMessageUI()
        audioTimer?.invalidate()
        stopVoiceMessageRecording()
        audioRecorder = nil
    }

    func stopVoiceMessageRecording() {
        audioRecorder?.stop()
        Environment.shared?.audioSession.endAudioActivity(recordVoiceMessageActivity)
    }
    
    // MARK: - Permissions
    
    func requestCameraPermissionIfNeeded() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return true
            case .denied, .restricted:
                let modal = PermissionMissingModal(permission: "camera") { }
                modal.modalPresentationStyle = .overFullScreen
                modal.modalTransitionStyle = .crossDissolve
                present(modal, animated: true, completion: nil)
                return false
                
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { _ in })
                return false
                
            default: return false
        }
    }

    func requestMicrophonePermissionIfNeeded(onNotGranted: @escaping () -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: break
            case .denied:
                onNotGranted()
                let modal = PermissionMissingModal(permission: "microphone") {
                    onNotGranted()
                }
                modal.modalPresentationStyle = .overFullScreen
                modal.modalTransitionStyle = .crossDissolve
                present(modal, animated: true, completion: nil)
                
            case .undetermined:
                onNotGranted()
                AVAudioSession.sharedInstance().requestRecordPermission { _ in }
                
            default: break
        }
    }

    func requestLibraryPermissionIfNeeded(onAuthorized: @escaping () -> Void) {
        let authorizationStatus: PHAuthorizationStatus
        if #available(iOS 14, *) {
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if authorizationStatus == .notDetermined {
                // When the user chooses to select photos (which is the .limit status),
                // the PHPhotoUI will present the picker view on the top of the front view.
                // Since we have the ScreenLockUI showing when we request premissions,
                // the picker view will be presented on the top of the ScreenLockUI.
                // However, the ScreenLockUI will dismiss with the permission request alert view, so
                // the picker view then will dismiss, too. The selection process cannot be finished
                // this way. So we add a flag (isRequestingPermission) to prevent the ScreenLockUI
                // from showing when we request the photo library permission.
                Environment.shared?.isRequestingPermission = true
                let appMode = AppModeManager.shared.currentAppMode
                // FIXME: Rather than setting the app mode to light and then to dark again once we're done,
                // it'd be better to just customize the appearance of the image picker. There doesn't currently
                // appear to be a good way to do so though...
                AppModeManager.shared.setCurrentAppMode(to: .light)
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    DispatchQueue.main.async {
                        AppModeManager.shared.setCurrentAppMode(to: appMode)
                    }
                    Environment.shared?.isRequestingPermission = false
                    if [ PHAuthorizationStatus.authorized, PHAuthorizationStatus.limited ].contains(status) {
                        onAuthorized()
                    }
                }
            }
        } else {
            authorizationStatus = PHPhotoLibrary.authorizationStatus()
            if authorizationStatus == .notDetermined {
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        onAuthorized()
                    }
                }
            }
        }
        
        switch authorizationStatus {
            case .authorized, .limited:
                onAuthorized()
                
            case .denied, .restricted:
                let modal = PermissionMissingModal(permission: "library") { }
                modal.modalPresentationStyle = .overFullScreen
                modal.modalTransitionStyle = .crossDissolve
                present(modal, animated: true, completion: nil)
                
            default: return
        }
    }

    // MARK: - Convenience
    
    func showErrorAlert(for attachment: SignalAttachment, onDismiss: (() -> ())?) {
        OWSAlerts.showAlert(
            title: "ATTACHMENT_ERROR_ALERT_TITLE".localized(),
            message: (attachment.localizedErrorDescription ?? SignalAttachment.missingDataErrorMessage),
            buttonTitle: nil
        ) { _ in
            onDismiss?()
        }
    }
}

// MARK: - UIDocumentInteractionControllerDelegate

extension ConversationVC: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
}

// MARK: - Message Request Actions

extension ConversationVC {
    fileprivate func approveMessageRequestIfNeeded(
        for threadId: String,
        threadVariant: SessionThread.Variant,
        isNewThread: Bool,
        timestampMs: Int64
    ) {
        guard threadVariant == .contact else { return }

        // If the contact doesn't exist then we should create it so we can store the 'isApproved' state
        // (it'll be updated with correct profile info if they accept the message request so this
        // shouldn't cause weird behaviours)
        guard
            let approvalData: (contact: Contact, thread: SessionThread?) = Storage.shared.read({ db in
                return (
                    Contact.fetchOrCreate(db, id: threadId),
                    try SessionThread.fetchOne(db, id: threadId)
                )
            }),
            let thread: SessionThread = approvalData.thread,
            !approvalData.contact.isApproved
        else {
            return
        }
        
        Storage.shared.writeAsync(
            updates: { db in
                // If we aren't creating a new thread (ie. sending a message request) then send a
                // messageRequestResponse back to the sender (this allows the sender to know that
                // they have been approved and can now use this contact in closed groups)
                if !isNewThread {
                    try MessageSender.send(
                        db,
                        message: MessageRequestResponse(
                            isApproved: true,
                            sentTimestampMs: UInt64(timestampMs)
                        ),
                        interactionId: nil,
                        in: thread
                    )
                }
                
                // Default 'didApproveMe' to true for the person approving the message request
                try approvalData.contact
                    .with(
                        isApproved: true,
                        didApproveMe: .update(approvalData.contact.didApproveMe || !isNewThread)
                    )
                    .save(db)
                
                // Send a sync message with the details of the contact
                try MessageSender
                    .syncConfiguration(db, forceSyncNow: true)
                    .retainUntilComplete()
            },
            completion: { _, _ in
                // Remove the 'MessageRequestsViewController' from the nav hierarchy if present
                DispatchQueue.main.async { [weak self] in
                    if
                        let viewControllers: [UIViewController] = self?.navigationController?.viewControllers,
                        let messageRequestsIndex = viewControllers.firstIndex(where: { $0 is MessageRequestsViewController }),
                        messageRequestsIndex > 0
                    {
                        var newViewControllers = viewControllers
                        newViewControllers.remove(at: messageRequestsIndex)
                        self?.navigationController?.viewControllers = newViewControllers
                    }
                }
            }
        )
    }

    @objc func acceptMessageRequest() {
        self.approveMessageRequestIfNeeded(
            for: self.viewModel.threadData.threadId,
            threadVariant: self.viewModel.threadData.threadVariant,
            isNewThread: false,
            timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
        )
    }

    @objc func deleteMessageRequest() {
        guard self.viewModel.threadData.threadVariant == .contact else { return }
        
        let threadId: String = self.viewModel.threadData.threadId
        let alertVC: UIAlertController = UIAlertController(
            title: "MESSAGE_REQUESTS_DELETE_CONFIRMATION_ACTON".localized(),
            message: nil,
            preferredStyle: .actionSheet
        )
        alertVC.addAction(UIAlertAction(title: "TXT_DELETE_TITLE".localized(), style: .destructive) { _ in
            // Delete the request
            Storage.shared.writeAsync(
                updates: { db in
                    // Update the contact
                    _ = try Contact
                        .fetchOrCreate(db, id: threadId)
                        .with(
                            isApproved: false,
                            isBlocked: true,

                            // Note: We set this to true so the current user will be able to send a
                            // message to the person who originally sent them the message request in
                            // the future if they unblock them
                            didApproveMe: true
                        )
                        .saved(db)
                    
                    _ = try SessionThread
                        .filter(id: threadId)
                        .deleteAll(db)
                    
                    try MessageSender
                        .syncConfiguration(db, forceSyncNow: true)
                        .retainUntilComplete()
                },
                completion: { db, _ in
                    DispatchQueue.main.async { [weak self] in
                        self?.navigationController?.popViewController(animated: true)
                    }
                }
            )
        })
        alertVC.addAction(UIAlertAction(title: "TXT_CANCEL_TITLE".localized(), style: .cancel, handler: nil))
        
        self.present(alertVC, animated: true, completion: nil)
    }
}

// MARK: - MediaPresentationContextProvider

extension ConversationVC: MediaPresentationContextProvider {
    func mediaPresentationContext(mediaItem: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard case let .gallery(galleryItem) = mediaItem else { return nil }
        
        // Note: According to Apple's docs the 'indexPathsForVisibleRows' method returns an
        // unsorted array which means we can't use it to determine the desired 'visibleCell'
        // we are after, due to this we will need to iterate all of the visible cells to find
        // the one we want
        let maybeMessageCell: VisibleMessageCell? = tableView.visibleCells
            .first { cell -> Bool in
                ((cell as? VisibleMessageCell)?
                    .albumView?
                    .itemViews
                    .contains(where: { mediaView in
                        mediaView.attachment.id == galleryItem.attachment.id
                    }))
                    .defaulting(to: false)
            }
            .map { $0 as? VisibleMessageCell }
        let maybeTargetView: MediaView? = maybeMessageCell?
            .albumView?
            .itemViews
            .first(where: { $0.attachment.id == galleryItem.attachment.id })
        
        guard
            let messageCell: VisibleMessageCell = maybeMessageCell,
            let targetView: MediaView = maybeTargetView,
            let mediaSuperview: UIView = targetView.superview
        else { return nil }

        let cornerRadius: CGFloat
        let cornerMask: CACornerMask
        let presentationFrame: CGRect = coordinateSpace.convert(targetView.frame, from: mediaSuperview)
        let frameInBubble: CGRect = messageCell.bubbleView.convert(targetView.frame, from: mediaSuperview)

        if messageCell.bubbleView.bounds == targetView.bounds {
            cornerRadius = messageCell.bubbleView.layer.cornerRadius
            cornerMask = messageCell.bubbleView.layer.maskedCorners
        }
        else {
            // If the frames don't match then assume it's either multiple images or there is a caption
            // and determine which corners need to be rounded
            cornerRadius = messageCell.bubbleView.layer.cornerRadius

            var newCornerMask = CACornerMask()
            let cellMaskedCorners: CACornerMask = messageCell.bubbleView.layer.maskedCorners

            if
                cellMaskedCorners.contains(.layerMinXMinYCorner) &&
                    frameInBubble.minX < CGFloat.leastNonzeroMagnitude &&
                    frameInBubble.minY < CGFloat.leastNonzeroMagnitude
            {
                newCornerMask.insert(.layerMinXMinYCorner)
            }

            if
                cellMaskedCorners.contains(.layerMaxXMinYCorner) &&
                abs(frameInBubble.maxX - messageCell.bubbleView.bounds.width) < CGFloat.leastNonzeroMagnitude &&
                    frameInBubble.minY < CGFloat.leastNonzeroMagnitude
            {
                newCornerMask.insert(.layerMaxXMinYCorner)
            }

            if
                cellMaskedCorners.contains(.layerMinXMaxYCorner) &&
                    frameInBubble.minX < CGFloat.leastNonzeroMagnitude &&
                abs(frameInBubble.maxY - messageCell.bubbleView.bounds.height) < CGFloat.leastNonzeroMagnitude
            {
                newCornerMask.insert(.layerMinXMaxYCorner)
            }

            if
                cellMaskedCorners.contains(.layerMaxXMaxYCorner) &&
                abs(frameInBubble.maxX - messageCell.bubbleView.bounds.width) < CGFloat.leastNonzeroMagnitude &&
                abs(frameInBubble.maxY - messageCell.bubbleView.bounds.height) < CGFloat.leastNonzeroMagnitude
            {
                newCornerMask.insert(.layerMaxXMaxYCorner)
            }

            cornerMask = newCornerMask
        }
        
        return MediaPresentationContext(
            mediaView: targetView,
            presentationFrame: presentationFrame,
            cornerRadius: cornerRadius,
            cornerMask: cornerMask
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return self.navigationController?.navigationBar.generateSnapshot(in: coordinateSpace)
    }
}
