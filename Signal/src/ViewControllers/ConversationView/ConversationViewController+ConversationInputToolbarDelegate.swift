//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import Photos
import SignalMessaging
import SignalUI

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

        BenchManager.startEvent(title: "Send Message Milestone: clearTextMessageAnimated",
                                eventId: "fromSendUntil_clearTextMessageAnimated")

        tryToSendTextMessage(messageBody, updateKeyboardState: true)
    }

    public func messageWasSent(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("")
        }

        self.lastMessageSentDate = Date()

        loadCoordinator.clearUnreadMessagesIndicator()
        inputToolbar?.quotedReply = nil

        if self.preferences.soundInForeground,
           let soundId = Sounds.systemSoundIDForSound(.standard(.messageSent), quiet: true) {
            AudioServicesPlaySystemSound(soundId)
        }
        Self.typingIndicatorsImpl.didSendOutgoingMessage(inThread: thread)
    }

    private func tryToSendTextMessage(_ messageBody: MessageBody, updateKeyboardState: Bool) {
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
                    self?.tryToSendTextMessage(messageBody, updateKeyboardState: false)
                }
            }
            return
        }

        let didShowSNAlert = showSafetyNumberConfirmationIfNecessary(
            confirmationText: SafetyNumberStrings.confirmSendButton
        ) { [weak self] didConfirmIdentity in
            guard let self = self else { return }
            if didConfirmIdentity {
                self.tryToSendTextMessage(messageBody, updateKeyboardState: false)
            }
        }
        if didShowSNAlert {
            return
        }

        guard !messageBody.text.isEmpty else {
            return
        }

        let didAddToProfileWhitelist = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)

        let message = Self.databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(
                body: messageBody,
                thread: self.thread,
                quotedReplyModel: inputToolbar.quotedReply,
                linkPreviewDraft: inputToolbar.linkPreviewDraft,
                editTarget: inputToolbar.editTarget,
                persistenceCompletionHandler: {
                    AssertIsOnMainThread()
                    self.loadCoordinator.enqueueReload()
                },
                transaction: transaction
            )
        }

        // TODO: Audit optimistic insertion.
        loadCoordinator.appendUnsavedOutgoingTextMessage(message)
        messageWasSent(message)

        // Clearing the text message is a key part of the send animation.
        // It takes 10-15ms, but we do it inline rather than dispatch async
        // since the send can't feel "complete" without it.
        BenchManager.bench(title: "clearTextMessageAnimated") {
            inputToolbar.clearTextMessage(animated: true)
        }
        BenchManager.completeEvent(eventId: "fromSendUntil_clearTextMessageAnimated")

        let thread = self.thread
        Self.databaseStorage.asyncWrite { transaction in
            // Reload a fresh instance of the thread model; our models are not
            // thread-safe, so it wouldn't be safe to update the model in an
            // async write.
            guard let thread = TSThread.anyFetch(uniqueId: thread.uniqueId, transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return
            }
            thread.update(withDraft: nil,
                          replyInfo: nil,
                          transaction: transaction)
        }

        if didAddToProfileWhitelist {
            ensureBannerState()
        }

        NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
    }

    public func sendSticker(_ stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        Logger.verbose("Sending sticker.")

        ImpactHapticFeedback.impactOccurred(style: .light)

        let message = ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, thread: thread)
        messageWasSent(message)
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
            let quotedReply = inputToolbar.quotedReply
            Self.databaseStorage.asyncWrite { transaction in
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
                    thread: thread,
                    transaction: transaction
                )

                // Persist the draft only if its changed. This avoids unnecessary model changes.
                guard didChange else {
                    return
                }

                let replyInfo: ThreadReplyInfoObjC?
                if let quotedReply, let serviceId = quotedReply.authorAddress.serviceId {
                    replyInfo = ThreadReplyInfoObjC(ThreadReplyInfo(timestamp: quotedReply.timestamp, author: serviceId))
                } else {
                    replyInfo = nil
                }
                thread.update(withDraft: currentDraft, replyInfo: replyInfo, transaction: transaction)
            }
        }
    }

    private static func draftHasChanged(
        currentDraft: MessageBody?,
        quotedReply: QuotedReplyModel?,
        thread: TSThread,
        transaction: SDSAnyReadTransaction
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

        let threadReplyInfoStore = DependenciesBridge.shared.threadReplyInfoStore
        let persistedQuotedReply = threadReplyInfoStore.fetch(for: thread.uniqueId, tx: transaction.asV2Read)
        if quotedReply?.timestamp != persistedQuotedReply?.timestamp {
            return true
        }
        if quotedReply?.authorAddress.serviceId != persistedQuotedReply?.author {
            return true
        }
        return false
    }

    public func tryToSendAttachments(_ attachments: [SignalAttachment],
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

        DispatchMainThreadSafe {
            if self.isBlockedConversation() {
                self.showUnblockConversationUI { [weak self] isBlocked in
                    if !isBlocked {
                        self?.tryToSendAttachments(attachments, messageBody: messageBody)
                    }
                }
                return
            }

            let didShowSNAlert = self.showSafetyNumberConfirmationIfNecessary(
                confirmationText: SafetyNumberStrings.confirmSendButton) { [weak self] didConfirmIdentity in
                if didConfirmIdentity {
                    self?.tryToSendAttachments(attachments, messageBody: messageBody)
                }
            }
            if didShowSNAlert {
                return
            }

            for attachment in attachments {
                if attachment.hasError {
                    Logger.warn("Invalid attachment: \(attachment.errorName ?? "Missing data").")
                    self.showErrorAlert(forAttachment: attachment)
                    return
                }
            }

            let didAddToProfileWhitelist = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(self.thread)

            let message = Self.databaseStorage.read { transaction in
                ThreadUtil.enqueueMessage(
                    body: messageBody,
                    mediaAttachments: attachments,
                    thread: self.thread,
                    quotedReplyModel: inputToolbar.quotedReply,
                    editTarget: inputToolbar.editTarget,
                    persistenceCompletionHandler: {
                        AssertIsOnMainThread()
                        self.loadCoordinator.enqueueReload()
                    },
                    transaction: transaction
                )
            }

            self.messageWasSent(message)

            if didAddToProfileWhitelist {
                self.ensureBannerState()
            }

            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        }
    }

    // MARK: - Accessory View

    public func cameraButtonPressed() {
        AssertIsOnMainThread()

        takePictureOrVideo()
    }

    public func galleryButtonPressed() {
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
        dismissKeyBoard()
        presentFormSheet(navigationController, animated: true)
    }

    public func paymentButtonPressed() {
        AssertIsOnMainThread()

        showSendPaymentUI(paymentRequestModel: nil)
    }

    public func showSendPaymentUI(paymentRequestModel: TSPaymentRequestModel?) {
        AssertIsOnMainThread()

        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Not a contact thread.")
            return
        }

        dismissKeyBoard()

        if payments.isKillSwitchActive {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_CANNOT_SEND_PAYMENTS_KILL_SWITCH",
                                                                      comment: "Error message indicating that payments cannot be sent because the feature is not currently available."))
            return
        }

        if paymentsHelper.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .cantSendPayment)
            return
        }

        SendPaymentViewController.presentFromConversationView(self,
                                                              delegate: self,
                                                              recipientAddress: contactThread.contactAddress,
                                                              paymentRequestModel: paymentRequestModel,
                                                              initialPaymentAmount: nil,
                                                              isOutgoingTransfer: false)
    }

    public func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment) {
        AssertIsOnMainThread()

        dismissKeyBoard()

        let pickerModal = SendMediaNavigationController.showingApprovalWithPickedLibraryMedia(asset: asset,
                                                                                              attachment: attachment,
                                                                                              delegate: self,
                                                                                              dataSource: self)
        presentFullScreen(pickerModal, animated: true)
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

    func showApprovalDialog(forAttachment attachment: SignalAttachment?) {
        AssertIsOnMainThread()

        guard let attachment = attachment else {
            owsFailDebug("attachment was unexpectedly nil")
            showErrorAlert(forAttachment: attachment)
            return
        }
        showApprovalDialog(forAttachments: [ attachment ])
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

        let modal = AttachmentApprovalViewController.wrappedInNavController(attachments: attachments,
                                                                            initialMessageBody: inputToolbar.messageBodyForSending,
                                                                            approvalDelegate: self,
                                                                            approvalDataSource: self)
        presentFullScreen(modal, animated: true)
    }
}

// MARK: -

fileprivate extension ConversationViewController {

    // MARK: - Attachment Picking: Contacts

    func chooseContactForSending() {
        AssertIsOnMainThread()

        dismissKeyBoard()
        contactsViewHelper.checkSharingAuthorization(
            purpose: .share,
            authorizedBehavior: .runAction({
                let contactsPicker = ContactsPicker(allowsMultipleSelection: false, subtitleCellType: .none)
                contactsPicker.contactsPickerDelegate = self
                contactsPicker.title = OWSLocalizedString(
                    "CONTACT_PICKER_TITLE",
                    comment: "navbar title for contact picker when sharing a contact"
                )
                self.presentFormSheet(OWSNavigationController(rootViewController: contactsPicker), animated: true)
            }),
            unauthorizedBehavior: .presentError(from: self)
        )
    }

    // MARK: - Attachment Picking: Documents

    func showDocumentPicker() {
        AssertIsOnMainThread()

        let documentTypes: [String] = [ kUTTypeItem as String ]

        // UIDocumentPickerModeImport copies to a temp file within our container.
        // It uses more memory than "open" but lets us avoid working with security scoped URLs.
        let pickerMode: UIDocumentPickerMode = .import

        let pickerController = UIDocumentPickerViewController(documentTypes: documentTypes,
                                                              in: pickerMode)
        pickerController.delegate = self

        dismissKeyBoard()
        presentFormSheet(pickerController, animated: true)
    }

    // MARK: - Media Library

    func takePictureOrVideo() {
        AssertIsOnMainThread()

        BenchManager.startEvent(title: "Show-Camera", eventId: "Show-Camera")
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

                let pickerModal = SendMediaNavigationController.showingCameraFirst()
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

        BenchManager.startEvent(title: "Show-Media-Library", eventId: "Show-Media-Library")

        ows_askForMediaLibraryPermissions { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                Logger.warn("Media Library permission denied.")
                return
            }

            let pickerModal = SendMediaNavigationController.showingMediaLibraryFirst()
            pickerModal.sendMediaNavDelegate = self
            pickerModal.sendMediaNavDataSource = self

            self.dismissKeyBoard()
            self.presentFullScreen(pickerModal, animated: true)
        }
    }
}

// MARK: - Attachment Picking: GIFs

public extension ConversationViewController {
    func showGifPicker() {
        let gifModal = GifPickerNavigationViewController(initialMessageBody: inputToolbar?.messageBodyForSending)
        gifModal.approvalDelegate = self
        gifModal.approvalDataSource = self
        dismissKeyBoard()
        present(gifModal, animated: true)
    }
}

// MARK: -

extension ConversationViewController: LocationPickerDelegate {

    public func didPickLocation(_ locationPicker: LocationPicker, location: Location) {
        AssertIsOnMainThread()

        Logger.verbose("Sending location share.")

        firstly(on: DispatchQueue.global()) { () -> Promise<SignalAttachment> in
            location.prepareAttachment()
        }.done(on: DispatchQueue.main) { [weak self] attachment in
            // TODO: Can we move this off the main thread?
            AssertIsOnMainThread()

            guard let self = self else { return }

            let didAddToProfileWhitelist = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(self.thread)

            let message = Self.databaseStorage.read { transaction in
                ThreadUtil.enqueueMessage(body: MessageBody(text: location.messageText,
                                                            ranges: .empty),
                                          mediaAttachments: [ attachment ],
                                          thread: self.thread,
                                          persistenceCompletionHandler: {
                                                AssertIsOnMainThread()
                                                self.loadCoordinator.enqueueReload()
                                          },
                                          transaction: transaction)
            }

            self.messageWasSent(message)

            if didAddToProfileWhitelist {
                self.ensureBannerState()
            }

            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error).")
        }
    }
}

// MARK: -

extension ConversationViewController: UIDocumentPickerDelegate {

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        Logger.debug("Picked document at url: \(url)")

        let typeIdentifier: String = {
            do {
                let resourceValues = try url.resourceValues(forKeys: Set([
                    .typeIdentifierKey
                ]))
                guard let typeIdentifier = resourceValues.typeIdentifier else {
                    owsFailDebug("Missing typeIdentifier.")
                    return kUTTypeData as String
                }
                return typeIdentifier
            } catch {
                owsFailDebug("Error: \(error)")
                return kUTTypeData as String
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
                return try DataSourcePath.dataSource(with: url,
                                                     shouldDeleteOnDeallocation: false)
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
                                                        dataUTI: typeIdentifier) {
            self.showApprovalDialogAfterProcessingVideoURL(url, filename: filename)
            return
        }

        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: typeIdentifier)
        showApprovalDialog(forAttachment: attachment)
    }

    private func showApprovalDialogAfterProcessingVideoURL(_ movieURL: URL, filename: String?) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: true) { modalActivityIndicator in
            let dataSource: DataSource
            do {
                dataSource = try DataSourcePath.dataSource(with: movieURL, shouldDeleteOnDeallocation: false)
            } catch {
                owsFailDebug("Error: \(error).")

                DispatchQueue.main.async {
                    self.showErrorAlert(forAttachment: nil)
                }
                return
            }

            dataSource.sourceFilename = filename
            let (promise, session) = SignalAttachment.compressVideoAsMp4(dataSource: dataSource,
                                                                         dataUTI: kUTTypeMPEG4 as String)
            firstly { () -> Promise<SignalAttachment> in
                promise
            }.done(on: DispatchQueue.main) { (attachment: SignalAttachment) in
                if modalActivityIndicator.wasCancelled {
                    session?.cancelExport()
                    return
                }
                modalActivityIndicator.dismiss {
                    if attachment.hasError {
                        owsFailDebug("Invalid attachment: \(attachment.errorName ?? "Unknown error").")
                        self.showErrorAlert(forAttachment: attachment)
                    } else {
                        self.showApprovalDialog(forAttachment: attachment)
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
        // Restore status bar visibility (if current VC hides it) so that
        // there's no visible UI updates in the presenter.
        if sendMediaNavigationController.topViewController?.prefersStatusBarHidden ?? false {
            sendMediaNavigationController.modalPresentationCapturesStatusBarAppearance = false
            sendMediaNavigationController.setNeedsStatusBarAppearanceUpdate()
        }
        self.dismiss(animated: true, completion: nil)
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController,
                      didApproveAttachments attachments: [SignalAttachment],
                      messageBody: MessageBody?) {
        tryToSendAttachments(attachments, messageBody: messageBody)
        inputToolbar?.clearTextMessage(animated: false)
        // we want to already be at the bottom when the user returns, rather than have to watch
        // the new message scroll into view.
        scrollToBottomOfConversation(animated: true)
        self.dismiss(animated: true, completion: nil)
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
        [ Self.contactsManager.displayNameWithSneakyTransaction(thread: thread) ]
    }

    func sendMediaNavMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        supportsMentions ? thread.recipientAddresses(with: SDSDB.shimOnlyBridge(tx)) : []
    }

    func sendMediaNavMentionCacheInvalidationKey() -> String {
        return thread.uniqueId
    }
}
