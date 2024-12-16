//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
import PassKit
import QuickLook
public import SignalServiceKit
public import SignalUI

extension ConversationViewController: CVComponentDelegate {

    public var componentDelegate: CVComponentDelegate { self }

    public var isConversationPreview: Bool { false }

    public var wallpaperBlurProvider: WallpaperBlurProvider? { backgroundContainer }

    public var spoilerState: SpoilerRenderState { return self.viewState.spoilerState }

    public func enqueueReload() {
        self.loadCoordinator.enqueueReload()
    }

    public func enqueueReloadWithoutCaches() {
        self.loadCoordinator.enqueueReloadWithoutCaches()
    }

    // MARK: - Double-Tap

    public func didDoubleTapTextViewItem(_ viewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        let controller = DoubleTapToEditOnboardingController(presentationContext: self) {
            self.messageActionsEditItem(viewModel)
        }

        controller.beginEditing(animated: true)
    }

    // MARK: - Long Press

    public func didLongPressTextViewItem(_ cell: CVCell,
                                         itemViewModel: CVItemViewModelImpl,
                                         shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.textActions(itemViewModel: itemViewModel,
                                                        shouldAllowReply: shouldAllowReply,
                                                        delegate: self)
        self.presentContextMenu(with: messageActions, focusedOn: cell, andModel: itemViewModel)
    }

    public func didLongPressMediaViewItem(_ cell: CVCell,
                                          itemViewModel: CVItemViewModelImpl,
                                          shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.mediaActions(itemViewModel: itemViewModel,
                                                         shouldAllowReply: shouldAllowReply,
                                                         delegate: self)
        self.presentContextMenu(with: messageActions, focusedOn: cell, andModel: itemViewModel)
    }

    public func didLongPressQuote(_ cell: CVCell,
                                  itemViewModel: CVItemViewModelImpl,
                                  shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.quotedMessageActions(itemViewModel: itemViewModel,
                                                                 shouldAllowReply: shouldAllowReply,
                                                                 delegate: self)
        self.presentContextMenu(with: messageActions, focusedOn: cell, andModel: itemViewModel)
    }

    public func didLongPressSystemMessage(_ cell: CVCell,
                                          itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.infoMessageActions(itemViewModel: itemViewModel,
                                                               delegate: self)
        self.presentContextMenu(with: messageActions, focusedOn: cell, andModel: itemViewModel)
    }

    public func didLongPressSticker(_ cell: CVCell,
                                    itemViewModel: CVItemViewModelImpl,
                                    shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.mediaActions(itemViewModel: itemViewModel,
                                                         shouldAllowReply: shouldAllowReply,
                                                         delegate: self)
        self.presentContextMenu(with: messageActions, focusedOn: cell, andModel: itemViewModel)
    }

    public func didLongPressPaymentMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool
    ) {
        let messageActions = MessageActions.paymentActions(
            itemViewModel: itemViewModel,
            shouldAllowReply: shouldAllowReply,
            delegate: self
        )
        self.presentContextMenu(with: messageActions, focusedOn: cell, andModel: itemViewModel)
    }

    public func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        collectionViewActiveContextMenuInteraction?.initiatingGestureRecognizerDidChange()
    }

    public func didEndLongPress(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        collectionViewActiveContextMenuInteraction?.initiatingGestureRecognizerDidEnd()
    }

    public func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        collectionViewActiveContextMenuInteraction?.initiatingGestureRecognizerDidEnd()
    }

    // MARK: -

    public func didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        populateReplyForMessage(itemViewModel)
    }

    public func didTapSenderAvatar(_ interaction: TSInteraction) {
        AssertIsOnMainThread()

        guard let incomingMessage = interaction as? TSIncomingMessage else {
            owsFailDebug("not an incoming message.")
            return
        }

        showMemberActionSheet(forAddress: incomingMessage.authorAddress, withHapticFeedback: false)
    }

    public func shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool {
        AssertIsOnMainThread()

        if thread.isGroupThread && !thread.isLocalUserFullMemberOfThread {
            return false
        }
        if self.threadViewModel.hasPendingMessageRequest {
            return false
        }
        if itemViewModel.wasRemotelyDeleted {
            return false
        }
        if itemViewModel.isSmsMessageRestoredFromBackup {
            return false
        }

        if let outgoingMessage = itemViewModel.interaction as? TSOutgoingMessage {
            if outgoingMessage.messageState == .failed {
                // Don't allow "delete" or "reply" on "failed" outgoing messages.
                return false
            } else if outgoingMessage.messageState == .sending {
                // Don't allow "delete" or "reply" on "sending" outgoing messages.
                return false
            } else if outgoingMessage.messageState == .pending {
                // Don't allow "delete" or "reply" on "sending" outgoing messages.
                return false
            }
        }

        return true
    }

    public func didTapReactions(reactionState: InteractionReactionState,
                                message: TSMessage) {
        AssertIsOnMainThread()

        if !reactionState.hasReactions {
            owsFailDebug("missing reaction state")
            return
        }

        let detailSheet = ReactionsDetailSheet(reactionState: reactionState, message: message)
        self.present(detailSheet, animated: true, completion: nil)
        self.reactionsDetailSheet = detailSheet
    }

    public var hasPendingMessageRequest: Bool {
        AssertIsOnMainThread()

        return self.threadViewModel.hasPendingMessageRequest
    }

    public func didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        expandTruncatedTextOrPresentLongTextView(itemViewModel)
    }

    public func didTapShowEditHistory(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let message = itemViewModel.interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return
        }

        let sheet = EditHistoryTableSheetViewController(
            message: message,
            threadViewModel: self.threadViewModel,
            spoilerState: viewState.spoilerState,
            editManager: self.context.editManager,
            database: SSKEnvironment.shared.databaseStorageRef,
            databaseChangeObserver: DependenciesBridge.shared.databaseChangeObserver
        )
        sheet.delegate = self
        self.present(sheet, animated: true)
    }

    public func didTapFailedOrPendingDownloads(_ message: TSMessage) {
        AssertIsOnMainThread()

        SSKEnvironment.shared.databaseStorageRef.write { tx in
            DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(
                message,
                priority: .userInitiated,
                tx: tx.asV2Write
            )
        }
    }

    public func didTapBrokenVideo() {
        let toastText = OWSLocalizedString("VIDEO_BROKEN",
                                           comment: "Toast alert text shown when tapping on a video that cannot be played.")
        presentToastCVC(toastText)
    }

    // MARK: - Messages

    public func didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachmentStream: ReferencedAttachmentStream,
        imageView: UIView
    ) {
        AssertIsOnMainThread()

        dismissKeyBoard()

        guard let pageVC = MediaPageViewController(
            initialMediaAttachment: attachmentStream,
            thread: self.thread,
            spoilerState: self.viewState.spoilerState
        ) else {
            return
        }

        self.present(pageVC, animated: true, completion: nil)
    }

    public func didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction {
        AssertIsOnMainThread()

        if
            PKAddPassesViewController.canAddPasses(),
            let pkPass = attachment.representedPKPass(),
            let addPassesVC = PKAddPassesViewController(pass: pkPass)
        {
            self.present(addPassesVC, animated: true, completion: nil)
            return .handledByDelegate
        } else if let previewController = attachment.createQLPreviewController() {
            self.present(previewController, animated: true, completion: nil)
            return .handledByDelegate
        } else {
            return .default
        }
    }

    public func didTapQuotedReply(_ quotedReply: QuotedReplyModel) {
        AssertIsOnMainThread()
        owsAssertDebug(quotedReply.originalMessageAuthorAddress.isValid)

        if quotedReply.originalContent.isStory {
            guard
                let quotedStoryAuthorAci = quotedReply.originalMessageAuthorAddress.aci,
                let timestamp = quotedReply.originalMessageTimestamp
            else {
                return
            }
            guard let quotedStory = SSKEnvironment.shared.databaseStorageRef.read(
                block: { StoryFinder.story(timestamp: timestamp, author: quotedStoryAuthorAci, transaction: $0) }
            ) else { return }

            let context: StoryContext
            if
                let contactServiceId = self.threadViewModel.contactAddress?.serviceId,
                quotedStory.authorAddress.isLocalAddress,
                case let .outgoing(recipientStates) = quotedStory.manifest,
                let recipientState = recipientStates[contactServiceId],
                let validContext = recipientState.firstValidContext()
            {
                // If its an outgoing story from the local user and the contact
                // is in the recipient states, set the context to the first valid
                // context they are a part of.
                context = validContext
            } else {
                // Else fall back to thinking this is an incoming story from this contact.
                context = .authorAci(quotedStory.authorAci)
            }

            let vc = StoryPageViewController(
                context: context,
                spoilerState: spoilerState,
                loadMessage: quotedStory
            )
            presentFullScreen(vc, animated: true)
        } else {
            scrollToQuotedMessage(quotedReply, isAnimated: true)
        }
    }

    public func didTapLinkPreview(_ linkPreview: OWSLinkPreview) {
        AssertIsOnMainThread()

        guard
            let urlString = linkPreview.urlString,
            let url = URL(string: urlString)
        else {
            owsFailDebug("Invalid link preview URL.")
            return
        }

        self.handleUrl(url)
    }

    func handleUrl(_ url: URL) {
        if StickerPackInfo.isStickerPackShare(url) {
            if let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) {
                didTapStickerPack(stickerPackInfo)
            } else {
                owsFailDebug("Could not parse sticker pack share URL: \(url)")
            }
            return
        }

        if GroupManager.isPossibleGroupInviteLink(url) {
            didTapGroupInviteLink(url: url)
            return
        }

        if SignalProxy.isValidProxyLink(url) {
            didTapProxyLink(url: url)
            return
        }

        if SignalDotMePhoneNumberLink.isPossibleUrl(url) {
            cvc_didTapSignalMeLink(url: url)
            return
        }

        if let usernameLink = Usernames.UsernameLink(usernameLinkUrl: url) {
            didTapUsernameLink(usernameLink: usernameLink)
            return
        }

        if let callLink = CallLink(url: url) {
            didTapCallLink(callLink)
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    public func didTapContactShare(_ contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        let view = ContactViewController(contactShare: contactShare)
        navigationController?.pushViewController(view, animated: true)
    }

    public func didTapSendMessage(to phoneNumbers: [String]) {
        AssertIsOnMainThread()

        contactShareViewHelper.sendMessage(to: phoneNumbers, from: self)
    }

    public func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.showInviteContact(contactShare: contactShare, from: self)
    }

    public func didTapAddToContacts(contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.showAddToContactsPrompt(contactShare: contactShare, from: self)
    }

    public func didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
        packView.present(from: self, animated: true)
    }

    public func didTapPayment(_ payment: PaymentsHistoryItem) {
        AssertIsOnMainThread()

        let paymentsDetailViewController = PaymentsDetailViewController(
            paymentItem: payment
        )
        navigationController?.pushViewController(paymentsDetailViewController, animated: true)
    }

    public func didTapGroupInviteLink(url: URL) {
        AssertIsOnMainThread()
        owsAssertDebug(GroupManager.isPossibleGroupInviteLink(url))

        GroupInviteLinksUI.openGroupInviteLink(url, fromViewController: self)
    }

    public func didTapProxyLink(url: URL) {
        AssertIsOnMainThread()
        guard let vc = ProxyLinkSheetViewController(url: url) else { return }
        present(vc, animated: true)
    }

    func didTapCallLink(_ callLink: CallLink) {
        AssertIsOnMainThread()
        GroupCallViewController.presentLobby(for: callLink)
    }

    public func cvc_didTapSignalMeLink(url: URL) {
        SignalDotMePhoneNumberLink.openChat(url: url, fromViewController: self)
    }

    public func didTapUsernameLink(usernameLink: Usernames.UsernameLink) {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            UsernameQuerier().queryForUsernameLink(
                link: usernameLink,
                fromViewController: self,
                tx: tx,
                onSuccess: { _, aci in
                    SignalApp.shared.presentConversationForAddress(
                        SignalServiceAddress(aci),
                        animated: true
                    )
                }
            )
        }
    }

    public func didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {
        showDetailView(itemViewModel)
    }

    public func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {
        prepareDetailViewForInteractivePresentation(itemViewModel)
    }

    public func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        AssertIsOnMainThread()

        if maximumDuration > 0.8 {
            owsFailDebug("Animation is too long, skipping.")
            return {}
        }

        let identifier = UUID()
        viewState.beginCellAnimation(identifier: identifier)

        var timer: Timer?
        let endAnimation = { [weak self] in
            AssertIsOnMainThread()
            guard let self = self else { return }

            timer?.invalidate()
            self.viewState.endCellAnimation(identifier: identifier)
            self.loadCoordinator.enqueueReload()
        }

        // Automatically unblock loads once the max duration is reached, even
        // if the cell didn't tell us it finished.
        timer = Timer.scheduledTimer(withTimeInterval: maximumDuration, repeats: false) { _ in
            endAnimation()
        }

        return endAnimation
    }

    // MARK: - System Cell

    public func didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {
        AssertIsOnMainThread()

        showFingerprint(address: address)
    }

    public func showFingerprint(address: SignalServiceAddress) {
        AssertIsOnMainThread()

        // Ensure keyboard isn't hiding the "safety numbers changed" interaction when we
        // return from FingerprintViewController.
        dismissKeyBoard()

        let addressAci: Aci? = address.aci ?? {
            guard let phoneNumber = address.phoneNumber else {
                return nil
            }
            // Reload the address from disk if we lack an ACI.
            let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
            return SSKEnvironment.shared.databaseStorageRef.read { tx in
                return recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx.asV2Read)?.aci
            }
        }()

        FingerprintViewController.present(for: addressAci, from: self)
    }

    public func didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {
        AssertIsOnMainThread()
        owsAssertDebug(address.isValid)

        dismissKeyBoard()

        let headerImageView = UIImageView(image: UIImage(named: "safety-number-change"))
        let headerView = UIView()
        headerView.addSubview(headerImageView)
        headerImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 22)
        headerImageView.autoPinEdge(toSuperviewEdge: .bottom)
        headerImageView.autoHCenterInSuperview()
        headerImageView.autoSetDimension(.width, toSize: 200)
        headerImageView.autoSetDimension(.height, toSize: 110)

        let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }
        let messageFormat = OWSLocalizedString("UNVERIFIED_SAFETY_NUMBER_CHANGE_DESCRIPTION_FORMAT",
                                              comment: "Description for the unverified safety number change. Embeds {name of contact with identity change}")

        let actionSheet = ActionSheetController(title: nil,
                                                message: String(format: messageFormat, displayName))
        actionSheet.customHeader = headerView

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("UNVERIFIED_SAFETY_NUMBER_VERIFY_ACTION",
                                                                         comment: "Action to verify a safety number after it has changed"),
                                                style: .default) { [weak self] _ in
            self?.showFingerprint(address: address)
        })

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.notNowButton,
                                                style: .cancel,
                                                handler: nil))
        presentActionSheet(actionSheet)
    }

    public func didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage) {
        AssertIsOnMainThread()

        let keyOwner = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: message.theirSignalAddress(), tx: tx).resolvedValue()
        }
        let titleFormat = OWSLocalizedString("SAFETY_NUMBERS_ACTIONSHEET_TITLE", comment: "Action sheet heading")
        let titleText = String(format: titleFormat, keyOwner)

        let actionSheet = ActionSheetController(title: titleText, message: nil)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("SHOW_SAFETY_NUMBER_ACTION",
                                                                         comment: "Action sheet item"),
                                                accessibilityIdentifier: "show_safety_number",
                                                style: .default) { [weak self] _ in
            Logger.info("Remote Key Changed actions: Show fingerprint display")
            self?.showFingerprint(address: message.theirSignalAddress())
        })

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("ACCEPT_NEW_IDENTITY_ACTION",
                                                                         comment: "Action sheet item"),
                                                accessibilityIdentifier: "accept_safety_number",
                                                style: .default) { _ in
            Logger.info("Remote Key Changed actions: Accepted new identity key")

            // DEPRECATED: we're no longer creating these incoming SN error's per message,
            // but there will be some legacy ones in the wild, behind which await
            // as-of-yet-undecrypted messages
            if let errorMessage = message as? TSInvalidIdentityKeyReceivingErrorMessage {
                do {
                    _ = try errorMessage.acceptNewIdentityKey()
                } catch {
                    // Deliberately crash if the user fails to explicitly accept the new identity
                    // key. In practice we haven't been creating these messages in over a year.
                    owsFail("Error: \(error)")
                }
            }
        })

        dismissKeyBoard()
        self.presentActionSheet(actionSheet)
    }

    public func didTapCorruptedMessage(_ message: TSErrorMessage) {
        AssertIsOnMainThread()

        let threadName = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            SSKEnvironment.shared.contactManagerRef.displayName(for: self.thread, transaction: transaction)
        }
        let alertMessage = String(format: OWSLocalizedString("CORRUPTED_SESSION_DESCRIPTION",
                                                            comment: "ActionSheet title"),
                                  threadName)
        let alert = ActionSheetController(title: nil, message: alertMessage)

        alert.addAction(OWSActionSheets.cancelAction)

        alert.addAction(ActionSheetAction(title: OWSLocalizedString("FINGERPRINT_SHRED_KEYMATERIAL_BUTTON",
                                                                   comment: ""),
                                          accessibilityIdentifier: "reset_session",
                                          style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let contactThread = self.thread as? TSContactThread else {
                // Corrupt Message errors only appear in contact threads.
                Logger.error("Unexpected request to reset session in group thread.")
                return
            }

            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                SSKEnvironment.shared.smJobQueuesRef.sessionResetJobQueue.add(contactThread: contactThread, transaction: transaction)
            }
        })

        dismissKeyBoard()
        self.presentActionSheet(alert)
    }

    public func didTapSessionRefreshMessage(_ message: TSErrorMessage) {
        dismissKeyBoard()

        let headerImageView = UIImageView(image: UIImage(named: "chat-session-refresh"))

        let headerView = UIView()
        headerView.addSubview(headerImageView)
        headerImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 22)
        headerImageView.autoPinEdge(toSuperviewEdge: .bottom)
        headerImageView.autoHCenterInSuperview()
        headerImageView.autoSetDimension(.width, toSize: 200)
        headerImageView.autoSetDimension(.height, toSize: 110)

        ContactSupportAlert.presentAlert(title: OWSLocalizedString("SESSION_REFRESH_ALERT_TITLE",
                                                                  comment: "Title for the session refresh alert"),
                                         message: OWSLocalizedString("SESSION_REFRESH_ALERT_MESSAGE",
                                                                    comment: "Description for the session refresh alert"),
                                         emailSupportFilter: "Signal iOS Session Refresh",
                                         fromViewController: self,
                                         additionalActions: [
                                            ActionSheetAction(title: CommonStrings.okayButton,
                                                              accessibilityIdentifier: "okay",
                                                              style: .default,
                                                              handler: nil)
                                         ],
                                         customHeader: headerView,
                                         showCancel: false)
    }

    // See: resendGroupUpdate
    public func didTapResendGroupUpdateForErrorMessage(_ message: TSErrorMessage) {
        AssertIsOnMainThread()

        guard let groupThread = self.thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        Task {
            await GroupManager.sendGroupUpdateMessage(thread: groupThread)
            Logger.info("Group updated, removing group creation error.")

            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                DependenciesBridge.shared.interactionDeleteManager
                    .delete(message, sideEffects: .default(), tx: tx.asV2Write)
            }
        }
    }

    public func didTapShowFingerprint(_ address: SignalServiceAddress) {
        AssertIsOnMainThread()

        showFingerprint(address: address)
    }

    // MARK: -

    public func didTapIndividualCall(_ call: TSCall) {
        AssertIsOnMainThread()
        owsAssertDebug(self.inputToolbar != nil)

        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
        }

        let alert = ActionSheetController(title: CallStrings.callBackAlertTitle,
                                          message: String(format: CallStrings.callBackAlertMessageFormat,
                                                          displayName))

        alert.addAction(ActionSheetAction(title: CallStrings.callBackAlertCallButton,
                                          accessibilityIdentifier: "call_back",
                                          style: .default) { [weak self] _ in
            guard let self = self else { return }
            switch call.offerType {
            case .audio:
                self.startIndividualAudioCall()
            case .video:
                self.startIndividualVideoCall()
            }
        })
        alert.addAction(OWSActionSheets.cancelAction)

        inputToolbar?.clearDesiredKeyboard()
        dismissKeyBoard()
        self.presentActionSheet(alert)
    }

    public func didTapLearnMoreMissedCallFromBlockedContact(_ call: TSCall) {
        AssertIsOnMainThread()

        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        let address = contactThread.contactAddress
        let displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue() }

        let alert = ActionSheetController(
            title: String(
                format: OWSLocalizedString(
                    "MISSED_CALL_BLOCKED_SYSTEM_SETTINGS_SHEET_TITLE",
                    comment: "Title for sheet shown when the user taps a missed call from a contact blocked in iOS settings. Embeds {{ Contact's name }}"
                ),
                displayName
            ),
            message: OWSLocalizedString(
                "MISSED_CALL_BLOCKED_SYSTEM_SETTINGS_SHEET_MESSAGE",
                comment: "Message for sheet shown when the user taps a missed call from a contact blocked in iOS settings.")
        )

        alert.addAction(
            ActionSheetAction(
                title: OWSLocalizedString(
                    "MISSED_CALL_BLOCKED_SYSTEM_SETTINGS_SHEET_BLOCK_ACTION",
                    comment: "Action to block contact in Signal for sheet shown when the user taps a missed call from a contact blocked in iOS settings."
                ),
                accessibilityIdentifier: "block_contact",
                style: .destructive
            ) { [weak self] _ in
                guard self != nil else { return }
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    SSKEnvironment.shared.blockingManagerRef.addBlockedAddress(
                        address,
                        blockMode: .localShouldLeaveGroups,
                        transaction: tx
                    )
                }
            }
        )
        alert.addAction(OWSActionSheets.okayAction)

        inputToolbar?.clearDesiredKeyboard()
        dismissKeyBoard()
        self.presentActionSheet(alert)
    }

    public func didTapGroupCall() {
        AssertIsOnMainThread()

        showGroupLobbyOrActiveCall()
    }

    public func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()
        if SSKEnvironment.shared.spamChallengeResolverRef.isPausingMessages {
            SpamCaptchaViewController.presentActionSheet(from: self)
        } else {
            SSKEnvironment.shared.spamChallengeResolverRef.retryPausedMessagesIfReady()
        }

    }

    public func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()

        let promptBuilder = ResendMessagePromptBuilder(
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef
        )
        dismissKeyBoard()
        self.present(promptBuilder.build(for: message), animated: true)
    }

    public func didTapGroupMigrationLearnMore() {
        AssertIsOnMainThread()
        presentFormSheet(
            LegacyGroupLearnMoreViewController(mode: .explainNewGroups),
            animated: true
        )
    }

    public func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {
        AssertIsOnMainThread()

        showGroupLinkPromotionActionSheet()
    }

    public func didTapViewGroupDescription(newGroupDescription: String) {
        AssertIsOnMainThread()

        func getGroupModel() -> TSGroupModel? {
            if let groupThread = thread as? TSGroupThread {
                return groupThread.groupModel
            }
            return nil
        }
        guard let groupModel = getGroupModel() else {
            owsFailDebug("Unexpectedly missing group model.")
            return
        }

        let vc = GroupDescriptionViewController(
            groupModel: groupModel,
            groupDescriptionCurrent: newGroupDescription,
            options: []
        )
        let navigationController = OWSNavigationController(rootViewController: vc)
        self.presentFormSheet(navigationController, animated: true)
    }

    public func didTapShowConversationSettings() {
        AssertIsOnMainThread()

        showConversationSettings()
    }

    public func didTapShowConversationSettingsAndShowMemberRequests() {
        AssertIsOnMainThread()

        showConversationSettingsAndShowMemberRequests()
    }

    public func didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterAci: Aci
    ) {
        AssertIsOnMainThread()

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "GROUPS_BLOCK_REQUEST_SHEET_TITLE",
                comment: "Title for sheet asking if the user wants to block a request to join the group."
            ),
            message: String(
                format: OWSLocalizedString(
                    "GROUPS_BLOCK_REQUEST_SHEET_MESSAGE",
                    comment: "Message for sheet offering to let the user block a request to join the group. Embeds {{ the requester's name }}."
                ),
                requesterName
            ))

        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "GROUPS_BLOCK_REQUEST_SHEET_BLOCK_BUTTON",
                comment: "Label for button that will block a request to join a group."
            ),
            style: .default,
            handler: { _ in
                GroupViewUtils.updateGroupWithActivityIndicator(
                    fromViewController: self,
                    updateDescription: "Blocking join request",
                    updateBlock: {
                        // If the user in question has canceled their request,
                        // this call will still block them.
                        return try await GroupManager.acceptOrDenyMemberRequestsV2(
                            groupModel: groupModel,
                            aci: requesterAci,
                            shouldAccept: false
                        )
                    },
                    completion: nil
                )
            })
        )

        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    public func didTapShowUpgradeAppUI() {
        AssertIsOnMainThread()

        UIApplication.shared.open(TSConstants.appStoreUrl, options: [:], completionHandler: nil)
    }

    public func didTapUpdateSystemContact(_ address: SignalServiceAddress, newNameComponents: PersonNameComponents) {
        SUIEnvironment.shared.contactsViewHelperRef.presentSystemContactsFlow(
            CreateOrEditContactFlow(address: address, nameComponents: newNameComponents),
            from: self
        )
    }

    public func didTapPhoneNumberChange(aci: Aci, phoneNumberOld: String, phoneNumberNew: String) {
        SUIEnvironment.shared.contactsViewHelperRef.checkEditAuthorization(
            performWhenAllowed: {
                let existingContact: CNContact? = {
                    guard let cnContactId = SSKEnvironment.shared.contactManagerRef.cnContactId(for: phoneNumberOld) else {
                        return nil
                    }
                    return SSKEnvironment.shared.contactManagerRef.cnContact(withId: cnContactId)
                }()
                guard let existingContact else {
                    owsFailDebug("Missing existing contact for phone number change.")
                    return
                }

                let address = SignalServiceAddress(serviceId: aci, phoneNumber: phoneNumberNew)
                SUIEnvironment.shared.contactsViewHelperRef.presentSystemContactsFlow(
                    CreateOrEditContactFlow(address: address, contact: existingContact),
                    from: self
                )
            },
            presentErrorFrom: self
        )
    }

    public func didTapViewOnceAttachment(_ interaction: TSInteraction) {
        AssertIsOnMainThread()

        ViewOnceMessageViewController.tryToPresent(interaction: interaction, from: self)
    }

    public func didTapViewOnceExpired(_ interaction: TSInteraction) {
        AssertIsOnMainThread()

        if interaction is TSOutgoingMessage {
            presentViewOnceOutgoingToast()
        } else {
            presentViewOnceAlreadyViewedToast()
        }
    }

    public func didTapContactName(thread: TSContactThread) {
        AssertIsOnMainThread()
        ContactAboutSheet(thread: thread, spoilerState: self.spoilerState)
            .present(from: self)
    }

    public func didTapUnknownThreadWarningGroup() {
        AssertIsOnMainThread()

        showUnknownThreadWarningAlert()
    }

    public func didTapUnknownThreadWarningContact() {
        AssertIsOnMainThread()

        showUnknownThreadWarningAlert()
    }

    public func didTapDeliveryIssueWarning(_ message: TSErrorMessage) {
        AssertIsOnMainThread()
        guard let senderAddress = message.sender else {
            owsFailDebug("Expected a sender address")
            return
        }

        // If the error message was added to a group thread, we must know that the failed decryption was
        // associated with the current thread. Why?
        //
        // - If we fail to decrypt a message, the sender may have tagged the envelope with a groupId. That
        // groupId is used to look up the source thread and insert this error message.
        // - If there is no groupId on the envelope, we don't know anything about which thread the original
        // message belongs to, so we fall back to inserting this message in the author's 1:1 thread.
        // - There's no other information that would allow us to determine the originating thread other
        // that this groupId field.
        // - Therefore, if this error message was added to a group thread, we know we must have the right thread
        // thread. If it's not in a group thread, we can't infer anything about the thread of the original message.
        //
        // Maybe one day the envelope will be annotated with additional information to always allow us to tie
        // the failed decryption to the originating thread. But until then, this heuristic will always be correct.
        // There's no reason to add an additional bit to the interactions db to track whether or not we know
        // the originating thread.
        showDeliveryIssueWarningAlert(from: senderAddress, isKnownThread: thread.isGroupThread)
    }

    public func didTapActivatePayments() {
        AssertIsOnMainThread()
        SignalApp.shared.showAppSettings(mode: .payments)
    }

    public func didTapSendPayment() {
        AssertIsOnMainThread()
        // Same action as tapping on the attachment toolbar.
        paymentButtonPressed()
    }

    public func didTapThreadMergeLearnMore(phoneNumber: String) {
        guard let contactAddress = (thread as? TSContactThread)?.contactAddress else {
            owsFailDebug("Can't handle a merge event in a group.")
            return
        }
        let formattedMessage: String = {
            let formatString = OWSLocalizedString(
                "THREAD_MERGE_LEARN_MORE",
                comment: "Shown after tapping a 'Learn More' button when multiple conversations for the same person have been merged into one. The first parameter is a phone number (eg +1 650-555-0100) and the second parameter is a name (eg John)."
            )
            let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: phoneNumber)
            let shortDisplayName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerRef.displayName(for: contactAddress, tx: tx).resolvedValue(useShortNameIfAvailable: true)
            }
            return String(format: formatString, formattedPhoneNumber, shortDisplayName)
        }()
        let customHeader: UIView = {
            let imageView = UIImageView(image: UIImage(named: "merged-chat")!)
            imageView.contentMode = .scaleAspectFit
            imageView.autoSetDimensions(to: .square(88))

            let stackView = UIStackView()
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.layoutMargins = UIEdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0)
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.addArrangedSubview(imageView)
            return stackView
        }()
        let actionSheet = ActionSheetController(message: formattedMessage)
        actionSheet.customHeader = customHeader
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton))
        presentActionSheet(actionSheet)
    }

    public func didTapReportSpamLearnMore() {
        AssertIsOnMainThread()

        let alert = ActionSheetController(
            title: OWSLocalizedString(
                "INFO_MESSAGE_REPORTED_SPAM_LEARN_MORE_TITLE",
                comment: "Title of the alert shown when a user taps on 'learn more' via the spam info message."
            ),
            message: OWSLocalizedString(
                "INFO_MESSAGE_REPORTED_SPAM_LEARN_MORE_MESSAGE",
                comment: "Body message of the alert shown when a user taps on 'learn more' via the spam info message.")
        )
        alert.addAction(OWSActionSheets.okayAction)

        inputToolbar?.clearDesiredKeyboard()
        dismissKeyBoard()
        self.presentActionSheet(alert)
    }

    public func didTapMessageRequestAcceptedOptions() {
        AssertIsOnMainThread()

        let message: String
        if thread is TSContactThread {
            message = String(
                format: OWSLocalizedString(
                    "INFO_MESSAGE_ACCEPTED_MESSAGE_REQUEST_OPTIONS_ACTION_SHEET_HEADER_CONTACT",
                    comment: "Header for an action sheet providing options in response to an accepted 1:1 message request. Embeds {{ the name of your chat partner }}."
                ),
                threadViewModel.shortName ?? threadViewModel.name
            )
        } else if thread is TSGroupThread {
            message = OWSLocalizedString(
                "INFO_MESSAGE_ACCEPTED_MESSAGE_REQUEST_OPTIONS_ACTION_SHEET_HEADER_GROUP",
                comment: "Header for an action sheet providing options in response to an accepted group message request."
            )
        } else {
            return
        }

        let alert = ActionSheetController(
            message: message
        )
        alert.addAction(ActionSheetAction(
            title: String(
                format: OWSLocalizedString(
                    "MESSAGE_REQUEST_ACCEPTED_INFO_MESSAGE_SHEET_OPTION_BLOCK",
                    comment: "Sheet option for blocking a chat. In this case, the sheet appears when the user taps a button attached to a 'message request accepted' info message in-chat."
                )
            ),
            style: .default,
            handler: { [weak self] _ in
                guard let self else { return }

                let blockThreadActionSheet = createBlockThreadActionSheet()
                presentActionSheet(blockThreadActionSheet)
            }
        ))
        alert.addAction(ActionSheetAction(
            title: String(
                format: OWSLocalizedString(
                    "MESSAGE_REQUEST_ACCEPTED_INFO_MESSAGE_SHEET_OPTION_SPAM",
                    comment: "Sheet option for reporting a chat as spam. In this case, the sheet appears when the user taps a button attached to a 'message request accepted' info message in-chat."
                )
            ),
            style: .default,
            handler: { [weak self] _ in
                guard let self else { return }

                let reportThreadActionSheet = createReportThreadActionSheet()
                presentActionSheet(reportThreadActionSheet)
            }
        ))
        alert.addAction(ActionSheetAction(
            title: String(
                format: OWSLocalizedString(
                    "MESSAGE_REQUEST_ACCEPTED_INFO_MESSAGE_SHEET_OPTION_DELETE",
                    comment: "Sheet option for deleting a chat. In this case, the sheet appears when the user taps a button attached to a 'message request accepted' info message in-chat."
                )
            ),
            style: .default,
            handler: { [weak self] _ in
                guard let self else { return }

                let deleteThreadActionSheet = createDeleteThreadActionSheet()
                presentActionSheet(deleteThreadActionSheet)
            }
        ))
        alert.addAction(.cancel)

        inputToolbar?.clearDesiredKeyboard()
        dismissKeyBoard()
        presentActionSheet(alert)
    }

    public func didTapJoinCallLinkCall(callLink: CallLink) {
        GroupCallViewController.presentLobby(for: callLink)
    }
}
