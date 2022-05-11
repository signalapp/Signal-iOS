// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import CoreServices
import Photos
import PhotosUI
import PromiseKit
import GRDB
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
        guard !viewModel.viewData.requiresApproval else { return }

        openSettings()
    }

    @objc func openSettings() {
        let settingsVC: OWSConversationSettingsViewController = OWSConversationSettingsViewController()
        settingsVC.configure(
            withThreadId: viewModel.viewData.thread.id,
            threadName: viewModel.viewData.threadName,
            isClosedGroup: (viewModel.viewData.thread.variant == .closedGroup),
            isOpenGroup: (viewModel.viewData.thread.variant == .openGroup),
            isNoteToSelf: viewModel.viewData.threadIsNoteToSelf
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

    // MARK: - Blocking
    
    @objc func unblock() {
        guard self.viewModel.viewData.thread.variant == .contact else { return }
        
        let publicKey: String = self.viewModel.viewData.thread.id

        UIView.animate(
            withDuration: 0.25,
            animations: {
                self.blockedBanner.alpha = 0
            },
            completion: { _ in
                GRDBStorage.shared.write { db in
                    try Contact
                        .filter(id: publicKey)
                        .updateAll(db, Contact.Columns.isBlocked.set(to: true))
                    
                    try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                }
            }
        )
    }

    func showBlockedModalIfNeeded() -> Bool {
        guard viewModel.viewData.threadIsBlocked else { return false }
        
        let blockedModal = BlockedModal(publicKey: viewModel.viewData.thread.id)
        blockedModal.modalPresentationStyle = .overFullScreen
        blockedModal.modalTransitionStyle = .crossDissolve
        present(blockedModal, animated: true, completion: nil)
        
        return true
    }

    // MARK: - SendMediaNavDelegate

    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
        dismiss(animated: true, completion: nil)
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        sendAttachments(attachments, with: messageText ?? "")
        resetMentions()
        self.snInputView.text = ""
        dismiss(animated: true) { }
    }

    func sendMediaNavInitialMessageText(_ sendMediaNavigationController: SendMediaNavigationController) -> String? {
        return snInputView.text
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageText newMessageText: String?) {
        snInputView.text = (newMessageText ?? "")
    }

    // MARK: - AttachmentApprovalViewControllerDelegate
    
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        sendAttachments(attachments, with: messageText ?? "") { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }

        scrollToBottom(isAnimated: false)
        resetMentions()
        self.snInputView.text = ""
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        dismiss(animated: true, completion: nil)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
        snInputView.text = newMessageText ?? ""
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
        requestLibraryPermissionIfNeeded { [weak self] in
            DispatchQueue.main.async {
                let sendMediaNavController = SendMediaNavigationController.showingMediaLibraryFirst()
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
        
        let sendMediaNavController = SendMediaNavigationController.showingCameraFirst()
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
        let navController = AttachmentApprovalViewController.wrappedInNavController(attachments: attachments, approvalDelegate: self)
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

        if text.contains(mnemonic) && !viewModel.viewData.threadIsNoteToSelf && !hasPermissionToSendSeed {
            // Warn the user if they're about to send their seed to someone
            let modal = SendSeedModal()
            modal.modalPresentationStyle = .overFullScreen
            modal.modalTransitionStyle = .crossDissolve
            modal.proceed = { self.sendMessage(hasPermissionToSendSeed: true) }
            return present(modal, animated: true, completion: nil)
        }

        // Note: 'shouldBeVisible' is set to true the first time a thread is saved so we can
        // use it to determine if the user is creating a new thread and update the 'isApproved'
        // flags appropriately
        let thread: SessionThread = viewModel.viewData.thread
        let oldThreadShouldBeVisible: Bool = thread.shouldBeVisible
        let sentTimestampMs: Int64 = Int64(floor((Date().timeIntervalSince1970 * 1000)))
        let linkPreviewDraft: OWSLinkPreviewDraft? = snInputView.linkPreviewInfo?.draft
        let quoteModel: QuotedReplyModel? = snInputView.quoteDraftInfo?.model
        
            for: self.thread,
        approveMessageRequestIfNeeded(
            for: thread,
            isNewThread: !oldThreadShouldBeVisible,
            timestampMs: (sentTimestampMs - 1)  // Set 1ms earlier as this is used for sorting
        )
        .done { [weak self] _ in
            GRDBStorage.shared.writeAsync(
                updates: { db in
                    // Update the thread to be visible
                    _ = try SessionThread
                        .filter(id: thread.id)
                        .updateAll(db, SessionThread.Columns.shouldBeVisible.set(to: true))
                    
                    // Create the interaction
                    let userPublicKey: String = getUserHexEncodedPublicKey(db)
                    let interaction: Interaction = try Interaction(
                        threadId: thread.id,
                        authorId: getUserHexEncodedPublicKey(db),
                        variant: .standardOutgoing,
                        body: text,
                        timestampMs: sentTimestampMs,
                        hasMention: text.contains("@\(userPublicKey)"),
                        linkPreviewUrl: linkPreviewDraft?.urlString
                    ).inserted(db)

                    // If there is a LinkPreview and it doesn't match an existing one then add it now
                    if
                        let linkPreviewDraft: OWSLinkPreviewDraft = linkPreviewDraft,
                        (try? interaction.linkPreview.isEmpty(db)) == true
                    {
                        var attachmentId: String?

                        // If the LinkPreview has image data then create an attachment first
                        if let imageData: Data = linkPreviewDraft.jpegImageData {
                            attachmentId = try LinkPreview.saveAttachmentIfPossible(
                                db,
                                imageData: imageData,
                                mimeType: OWSMimeTypeImageJpeg
                            )
                        }

                        try LinkPreview(
                            url: linkPreviewDraft.urlString,
                            title: linkPreviewDraft.title,
                            attachmentId: attachmentId
                        ).insert(db)
                    }

                    guard let interactionId: Int64 = interaction.id else { return }

                    // If there is a Quote the insert it now
                    if let quoteModel: QuotedReplyModel = quoteModel {
                        try Quote(
                            interactionId: interactionId,
                            authorId: quoteModel.authorId,
                            timestampMs: quoteModel.timestampMs,
                            body: quoteModel.body,
                            attachmentId: quoteModel.attachment?.id
                        ).insert(db)
                    }
                    
                    try MessageSender.send(
                        db,
                        interaction: interaction,
                        with: [],
                        in: thread
                    )
                },
                completion: { [weak self] _, _ in
                    self?.viewModel.sentMessageBeforeUpdate = true
                    self?.handleMessageSent()
                }
            )
        }
        .catch(on: DispatchQueue.main) { [weak self] _ in
            // Show an error indicating that approving the thread failed
            let alert = UIAlertController(title: "Session", message: "An error occurred when trying to accept this message request", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self?.present(alert, animated: true, completion: nil)
        }
        .retainUntilComplete()
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
        let thread: SessionThread = viewModel.viewData.thread
        let oldThreadShouldBeVisible: Bool = thread.shouldBeVisible
        let sentTimestampMs: Int64 = Int64(floor((Date().timeIntervalSince1970 * 1000)))

        approveMessageRequestIfNeeded(
            for: thread,
            isNewThread: !oldThreadShouldBeVisible,
            timestampMs: (sentTimestampMs - 1)  // Set 1ms earlier as this is used for sorting
        )
        .done { [weak self] _ in
            GRDBStorage.shared.writeAsync(
                updates: { db in
                    // Update the thread to be visible
                    _ = try SessionThread
                        .filter(id: thread.id)
                        .updateAll(db, SessionThread.Columns.shouldBeVisible.set(to: true))
                    
                    // Create the interaction
                    let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
                    let interaction: Interaction = try Interaction(
                        threadId: thread.id,
                        authorId: getUserHexEncodedPublicKey(db),
                        variant: .standardOutgoing,
                        body: text,
                        timestampMs: sentTimestampMs,
                        hasMention: text.contains("@\(currentUserPublicKey)")
                    ).inserted(db)

                    try MessageSender.send(
                        db,
                        interaction: interaction,
                        with: attachments,
                        in: thread
                    )
                },
                completion: { [weak self] _, _ in
                    self?.viewModel.sentMessageBeforeUpdate = true
                    self?.handleMessageSent()
                    
                    // Attachment successfully sent - dismiss the screen
                    DispatchQueue.main.async {
                        onComplete?()
                    }
                }
            )
        }
        .catch(on: DispatchQueue.main) { [weak self] _ in
            // Show an error indicating that approving the thread failed
            let alert = UIAlertController(title: "Session", message: "An error occurred when trying to accept this message request", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self?.present(alert, animated: true, completion: nil)
        }
        .retainUntilComplete()
    }

    func handleMessageSent() {
        DispatchQueue.main.async { [weak self] in
            self?.snInputView.text = ""
            self?.snInputView.quoteDraftInfo = nil
        }
        
        resetMentions()

        if Environment.shared.preferences.soundInForeground() {
            let soundID = Preferences.Sound.systemSoundId(for: .messageSent, quiet: true)
            AudioServicesPlaySystemSound(soundID)
        }
        
        let thread: SessionThread = self.viewModel.viewData.thread
        
        GRDBStorage.shared.writeAsync { db in
            TypingIndicators.didStopTyping(db, in: thread, direction: .outgoing)
            
            _ = try SessionThread
                .filter(id: thread.id)
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
            let thread: SessionThread = self.viewModel.viewData.thread
            
            GRDBStorage.shared.writeAsync { db in
                TypingIndicators.didStartTyping(
                    db,
                    in: thread,
                    direction: .outgoing,
                    timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
                )
            }
        }
        
        updateMentions(for: newText)
    }
    
    // MARK: --Attachments
    
    func didPasteImageFromPasteboard(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else { return }
        
        let dataSource = DataSourceValue.dataSource(with: imageData, utiType: kUTTypeJPEG as String)
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeJPEG as String, imageQuality: .medium)

        let approvalVC = AttachmentApprovalViewController.wrappedInNavController(attachments: [ attachment ], approvalDelegate: self)
        approvalVC.modalPresentationStyle = .fullScreen
        
        self.present(approvalVC, animated: true, completion: nil)
    }

    // MARK: --Mentions
    
    func handleMentionSelected(_ mentionInfo: ConversationViewModel.MentionInfo, from view: MentionSelectionView) {
        guard let currentMentionStartIndex = currentMentionStartIndex else { return }
        
        mentions.append(mentionInfo)
        
        let newText: String = snInputView.text.replacingCharacters(
            in: currentMentionStartIndex...,
            with: "@\(mentionInfo.profile.displayName(for: self.viewModel.viewData.thread.variant)) "
        )
        
        snInputView.text = newText
        self.currentMentionStartIndex = nil
        snInputView.hideMentionsUI()
        
        mentions = mentions.filter { mentionInfo -> Bool in
            newText.contains(mentionInfo.profile.displayName(for: self.viewModel.viewData.thread.variant))
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

    func showInputAccessoryView() {
        UIView.animate(withDuration: 0.25, animations: {
            self.inputAccessoryView?.isHidden = false
            self.inputAccessoryView?.alpha = 1
        })
    }

    // MARK: MessageCellDelegate

    func handleItemLongPressed(_ item: ConversationViewModel.Item) {
        // Show the context menu if applicable
        guard
            let keyWindow: UIWindow = UIApplication.shared.keyWindow,
            let index = viewModel.viewData.items.firstIndex(of: item),
            let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? VisibleMessageCell,
            let snapshot = cell.bubbleView.snapshotView(afterScreenUpdates: false),
            contextMenuWindow == nil,
            let actions: [ContextMenuVC.Action] = ContextMenuVC.actions(
                for: item,
                currentUserIsOpenGroupModerator: OpenGroupAPIV2.isUserModerator(
                    self.viewModel.viewData.userPublicKey,
                    for: self.viewModel.viewData.openGroupRoom,
                    on: self.viewModel.viewData.openGroupServer
                ),
                delegate: self
            )
        else { return }
        
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        self.contextMenuWindow = ContextMenuWindow()
        self.contextMenuVC = ContextMenuVC(
            snapshot: snapshot,
            frame: cell.convert(cell.bubbleView.frame, to: keyWindow),
            item: item,
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
        self.contextMenuWindow?.makeKeyAndVisible()
    }

    func handleItemTapped(_ item: ConversationViewModel.Item, gestureRecognizer: UITapGestureRecognizer) {
        guard item.interactionVariant != .standardOutgoing || item.state != .failed else {
            // Show the failed message sheet
            showFailedMessageSheet(for: item)
            return
        }
        
        // If it's an incoming media message and the thread isn't trusted then show the placeholder view
        if item.cellType != .textOnlyMessage && item.interactionVariant == .standardIncoming && !item.isThreadTrusted {
            let modal = DownloadAttachmentModal(profile: item.profile)
            modal.modalPresentationStyle = .overFullScreen
            modal.modalTransitionStyle = .crossDissolve
            
            present(modal, animated: true, completion: nil)
            return
        }
        
        switch item.cellType {
            case .audio: viewModel.playOrPauseAudio(for: item)
            
            case .mediaMessage:
                guard let index = viewItems.firstIndex(where: { $0 === viewItem }),
                    let cell = messagesTableView.cellForRow(at: IndexPath(row: index, section: 0)) as? VisibleMessageCell else { return }
                if
                    viewItem.interaction is TSIncomingMessage,
                    let thread = self.thread as? TSContactThread,
                    let contact: Contact? = GRDBStorage.shared.read({ db in try Contact.fetchOne(db, id: thread.contactSessionID()) }),
                    contact?.isTrusted != true {
                    confirmDownload()
                } else {
                    guard let albumView = cell.albumView else { return }
                    let locationInCell = gestureRecognizer.location(in: cell)
                    // Figure out which of the media views was tapped
                    let locationInAlbumView = cell.convert(locationInCell, to: albumView)
                    guard let mediaView = albumView.mediaView(forLocation: locationInAlbumView) else { return }
                    if albumView.isMoreItemsView(mediaView: mediaView) && viewItem.mediaAlbumHasFailedAttachment() {
                        // TODO: Tapped a failed incoming attachment
                    }
                    let attachment = mediaView.attachment
                    if let pointer = attachment as? TSAttachmentPointer {
                        if pointer.state == .failed {
                            // TODO: Tapped a failed incoming attachment
                        }
                    }
                    guard let stream = attachment as? TSAttachmentStream else { return }
                    let gallery = MediaGallery(thread: thread, options: [ .sliderEnabled, .showAllMediaButton ])
                    gallery.presentDetailView(fromViewController: self, mediaAttachment: stream)
                }
            case .genericAttachment:
                guard
                    let attachment: Attachment = item.attachments?.first,
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
                navigationController?.present(shareVC, animated: true, completion: nil)
            case .textOnlyMessage:
                if let reply = viewItem.quotedReply {
                    // Scroll to the source of the reply
                    guard let indexPath = viewModel.ensureLoadWindowContainsQuotedReply(reply) else { return }
                    messagesTableView.scrollToRow(at: indexPath, at: UITableView.ScrollPosition.middle, animated: true)
                } else if let message = viewItem.interaction as? TSIncomingMessage, let name = message.openGroupInvitationName,
                    let url = message.openGroupInvitationURL {
                    joinOpenGroup(name: name, url: url)
                }
            default: break
            }
        }
    }
    
    func handleItemDoubleTapped(_ item: ConversationViewModel.Item) {
        switch item.cellType {
            // The user can double tap a voice message when it's playing to speed it up
            case .audio: self.viewModel.speedUpAudio(for: item)
            default: break
        }
    }

    func showFailedMessageSheet(for tsMessage: TSOutgoingMessage) {
        let thread = self.thread
        let error = tsMessage.mostRecentFailureText
        let sheet = UIAlertController(title: error, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            Storage.write { transaction in
                tsMessage.remove(with: transaction)
                Storage.shared.cancelPendingMessageSendJobIfNeeded(for: tsMessage.timestamp, using: transaction)
            }
        }))
        sheet.addAction(UIAlertAction(title: "Resend", style: .default, handler: { _ in
            let message = VisibleMessage.from(tsMessage)
            Storage.write { transaction in
                var attachments: [TSAttachmentStream] = []
                tsMessage.attachmentIds.forEach { attachmentID in
                    guard let attachmentID = attachmentID as? String else { return }
                    let attachment = TSAttachment.fetch(uniqueId: attachmentID, transaction: transaction)
                    guard let stream = attachment as? TSAttachmentStream else { return }
                    attachments.append(stream)
                }
                MessageSender.prep(attachments, for: message, using: transaction)
                MessageSender.send(message, in: thread, using: transaction)
            }
        }))
        // HACK: Extracting this info from the error string is pretty dodgy
        let prefix = "HTTP request failed at destination (Service node "
        if error.hasPrefix(prefix) {
            let rest = error.substring(from: prefix.count)
            if let index = rest.firstIndex(of: ")") {
                let snodeAddress = String(rest[rest.startIndex..<index])
                sheet.addAction(UIAlertAction(title: "Copy Service Node Info", style: .default, handler: { _ in
                    UIPasteboard.general.string = snodeAddress
                }))
            }
    func handleItemSwiped(_ item: ConversationViewModel.Item, state: SwipeState) {
        switch state {
            case .began: tableView.isScrollEnabled = false
            case .ended, .cancelled: tableView.isScrollEnabled = true
        }
    }

    
    func showFullText(_ viewItem: ConversationViewItem) {
        let longMessageVC = LongTextViewController(viewItem: viewItem)
        navigationController!.pushViewController(longMessageVC, animated: true)
    }
    
    func reply(_ viewItem: ConversationViewItem) {
        var quoteDraftOrNil: OWSQuotedReplyModel?
        Storage.read { transaction in
            quoteDraftOrNil = OWSQuotedReplyModel.quotedReplyForSending(with: viewItem, threadId: viewItem.interaction.uniqueThreadId, transaction: transaction)
        }
        guard let quoteDraft = quoteDraftOrNil else { return }
        let isOutgoing = (viewItem.interaction.interactionType() == .outgoingMessage)
        snInputView.quoteDraftInfo = (model: quoteDraft, isOutgoing: isOutgoing)
        snInputView.becomeFirstResponder()
    }
    
    func copy(_ viewItem: ConversationViewItem) {
        if viewItem.canCopyMedia() {
            viewItem.copyMediaAction()
        } else {
            viewItem.copyTextAction()
        }
    }
    
    func copySessionID(_ viewItem: ConversationViewItem) {
        // FIXME: Copying media
        guard let message = viewItem.interaction as? TSIncomingMessage else { return }
        UIPasteboard.general.string = message.authorId
    }
    
    func delete(_ viewItem: ConversationViewItem) {
        guard let message = viewItem.interaction as? TSMessage else { return self.deleteLocally(viewItem) }
        
        // Handle open group messages the old way
        if message.isOpenGroupMessage { return self.deleteForEveryone(viewItem) }
        
        // Handle 1-1 and closed group messages with unsend request
        if viewItem.interaction.interactionType() == .outgoingMessage, message.serverHash != nil  {
            let alertVC = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
            let deleteLocallyAction = UIAlertAction.init(title: NSLocalizedString("delete_message_for_me", comment: ""), style: .destructive) { _ in
                self.deleteLocally(viewItem)
                self.showInputAccessoryView()
            }
            alertVC.addAction(deleteLocallyAction)
            
            var title = NSLocalizedString("delete_message_for_everyone", comment: "")
            if !viewItem.isGroupThread {
                title = String(format: NSLocalizedString("delete_message_for_me_and_recipient", comment: ""), viewItem.interaction.thread.name())
            }
            let deleteRemotelyAction = UIAlertAction.init(title: title, style: .destructive) { _ in
                self.deleteForEveryone(viewItem)
                self.showInputAccessoryView()
            }
            alertVC.addAction(deleteRemotelyAction)
            
            let cancelAction = UIAlertAction.init(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .cancel) {_ in
                self.showInputAccessoryView()
            }
            alertVC.addAction(cancelAction)
            
            self.inputAccessoryView?.isHidden = true
            self.inputAccessoryView?.alpha = 0
            self.presentAlert(alertVC)
        } else {
            deleteLocally(viewItem)
        }
    }
    
    private func buildUnsendRequest(_ viewItem: ConversationViewItem) -> UnsendRequest? {
        if let message = viewItem.interaction as? TSMessage,
           message.isOpenGroupMessage || message.serverHash == nil { return nil }
        let unsendRequest = UnsendRequest()
        switch viewItem.interaction.interactionType() {
        case .incomingMessage:
            if let incomingMessage = viewItem.interaction as? TSIncomingMessage {
                unsendRequest.author = incomingMessage.authorId
            }
        case .outgoingMessage: unsendRequest.author = getUserHexEncodedPublicKey()
        default: return nil // Should never occur
        }
        unsendRequest.timestamp = viewItem.interaction.timestamp
        return unsendRequest
    }
    
    func deleteLocally(_ viewItem: ConversationViewItem) {
        viewItem.deleteLocallyAction()
        if let unsendRequest = buildUnsendRequest(viewItem) {
            SNMessagingKitConfiguration.shared.storage.write { transaction in
                MessageSender.send(unsendRequest, to: .contact(publicKey: getUserHexEncodedPublicKey()), using: transaction).retainUntilComplete()
            }
        }
    }
    
    func deleteForEveryone(_ viewItem: ConversationViewItem) {
        viewItem.deleteLocallyAction()
        viewItem.deleteRemotelyAction()
        if let unsendRequest = buildUnsendRequest(viewItem) {
            SNMessagingKitConfiguration.shared.storage.write { transaction in
                MessageSender.send(unsendRequest, in: self.thread, using: transaction as! YapDatabaseReadWriteTransaction)
            }
        }
    }
    
    func save(_ viewItem: ConversationViewItem) {
        guard viewItem.canSaveMedia() else { return }
        viewItem.saveMediaAction()
        sendMediaSavedNotificationIfNeeded(for: viewItem)
    }
    
    func ban(_ viewItem: ConversationViewItem) {
        guard let message = viewItem.interaction as? TSIncomingMessage, message.isOpenGroupMessage else { return }
        let explanation = "This will ban the selected user from this room. It won't ban them from other rooms."
        let alert = UIAlertController(title: "Session", message: explanation, preferredStyle: .alert)
        let threadID = thread.uniqueId!
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let publicKey = message.authorId
            guard let openGroupV2 = Storage.shared.getV2OpenGroup(for: threadID) else { return }
            OpenGroupAPIV2.ban(publicKey, from: openGroupV2.room, on: openGroupV2.server).retainUntilComplete()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    func banAndDeleteAllMessages(_ viewItem: ConversationViewItem) {
        guard let message = viewItem.interaction as? TSIncomingMessage, message.isOpenGroupMessage else { return }
        let explanation = "This will ban the selected user from this room and delete all messages sent by them. It won't ban them from other rooms or delete the messages they sent there."
        let alert = UIAlertController(title: "Session", message: explanation, preferredStyle: .alert)
        let threadID = thread.uniqueId!
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let publicKey = message.authorId
            guard let openGroupV2 = Storage.shared.getV2OpenGroup(for: threadID) else { return }
            OpenGroupAPIV2.banAndDeleteAllMessages(publicKey, from: openGroupV2.room, on: openGroupV2.server).retainUntilComplete()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    func handleQuoteViewCancelButtonTapped() {
        snInputView.quoteDraftInfo = nil
    }
    
    func openURL(_ url: URL) {
        // URLs can be unsafe, so always ask the user whether they want to open one
        let title = NSLocalizedString("modal_open_url_title", comment: "")
        let message = String(format: NSLocalizedString("modal_open_url_explanation", comment: ""), url.absoluteString)
        let alertVC = UIAlertController.init(title: title, message: message, preferredStyle: .actionSheet)
        let openAction = UIAlertAction.init(title: NSLocalizedString("modal_open_url_button_title", comment: ""), style: .default) { _ in
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            self.showInputAccessoryView()
        }
        alertVC.addAction(openAction)
        let copyAction = UIAlertAction.init(title: NSLocalizedString("modal_copy_url_button_title", comment: ""), style: .default) { _ in
            UIPasteboard.general.string = url.absoluteString
            self.showInputAccessoryView()
        }
        alertVC.addAction(copyAction)
        let cancelAction = UIAlertAction.init(title: NSLocalizedString("cancel", comment: ""), style: .cancel) {_ in
            self.showInputAccessoryView()
        }
        alertVC.addAction(cancelAction)
        self.presentAlert(alertVC)
    }
    
    func joinOpenGroup(name: String, url: String) {
        // Open groups can be unsafe, so always ask the user whether they want to join one
        let joinOpenGroupModal = JoinOpenGroupModal(name: name, url: url)
        joinOpenGroupModal.modalPresentationStyle = .overFullScreen
        joinOpenGroupModal.modalTransitionStyle = .crossDissolve
        present(joinOpenGroupModal, animated: true, completion: nil)
    }
    
    func handleReplyButtonTapped(for item: ConversationViewModel.Item) {
        reply(item)
    }
    
    func showUserDetails(for profile: Profile) {
        let userDetailsSheet = UserDetailsSheet(for: profile)
        userDetailsSheet.modalPresentationStyle = .overFullScreen
        userDetailsSheet.modalTransitionStyle = .crossDissolve
        
        present(userDetailsSheet, animated: true, completion: nil)
    }

    // MARK: Voice Message Playback
    @objc func handleAudioDidFinishPlayingNotification(_ notification: Notification) {
        // Play the next voice message if there is one
        guard let audioPlayer = audioPlayer, let viewItem = audioPlayer.owner as? ConversationViewItem,
            let index = viewItems.firstIndex(where: { $0 === viewItem }), index < (viewItems.endIndex - 1) else { return }
        let nextViewItem = viewItems[index + 1]
        guard nextViewItem.messageCellType == .audio else { return }
        playOrPauseAudio(for: nextViewItem)
    }
    
    func playOrPauseAudio(for viewItem: ConversationViewItem) {
        guard let attachment = viewItem.attachmentStream else { return }
        let fileManager = FileManager.default
        guard let path = attachment.originalFilePath, fileManager.fileExists(atPath: path),
            let url = attachment.originalMediaURL else { return }
        if let audioPlayer = audioPlayer {
            if let owner = audioPlayer.owner as? ConversationViewItem, owner === viewItem {
                audioPlayer.playbackRate = 1
                audioPlayer.togglePlayState()
                return
            } else {
                audioPlayer.stop()
                self.audioPlayer = nil
            }
        }
        let audioPlayer = OWSAudioPlayer(mediaUrl: url, audioBehavior: .audioMessagePlayback, delegate: viewItem)
        self.audioPlayer = audioPlayer
        audioPlayer.owner = viewItem
        audioPlayer.play()
        audioPlayer.setCurrentTime(Double(viewItem.audioProgressSeconds))
    }

    func speedUpAudio(for viewItem: ConversationViewItem) {
        guard let audioPlayer = audioPlayer, let owner = audioPlayer.owner as? ConversationViewItem, owner === viewItem, audioPlayer.isPlaying else { return }
        audioPlayer.playbackRate = 1.5
        viewItem.lastAudioMessageView?.showSpeedUpLabel()
    }

    // MARK: Voice Message Recording
    func startVoiceMessageRecording() {
        // Request permission if needed
        requestMicrophonePermissionIfNeeded() { [weak self] in
            self?.cancelVoiceMessageRecording()
        }
        // Keep screen on
        UIApplication.shared.isIdleTimerDisabled = false
        guard AVAudioSession.sharedInstance().recordPermission == .granted else { return }
        // Cancel any current audio playback
        audioPlayer?.stop()
        audioPlayer = nil
        // Create URL
        let directory = OWSTemporaryDirectory()
        let fileName = "\(NSDate.millisecondTimestamp()).m4a"
        let path = (directory as NSString).appendingPathComponent(fileName)
        let url = URL(fileURLWithPath: path)
        // Set up audio session
        let isConfigured = audioSession.startAudioActivity(recordVoiceMessageActivity)
        guard isConfigured else {
            return cancelVoiceMessageRecording()
        }
        // Set up audio recorder
        let settings: [String:NSNumber] = [
            AVFormatIDKey : NSNumber(value: kAudioFormatMPEG4AAC),
            AVSampleRateKey : NSNumber(value: 44100),
            AVNumberOfChannelsKey : NSNumber(value: 2),
            AVEncoderBitRateKey : NSNumber(value: 128 * 1024)
        ]
        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = true
            self.audioRecorder = audioRecorder
        } catch {
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
            let title = NSLocalizedString("VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE", comment: "")
            let message = NSLocalizedString("VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE", comment: "")
            return OWSAlerts.showAlert(title: title, message: message)
        }
        // Get data
        let dataSourceOrNil = DataSourcePath.dataSource(with: audioRecorder.url, shouldDeleteOnDeallocation: true)
        self.audioRecorder = nil
        guard let dataSource = dataSourceOrNil else { return SNLog("Couldn't load recorded data.") }
        // Create attachment
        let fileName = (NSLocalizedString("VOICE_MESSAGE_FILE_NAME", comment: "") as NSString).appendingPathExtension("m4a")
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
        audioSession.endAudioActivity(recordVoiceMessageActivity)
    }
    
    // MARK: Data Extraction Notifications
    @objc func sendScreenshotNotificationIfNeeded() {
        /*
        guard thread is TSContactThread else { return }
        let message = DataExtractionNotification()
        message.kind = .screenshot
        Storage.write { transaction in
            MessageSender.send(message, in: self.thread, using: transaction)
        }
         */
    }
    
    func sendMediaSavedNotificationIfNeeded(for viewItem: ConversationViewItem) {
        guard thread is TSContactThread, viewItem.interaction.interactionType() == .incomingMessage else { return }
        let message = DataExtractionNotification()
        message.kind = .mediaSaved(timestamp: viewItem.interaction.timestamp)
        Storage.write { transaction in
            MessageSender.send(message, in: self.thread, using: transaction)
        }
    }

    // MARK: Requesting Permission
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
                Environment.shared.isRequestingPermission = true
                let appMode = AppModeManager.shared.currentAppMode
                // FIXME: Rather than setting the app mode to light and then to dark again once we're done,
                // it'd be better to just customize the appearance of the image picker. There doesn't currently
                // appear to be a good way to do so though...
                AppModeManager.shared.setCurrentAppMode(to: .light)
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    DispatchQueue.main.async {
                        AppModeManager.shared.setCurrentAppMode(to: appMode)
                    }
                    Environment.shared.isRequestingPermission = false
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
        let title = NSLocalizedString("ATTACHMENT_ERROR_ALERT_TITLE", comment: "")
        let message = attachment.localizedErrorDescription ?? SignalAttachment.missingDataErrorMessage
        
        OWSAlerts.showAlert(title: title, message: message, buttonTitle: nil) { _ in
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
    
    fileprivate func approveMessageRequestIfNeeded(for thread: TSThread?, isNewThread: Bool, timestamp: Double) -> Promise<Void> {
        guard let contactThread: TSContactThread = thread as? TSContactThread else { return Promise.value(()) }
        
        // If the contact doesn't exist then we should create it so we can store the 'isApproved' state
        // (it'll be updated with correct profile info if they accept the message request so this
        // shouldn't cause weird behaviours)
        let sessionId: String = contactThread.contactSessionID()
        
        guard
            let contact: Contact = GRDBStorage.shared.read({ db in Contact.fetchOrCreate(db, id: sessionId) }),
            !contact.isApproved
        else {
            return Promise.value(())
        }
        
        return Promise.value(())
            .then { [weak self] _ -> Promise<Void> in
                guard !isNewThread else { return Promise.value(()) }
                guard let strongSelf = self else { return Promise(error: MessageSender.Error.noThread) }
                
                // If we aren't creating a new thread (ie. sending a message request) then send a
                // messageRequestResponse back to the sender (this allows the sender to know that
                // they have been approved and can now use this contact in closed groups)
                let (promise, seal) = Promise<Void>.pending()
                let messageRequestResponse: MessageRequestResponse = MessageRequestResponse(
                    isApproved: true
                )
                messageRequestResponse.sentTimestamp = timestamp
                
                // Show a loading indicator
                ModalActivityIndicatorViewController.present(fromViewController: strongSelf, canCancel: false) { _ in
                    seal.fulfill(())
                }
                
                return promise
                    .then { _ -> Promise<Void> in
                        let (promise, seal) = Promise<Void>.pending()
                        Storage.writeSync { transaction in
                            MessageSender.sendNonDurably(messageRequestResponse, in: contactThread, using: transaction)
                                .done { seal.fulfill(()) }
                                .catch { _ in seal.fulfill(()) } // Fulfill even if this failed; the configuration in the swarm should be at most 2 days old
                                .retainUntilComplete()
                        }
                        
                        return promise
                    }
                    .map { _ in
                        if self?.presentedViewController is ModalActivityIndicatorViewController {
                            self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                        }
                    }
            }
            .map { _ in
                // Default 'didApproveMe' to true for the person approving the message request
                GRDBStorage.shared.writeAsync(
                    updates: { db in
                        try contact
                            .with(
                                isApproved: true,
                                didApproveMe: .update(contact.didApproveMe || !isNewThread)
                            )
                            .save(db)
                    },
                    completion: { db, _ in
                        // Send a sync message with the details of the contact
                        MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                        
                        // Hide the 'messageRequestView' since the request has been approved
                        DispatchQueue.main.async { [weak self] in
                            let messageRequestViewWasVisible: Bool = (self?.messageRequestView.isHidden == false)
                            
                            UIView.animate(withDuration: 0.3) {
                                self?.messageRequestView.isHidden = true
                                self?.scrollButtonMessageRequestsBottomConstraint?.isActive = false
                                self?.scrollButtonBottomConstraint?.isActive = true
                                
                                // Update the table content inset and offset to account for
                                // the dissapearance of the messageRequestsView
                                if messageRequestViewWasVisible {
                                    let messageRequestsOffset: CGFloat = ((self?.messageRequestView.bounds.height ?? 0) + 16)
                                    let oldContentInset: UIEdgeInsets = (self?.messagesTableView.contentInset ?? UIEdgeInsets.zero)
                                    self?.messagesTableView.contentInset = UIEdgeInsets(
                                        top: 0,
                                        leading: 0,
                                        bottom: max(oldContentInset.bottom - messageRequestsOffset, 0),
                                        trailing: 0
                                    )
                                }
                            }
                            
                            // Update UI
                            self?.updateNavBarButtons()
                            
                            // Remove the 'MessageRequestsViewController' from the nav hierarchy if present
                            if
                                let viewControllers: [UIViewController] = self?.navigationController?.viewControllers,
                                let messageRequestsIndex = viewControllers.firstIndex(where: { $0 is MessageRequestsViewController }),
                                messageRequestsIndex > 0
                            {
                                var newViewControllers = viewControllers
                                newViewControllers.remove(at: messageRequestsIndex)
                                self?.navigationController?.setViewControllers(newViewControllers, animated: false)
                            }
                        }
                    }
                )
            }
    }
    
    @objc func acceptMessageRequest() {
        let promise: Promise<Void> = self.approveMessageRequestIfNeeded(
            for: self.thread,
            isNewThread: false,
            timestamp: NSDate.millisecondTimestamp()
        )
        
        // Show an error indicating that approving the thread failed
        promise.catch(on: DispatchQueue.main) { [weak self] _ in
            let alert = UIAlertController(title: "Session", message: NSLocalizedString("MESSAGE_REQUESTS_APPROVAL_ERROR_MESSAGE", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
            self?.present(alert, animated: true, completion: nil)
        }
        
        promise.retainUntilComplete()
    }
    
    @objc func deleteMessageRequest() {
        guard let uniqueId: String = thread.uniqueId else { return }
        
        let alertVC: UIAlertController = UIAlertController(title: NSLocalizedString("MESSAGE_REQUESTS_DELETE_CONFIRMATION_ACTON", comment: ""), message: nil, preferredStyle: .actionSheet)
        alertVC.addAction(UIAlertAction(title: NSLocalizedString("TXT_DELETE_TITLE", comment: ""), style: .destructive) { _ in
            // Delete the request
            GRDBStorage.shared.writeAsync(
                updates: { [weak self] db in
                    // Update the contact
                    if let contactThread: TSContactThread = self?.thread as? TSContactThread {
                        let sessionId: String = contactThread.contactSessionID()
                        
                        // Stop observing the `BlockListDidChange` notification (we are about to pop the screen
                        // so showing the banner just looks buggy)
                        if let strongSelf = self {
                            NotificationCenter.default.removeObserver(strongSelf, name: .contactBlockedStateChanged, object: nil)
                        }
                        
                        try? Contact
                            .fetchOne(db, id: sessionId)?
                            .with(
                                isApproved: false,
                                isBlocked: true,
                                
                                // Note: We set this to true so the current user will be able to send a
                                // message to the person who originally sent them the message request in
                                // the future if they unblock them
                                didApproveMe: true
                            )
                            .update(db)
                    }
                },
                completion: { db, _ in
                    Storage.write(
                        with: { [weak self] transaction in
                            // TODO: This should be above the contact updating
                            Storage.shared.cancelPendingMessageSendJobs(for: uniqueId, using: transaction)
                            
                            // Delete all thread content
                            self?.thread.removeAllThreadInteractions(with: transaction)
                            self?.thread.remove(with: transaction)
                        },
                        completion: { [weak self] in
                            // Force a config sync and pop to the previous screen
                            // TODO: This might cause an "incorrect thread" crash
                            MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                            
                            DispatchQueue.main.async {
                                self?.navigationController?.popViewController(animated: true)
                            }
                        }
                    )
                }
            )
        })
        alertVC.addAction(UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .cancel, handler: nil))
        self.present(alertVC, animated: true, completion: nil)
    }
}
