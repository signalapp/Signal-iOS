//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
public import Photos
public import SignalServiceKit
public import SignalUI
import UniformTypeIdentifiers

extension ConversationViewController: ConversationInputToolbarDelegate {

    public func isBlockedConversation() -> Bool {
        threadViewModel.isBlocked
    }

    public func isGroup() -> Bool {
        isGroupConversation
    }

    public func sendButtonPressed() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        inputToolbar.acceptAutocorrectSuggestion()

        guard let messageBody = inputToolbar.messageBodyForSending else {
            return
        }

        tryToSendTextMessage(messageBody, updateKeyboardState: true)
    }

    public func messageWasSent() {
        AssertIsOnMainThread()

        self.lastMessageSentDate = Date()

        loadCoordinator.clearUnreadMessagesIndicator()
        inputToolbar?.quotedReplyDraft = nil

        if SSKEnvironment.shared.preferencesRef.soundInForeground,
           let soundId = Sounds.systemSoundIDForSound(.standard(.messageSent), quiet: true) {
            AudioServicesPlaySystemSound(soundId)
        }
        SSKEnvironment.shared.typingIndicatorsRef.didSendOutgoingMessage(inThread: thread)
    }

    private func tryToSendTextMessage(_ messageBody: MessageBody, updateKeyboardState: Bool) {
        tryToSendTextMessage(
            messageBody,
            updateKeyboardState: updateKeyboardState,
            untrustedThreshold: Date().addingTimeInterval(-OWSIdentityManagerImpl.Constants.defaultUntrustedInterval)
        )
    }

    private func tryToSendTextMessage(_ messageBody: MessageBody, updateKeyboardState: Bool, untrustedThreshold: Date) {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("View not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        guard !isBlockedConversation() else {
            showUnblockConversationUI { [weak self] isBlocked in
                if !isBlocked {
                    self?.tryToSendTextMessage(messageBody, updateKeyboardState: false, untrustedThreshold: untrustedThreshold)
                }
            }
            return
        }

        let newUntrustedThreshold = Date()
        let didShowSNAlert = showSafetyNumberConfirmationIfNecessary(
            confirmationText: SafetyNumberStrings.confirmSendButton,
            untrustedThreshold: untrustedThreshold
        ) { [weak self] didConfirmIdentity in
            guard let self = self else { return }
            if didConfirmIdentity {
                self.tryToSendTextMessage(messageBody, updateKeyboardState: false, untrustedThreshold: newUntrustedThreshold)
            }
        }
        if didShowSNAlert {
            return
        }

        guard !messageBody.text.isEmpty else {
            return
        }

        let didAddToProfileWhitelist = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)

        let editValidationError: EditSendValidationError? = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            if let editTarget = inputToolbar.editTarget {
                return context.editManager.validateCanSendEdit(
                    targetMessageTimestamp: editTarget.timestamp,
                    thread: self.thread,
                    tx: transaction
                )
            }
            return nil
        }

        if let error = editValidationError {
            OWSActionSheets.showActionSheet(message: error.localizedDescription)
            return
        }

        if let editTarget = inputToolbar.editTarget {
            ThreadUtil.enqueueEditMessage(
                body: messageBody,
                thread: self.thread,
                // If we have _any_ quoted reply populated, keep the existing quoted reply.
                // If its cleared, "change" it to nothing (clear it).
                quotedReplyEdit: inputToolbar.quotedReplyDraft == nil ? .change(()) : .keep,
                linkPreviewDraft: inputToolbar.linkPreviewDraft,
                editTarget: editTarget,
                persistenceCompletionHandler: {
                    AssertIsOnMainThread()
                    self.loadCoordinator.enqueueReload()
                }
            )
        } else {
            ThreadUtil.enqueueMessage(
                body: messageBody,
                thread: self.thread,
                quotedReplyDraft: inputToolbar.quotedReplyDraft,
                linkPreviewDraft: inputToolbar.linkPreviewDraft,
                persistenceCompletionHandler: {
                    AssertIsOnMainThread()
                    self.loadCoordinator.enqueueReload()
                }
            )
        }

        messageWasSent()

        // Clearing the text message is a key part of the send animation.
        // It takes 10-15ms, but we do it inline rather than dispatch async
        // since the send can't feel "complete" without it.
        inputToolbar.clearTextMessage(animated: true)

        let thread = self.thread
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            // Reload a fresh instance of the thread model; our models are not
            // thread-safe, so it wouldn't be safe to update the model in an
            // async write.
            guard let thread = TSThread.anyFetch(uniqueId: thread.uniqueId, transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return
            }
            thread.updateWithDraft(
                draftMessageBody: nil,
                replyInfo: nil,
                editTargetTimestamp: nil,
                transaction: transaction
            )
        }

        if didAddToProfileWhitelist {
            ensureBannerState()
        }

        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    public func sendSticker(_ stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        ImpactHapticFeedback.impactOccurred(style: .light)

        ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, thread: thread)
        messageWasSent()
    }

    public func presentManageStickersView() {
        AssertIsOnMainThread()

        let manageStickersView = ManageStickersViewController()
        let navigationController = OWSNavigationController(rootViewController: manageStickersView)
        presentFormSheet(navigationController, animated: true)
    }

    public func updateToolbarHeight() {
        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard inputToolbar != nil else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        updateInputAccessoryPlaceholderHeight()
        updateBottomBarPosition()
        updateContentInsets()
    }

    public func voiceMemoGestureDidStart() {
        AssertIsOnMainThread()
        Logger.info("")

        let kIgnoreMessageSendDoubleTapDurationSeconds: TimeInterval = 2.0
        if let lastMessageSentDate = self.lastMessageSentDate,
           abs(lastMessageSentDate.timeIntervalSinceNow) < kIgnoreMessageSendDoubleTapDurationSeconds {
            // If users double-taps the message send button, the second tap can look like a
            // very short voice message gesture.  We want to ignore such gestures.
            cancelRecordingVoiceMessage()
            return
        }

        checkPermissionsAndStartRecordingVoiceMessage()
    }

    public func voiceMemoGestureDidComplete() {
        AssertIsOnMainThread()
        Logger.info("")

        finishRecordingVoiceMessage(sendImmediately: true)
    }

    public func voiceMemoGestureDidLock() {
        AssertIsOnMainThread()
        Logger.info("")

        inputToolbar?.lockVoiceMemoUI()
    }

    public func voiceMemoGestureDidCancel() {
        AssertIsOnMainThread()
        Logger.info("")

        cancelRecordingVoiceMessage()
    }

    public func voiceMemoGestureWasInterrupted() {
        AssertIsOnMainThread()
        Logger.info("")

        finishRecordingVoiceMessage(sendImmediately: false)
    }

    func sendVoiceMemoDraft(_ voiceMemoDraft: VoiceMessageInterruptedDraft) {
        AssertIsOnMainThread()

        sendVoiceMessageDraft(voiceMemoDraft)
    }

    public func saveDraft() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        if !inputToolbar.isHidden {
            let thread = self.thread
            let currentDraft = inputToolbar.messageBodyForSending
            let quotedReply = inputToolbar.quotedReplyDraft
            let editTarget = inputToolbar.editTarget
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                // Reload a fresh instance of the thread model; our models are not
                // thread-safe, so it wouldn't be safe to update the model in an
                // async write.
                guard let thread = TSThread.anyFetch(uniqueId: thread.uniqueId, transaction: transaction) else {
                    owsFailDebug("Missing thread.")
                    return
                }

                let didChange = Self.draftHasChanged(
                    currentDraft: currentDraft,
                    quotedReply: quotedReply,
                    editTarget: editTarget,
                    thread: thread,
                    transaction: transaction
                )

                // Persist the draft only if its changed. This avoids unnecessary model changes.
                guard didChange else {
                    return
                }

                let replyInfo: ThreadReplyInfo?
                if
                    let quotedReply,
                    let originalMessageTimestamp = quotedReply.originalMessageTimestamp,
                    let aci = quotedReply.originalMessageAuthorAddress.aci
                {
                    replyInfo = ThreadReplyInfo(
                        timestamp: originalMessageTimestamp,
                        author: aci
                    )
                } else {
                    replyInfo = nil
                }

                let editTargetTimestamp: UInt64? = inputToolbar.editTarget?.timestamp

                thread.updateWithDraft(
                    draftMessageBody: currentDraft,
                    replyInfo: replyInfo,
                    editTargetTimestamp: editTargetTimestamp,
                    transaction: transaction
                )
            }
        }
    }

    private static func draftHasChanged(
        currentDraft: MessageBody?,
        quotedReply: DraftQuotedReplyModel?,
        editTarget: TSOutgoingMessage?,
        thread: TSThread,
        transaction: DBReadTransaction
    ) -> Bool {
        let currentText = currentDraft?.text ?? ""
        let persistedText = thread.messageDraft ?? ""
        if currentText != persistedText {
            return true
        }

        let currentRanges = currentDraft?.ranges.mentions ?? [:]
        let persistedRanges = thread.messageDraftBodyRanges?.mentions ?? [:]
        if currentRanges != persistedRanges {
            return true
        }

        if
            let threadTimestamp = thread.editTargetTimestamp,
            threadTimestamp.uint64Value != editTarget?.timestamp ?? 0
        {
            return true
        }

        let threadReplyInfoStore = DependenciesBridge.shared.threadReplyInfoStore
        let persistedQuotedReply = threadReplyInfoStore.fetch(for: thread.uniqueId, tx: transaction)
        if quotedReply?.originalMessageTimestamp != persistedQuotedReply?.timestamp {
            return true
        }
        if quotedReply?.originalMessageAuthorAddress.aci != persistedQuotedReply?.author {
            return true
        }
        return false
    }

    @MainActor
    func tryToSendAttachments(
        _ attachments: [SignalAttachment],
        from viewController: UIViewController,
        messageBody: MessageBody?
    ) async throws(SendAttachmentError) {
        try await tryToSendAttachments(
            attachments,
            from: viewController,
            messageBody: messageBody,
            untrustedThreshold: Date().addingTimeInterval(-OWSIdentityManagerImpl.Constants.defaultUntrustedInterval)
        )
    }

    enum SendAttachmentError: Error {
        case inputToolbarNotReady
        case inputToolbarMissing
        case conversationBlocked
        case untrustedContacts
        case invalidAttachment(SignalAttachment)
    }

    @MainActor
    private func tryToSendAttachments(
        _ attachments: [SignalAttachment],
        from viewController: UIViewController,
        messageBody: MessageBody?,
        untrustedThreshold: Date
    ) async throws(SendAttachmentError) {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            throw .inputToolbarNotReady
        }
        guard let inputToolbar = inputToolbar else {
            throw .inputToolbarMissing
        }

        if self.isBlockedConversation() {
            let isBlocked = await self.showUnblockConversationUI()
            guard !isBlocked else {
                throw .conversationBlocked
            }
        }

        let newUntrustedThreshold = Date()
        let identityIsConfirmed = await self.showSafetyNumberConfirmationIfNecessary(
            from: viewController,
            confirmationText: SafetyNumberStrings.confirmSendButton,
            untrustedThreshold: newUntrustedThreshold
        )

        guard identityIsConfirmed else {
            throw .untrustedContacts
        }

        if let attachment = attachments.first(where: \.hasError) {
            throw .invalidAttachment(attachment)
        }

        let didAddToProfileWhitelist = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(self.thread)

        let hasViewOnceAttachment = attachments.contains(where: { $0.isViewOnceAttachment })
        owsPrecondition(!hasViewOnceAttachment || messageBody == nil)
        owsPrecondition(!hasViewOnceAttachment || inputToolbar.quotedReplyDraft == nil)

        ThreadUtil.enqueueMessage(
            body: messageBody,
            mediaAttachments: attachments,
            thread: self.thread,
            quotedReplyDraft: inputToolbar.quotedReplyDraft,
            persistenceCompletionHandler: {
                AssertIsOnMainThread()
                self.loadCoordinator.enqueueReload()
            }
        )

        self.messageWasSent()

        if didAddToProfileWhitelist {
            self.ensureBannerState()
        }

        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    // MARK: - Accessory View

    public func cameraButtonPressed() {
        AssertIsOnMainThread()

        takePictureOrVideo()
    }

    public func photosButtonPressed() {
        AssertIsOnMainThread()

        chooseFromLibrary()
    }

    public func gifButtonPressed() {
        AssertIsOnMainThread()

        showGifPicker()
    }

    public func fileButtonPressed() {
        AssertIsOnMainThread()

        showDocumentPicker()
    }

    public func contactButtonPressed() {
        AssertIsOnMainThread()

        chooseContactForSending()
    }

    public func locationButtonPressed() {
        AssertIsOnMainThread()

        let locationPicker = LocationPicker()
        locationPicker.delegate = self
        let navigationController = OWSNavigationController(rootViewController: locationPicker)
        navigationController.presentationController?.delegate = self
        dismissKeyBoard()
        presentFormSheet(navigationController, animated: true)
    }

    public func paymentButtonPressed() {
        AssertIsOnMainThread()

        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Not a contact thread.")
            return
        }

        dismissKeyBoard()

        if SUIEnvironment.shared.paymentsRef.isKillSwitchActive {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_CANNOT_SEND_PAYMENTS_KILL_SWITCH",
                                                                      comment: "Error message indicating that payments cannot be sent because the feature is not currently available."))
            return
        }

        if SSKEnvironment.shared.paymentsHelperRef.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .cantSendPayment)
            return
        }

        SendPaymentViewController.presentFromConversationView(
            self,
            delegate: self,
            recipientAddress: contactThread.contactAddress,
            initialPaymentAmount: nil,
            isOutgoingTransfer: false
        )
    }

    public func pollButtonPressed() {
        AssertIsOnMainThread()

        if !FeatureFlags.pollSend {
            return
        }

        dismissKeyBoard()

        let newPollViewController = NewPollViewController()
        newPollViewController.sendDelegate = self
        present(newPollViewController, animated: true)
    }

    public func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment) {
        AssertIsOnMainThread()

        dismissKeyBoard()

        let pickerModal = SendMediaNavigationController.showingApprovalWithPickedLibraryMedia(
            asset: asset,
            attachment: attachment,
            hasQuotedReplyDraft: inputToolbar?.quotedReplyDraft != nil,
            delegate: self,
            dataSource: self
        )
        let presenter = self.splitViewController ?? self
        presenter.present(pickerModal, animated: true)
    }
}

// MARK: -

public extension ConversationViewController {

    func showErrorAlert(forAttachment attachment: SignalAttachment?) {
        AssertIsOnMainThread()
        owsAssertDebug(attachment == nil || attachment?.hasError == true)

        let errorMessage = (attachment?.localizedErrorDescription
                                ?? SignalAttachment.missingDataErrorMessage)

        Logger.error("\(errorMessage)")

        OWSActionSheets.showActionSheet(title: OWSLocalizedString("ATTACHMENT_ERROR_ALERT_TITLE",
                                                                 comment: "The title of the 'attachment error' alert."),
                                        message: errorMessage)
    }

    func showApprovalDialog(forAttachments attachments: [SignalAttachment]) {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        let modal = AttachmentApprovalViewController.wrappedInNavController(
            attachments: attachments,
            initialMessageBody: inputToolbar.messageBodyForSending,
            hasQuotedReplyDraft: inputToolbar.quotedReplyDraft != nil,
            approvalDelegate: self,
            approvalDataSource: self,
            stickerSheetDelegate: self
        )
        modal.modalPresentationStyle = .overCurrentContext
        let presenter = self.splitViewController ?? self
        presenter.present(modal, animated: true)
    }
}

// MARK: -

fileprivate extension ConversationViewController {

    // MARK: - Attachment Picking: Contacts

    func chooseContactForSending() {
        AssertIsOnMainThread()

        dismissKeyBoard()
        SUIEnvironment.shared.contactsViewHelperRef.checkReadAuthorization(
            purpose: .share,
            performWhenAllowed: {
                let contactsPicker = ContactPickerViewController(allowsMultipleSelection: false, subtitleCellType: .none)
                contactsPicker.delegate = self
                contactsPicker.title = OWSLocalizedString(
                    "CONTACT_PICKER_TITLE",
                    comment: "navbar title for contact picker when sharing a contact"
                )
                let sheet = OWSNavigationController(rootViewController: contactsPicker)
                sheet.presentationController?.delegate = self
                self.presentFormSheet(sheet, animated: true)
            },
            presentErrorFrom: self
        )
    }

    // MARK: - Attachment Picking: Documents

    func showDocumentPicker() {
        AssertIsOnMainThread()

        // UIDocumentPickerViewController with asCopy true copies to a temp file within our container.
        // It uses more memory than "open" but lets us avoid working with security scoped URLs.
        let pickerController = UIDocumentPickerViewController(forOpeningContentTypes: [.item],
                                                              asCopy: true)
        pickerController.delegate = self
        pickerController.presentationController?.delegate = self

        dismissKeyBoard()
        presentFormSheet(pickerController, animated: true)
    }

    // MARK: - Media Library

    func takePictureOrVideo() {
        AssertIsOnMainThread()

        ows_askForCameraPermissions { [weak self] cameraGranted in
            guard let self = self else { return }
            guard cameraGranted else {
                Logger.warn("camera permission denied.")
                return
            }
            self.ows_askForMicrophonePermissions { [weak self] micGranted in
                guard let self = self else { return }
                if !micGranted {
                    Logger.warn("proceeding, though mic permission denied.")
                    // We can still continue without mic permissions, but any captured video will
                    // be silent.
                }

                let pickerModal = SendMediaNavigationController.showingCameraFirst(
                    hasQuotedReplyDraft: self.inputToolbar?.quotedReplyDraft != nil,
                )
                pickerModal.sendMediaNavDelegate = self
                pickerModal.sendMediaNavDataSource = self
                pickerModal.modalPresentationStyle = .overFullScreen
                // Defer hiding status bar until modal is fully onscreen
                // to prevent unwanted shifting upwards of the entire presenter VC's view.
                let pickerHidesStatusBar = (pickerModal.topViewController?.prefersStatusBarHidden ?? false)
                if !pickerHidesStatusBar {
                    pickerModal.modalPresentationCapturesStatusBarAppearance = true
                }
                self.dismissKeyBoard()
                self.present(pickerModal, animated: true) {
                    if pickerHidesStatusBar {
                        pickerModal.modalPresentationCapturesStatusBarAppearance = true
                        pickerModal.setNeedsStatusBarAppearanceUpdate()
                    }
                }
            }
        }
    }

    func chooseFromLibrary() {
        AssertIsOnMainThread()

        let pickerModal = SendMediaNavigationController.showingNativePicker(
            hasQuotedReplyDraft: inputToolbar?.quotedReplyDraft != nil,
        )
        pickerModal.sendMediaNavDelegate = self
        pickerModal.sendMediaNavDataSource = self

        self.dismissKeyBoard()
        let presenter = self.splitViewController ?? self
        presenter.present(pickerModal, animated: false)
    }
}

// MARK: - Attachment Picking: GIFs

public extension ConversationViewController {
    func showGifPicker() {
        let gifModal = GifPickerNavigationViewController(
            initialMessageBody: inputToolbar?.messageBodyForSending,
            hasQuotedReplyDraft: inputToolbar?.quotedReplyDraft != nil,
        )
        gifModal.approvalDelegate = self
        gifModal.approvalDataSource = self
        gifModal.presentationController?.delegate = self
        dismissKeyBoard()
        present(gifModal, animated: true)
    }
}

// MARK: -

extension ConversationViewController: LocationPickerDelegate {

    public func didPickLocation(_ locationPicker: LocationPicker, location: Location) {
        AssertIsOnMainThread()

        Task { @MainActor in
            let attachment: SignalAttachment
            do {
                attachment = try await location.prepareAttachment()
            } catch {
                owsFailDebug("Error: \(error).")
                return
            }

            // TODO: Can we move this off the main thread?

            let didAddToProfileWhitelist = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(self.thread)

            ThreadUtil.enqueueMessage(
                body: MessageBody(text: location.messageText, ranges: .empty),
                mediaAttachments: [attachment],
                thread: self.thread,
                persistenceCompletionHandler: {
                    AssertIsOnMainThread()
                    self.loadCoordinator.enqueueReload()
                }
            )

            self.messageWasSent()

            if didAddToProfileWhitelist {
                self.ensureBannerState()
            }

            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        }
    }

    public func locationPickerDidCancel() {
        self.dismiss(animated: true)
        self.openAttachmentKeyboard()
    }
}

// MARK: -

extension ConversationViewController: UIDocumentPickerDelegate {
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.openAttachmentKeyboard()
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        Logger.debug("Picked document at url: \(url)")

        let contentType: UTType = {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey])
                guard let contentType = resourceValues.contentType else {
                    owsFailDebug("Missing contentType.")
                    return .data
                }
                return contentType
            } catch {
                owsFailDebug("Error: \(error)")
                return .data
            }
        }()
        let isDirectory: Bool = {
            do {
                let resourceValues = try url.resourceValues(forKeys: Set([
                    .isDirectoryKey
                ]))
                guard let isDirectory = resourceValues.isDirectory else {
                    owsFailDebug("Missing isDirectory.")
                    return false
                }
                return isDirectory
            } catch {
                owsFailDebug("Error: \(error)")
                return false
            }
        }()

        if isDirectory {
            Logger.info("User picked directory.")

            DispatchQueue.main.async {
                OWSActionSheets.showActionSheet(title: OWSLocalizedString("ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE",
                                                                         comment: "Alert title when picking a document fails because user picked a directory/bundle"),
                                                message: OWSLocalizedString("ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY",
                                                                           comment: "Alert body when picking a document fails because user picked a directory/bundle"))
            }
            return
        }

        let filename: String = {
            if let filename = url.lastPathComponent.strippedOrNil {
                return filename
            }
            owsFailDebug("Unable to determine filename")
            return OWSLocalizedString("ATTACHMENT_DEFAULT_FILENAME",
                                     comment: "Generic filename for an attachment with no known name")
        }()

        func buildDataSource() -> DataSource? {
            do {
                return try DataSourcePath(fileUrl: url, shouldDeleteOnDeallocation: false)
            } catch {
                owsFailDebug("Error: \(error).")
                return nil
            }
        }
        guard let dataSource = buildDataSource() else {
            DispatchQueue.main.async {
                OWSActionSheets.showActionSheet(title: OWSLocalizedString("ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
                                                                         comment: "Alert title when picking a document fails for an unknown reason"))
            }
            return
        }
        dataSource.sourceFilename = filename

        // Although we want to be able to send higher quality attachments through the document picker
        // it's more important that we ensure the sent format is one all clients can accept (e.g. *not* quicktime .mov)
        if SignalAttachment.isVideoThatNeedsCompression(dataSource: dataSource,
                                                        dataUTI: contentType.identifier) {
            self.showApprovalDialogAfterProcessingVideoURL(url, filename: filename)
            return
        }

        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: contentType.identifier)
        showApprovalDialog(forAttachments: [attachment])
    }

    private func showApprovalDialogAfterProcessingVideoURL(_ movieURL: URL, filename: String?) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: true) { modalActivityIndicator in
            let dataSource: DataSource
            do {
                dataSource = try DataSourcePath(fileUrl: movieURL, shouldDeleteOnDeallocation: false)
            } catch {
                owsFailDebug("Error: \(error).")

                DispatchQueue.main.async {
                    self.showErrorAlert(forAttachment: nil)
                }
                return
            }

            dataSource.sourceFilename = filename
            let promise = Promise.wrapAsync({
                return try await SignalAttachment.compressVideoAsMp4(dataSource: dataSource,
                                                                     dataUTI: UTType.mpeg4Movie.identifier)
            })
            promise.done(on: DispatchQueue.main) { (attachment: SignalAttachment) in
                if modalActivityIndicator.wasCancelled {
                    return
                }
                modalActivityIndicator.dismiss {
                    if attachment.hasError {
                        owsFailDebug("Invalid attachment: \(attachment.errorName ?? "Unknown error").")
                        self.showErrorAlert(forAttachment: attachment)
                    } else {
                        self.showApprovalDialog(forAttachments: [attachment])
                    }
                }
            }.catch(on: DispatchQueue.main) { error in
                owsFailDebug("Error: \(error).")

                modalActivityIndicator.dismiss {
                    owsFailDebug("Invalid attachment.")
                    self.showErrorAlert(forAttachment: nil)
                }
            }
        }
    }
}

// MARK: -

extension ConversationViewController: SendMediaNavDelegate {
    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
        self.dismiss(animated: true, completion: nil)
        self.openAttachmentKeyboard()
    }

    func sendMediaNav(
        _ sendMediaNavigationController: SendMediaNavigationController,
        didApproveAttachments attachments: [SignalAttachment],
        messageBody: MessageBody?
    ) {
        Task { @MainActor in
            await self.sendAttachments(
                attachments,
                from: sendMediaNavigationController,
                messageBody: messageBody
            )
        }
    }

    /// Attempts to send attachments. Handles prompting to unblock or un-verify safety numbers, as well as showing failure states.
    @MainActor
    func sendAttachments(
        _ attachments: [SignalAttachment],
        from viewController: UIViewController,
        messageBody: MessageBody?
    ) async {
        do throws(SendAttachmentError) {
            try await tryToSendAttachments(
                attachments,
                from: viewController,
                messageBody: messageBody
            )

            if attachments.count == 1, let attachment = attachments.first, attachment.isBorderless {
                // This looks like a sticker, we shouldn't clear the input toolbar.
            } else {
                inputToolbar?.clearTextMessage(animated: false)
            }

            // we want to already be at the bottom when the user returns, rather than have to watch
            // the new message scroll into view.
            scrollToBottomOfConversation(animated: true)
            self.dismiss(animated: true)
        } catch {
            switch error {
            case .inputToolbarNotReady:
                owsFailDebug("InputToolbar not yet ready.")
            case .inputToolbarMissing:
                owsFailDebug("Missing inputToolbar.")
            case .conversationBlocked, .untrustedContacts:
                // User was prompted but chose not to make changes. Stop here.
                break
            case .invalidAttachment(let attachment):
                Logger.warn("Invalid attachment: \(attachment.errorName ?? "Missing data").")
                self.showErrorAlert(forAttachment: attachment)
            }
        }
    }

    func sendMediaNav(_ sendMediaNavifationController: SendMediaNavigationController,
                      didFinishWithTextAttachment textAttachment: UnsentTextAttachment) {
        owsFailDebug("Can not post text stories to chat.")
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController,
                      didChangeMessageBody newMessageBody: MessageBody?) {
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

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeViewOnceState isViewOnce: Bool) {
        // We can ignore this event.
    }
}

// MARK: -

extension ConversationViewController: SendMediaNavDataSource {

    func sendMediaNavInitialMessageBody(_ sendMediaNavigationController: SendMediaNavigationController) -> MessageBody? {
        inputToolbar?.messageBodyForSending
    }

    var sendMediaNavTextInputContextIdentifier: String? { textInputContextIdentifier }

    var sendMediaNavRecipientNames: [String] {
        let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx) }
        return [displayName]
    }

    func sendMediaNavMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        supportsMentions ? thread.recipientAddresses(with: SDSDB.shimOnlyBridge(tx)) : []
    }

    func sendMediaNavMentionCacheInvalidationKey() -> String {
        return thread.uniqueId
    }
}

// MARK: - StickerPickerSheetDelegate

extension ConversationViewController: StickerPickerSheetDelegate {
    public func makeManageStickersViewController() -> UIViewController {
        let manageStickersView = ManageStickersViewController()
        let navigationController = OWSNavigationController(rootViewController: manageStickersView)
        return navigationController
    }
}

// MARK: - PollSendDelegate

extension ConversationViewController: PollSendDelegate {
    public func sendPoll(question: String, options: [String], allowMultipleVotes: Bool) {
        ThreadUtil.enqueueMessage(
            withPoll:
                OWSPoll(
                    // We don't know the pollID yet since it hasn't been inserted in the DB.
                    // That is OK since this OWSPoll instance will not be used to re-render
                    // the conversation view (when pollID is needed to determine equatability).
                    pollId: 0,
                    question: question,
                    options: options,
                    allowsMultiSelect: allowMultipleVotes,
                    votes: [:],
                    isEnded: false
                ),
            thread: self.thread
        )
    }
}
