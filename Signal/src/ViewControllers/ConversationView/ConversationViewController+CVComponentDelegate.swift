//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PassKit
import QuickLook
import SignalMessaging
import SignalServiceKit
import SignalUI

extension ConversationViewController: CVComponentDelegate {

    public var componentDelegate: CVComponentDelegate { self }

    public var isConversationPreview: Bool { false }

    public var wallpaperBlurProvider: WallpaperBlurProvider? { backgroundContainer }

    public func enqueueReload() {
        self.loadCoordinator.enqueueReload()
    }

    public func enqueueReloadWithoutCaches() {
        self.loadCoordinator.enqueueReloadWithoutCaches()
    }

    // MARK: - Double tap

    public func didDoubleTapGeneralMessageItem(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        addOrRemoveEmojiFromDoubleTap(itemViewModel)
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
        if let message = itemViewModel.interaction as? TSMessage,
           message.wasRemotelyDeleted {
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

    public func didTapFailedOrPendingDownloads(_ message: TSMessage) {
        AssertIsOnMainThread()

        attachmentDownloads.enqueueDownloadOfAttachments(
            forMessageId: message.uniqueId,
            attachmentGroup: .allAttachmentsIncoming,
            downloadBehavior: .bypassAll,
            touchMessageImmediately: true,
            success: { _ in
                Logger.info("Successfully re-downloaded attachment.")
            },
            failure: { error in
                Logger.warn("Failed to redownload message with error: \(error)")
            }
        )
    }

    public func didTapBrokenVideo() {
        let toastText = NSLocalizedString("VIDEO_BROKEN",
                                          comment: "Toast alert text shown when tapping on a video that cannot be played.")
        presentToastCVC(toastText)
    }

    // MARK: - Messages

    public func didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                                attachmentStream: TSAttachmentStream,
                                imageView: UIView) {
        AssertIsOnMainThread()

        dismissKeyBoard()

        let pageVC = MediaPageViewController(initialMediaAttachment: attachmentStream,
                                             thread: self.thread)
        self.present(pageVC, animated: true, completion: nil)
    }

    public func didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction {
        AssertIsOnMainThread()

        if attachment.canQuickLook {
            let previewController = QLPreviewController()
            previewController.dataSource = attachment
            self.present(previewController, animated: true, completion: nil)
            return .handledByDelegate
        } else if PKAddPassesViewController.canAddPasses(),
                  let pkPass = attachment.representedPKPass(),
                  let addPassesVC = PKAddPassesViewController(pass: pkPass) {
            self.present(addPassesVC, animated: true, completion: nil)
            return .handledByDelegate
        } else {
            return .default
        }
    }

    public func didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel) {
        AssertIsOnMainThread()
        owsAssertDebug(quotedReply.timestamp > 0)
        owsAssertDebug(quotedReply.authorAddress.isValid)

        if quotedReply.isStory {
            guard let quotedStory = databaseStorage.read(
                block: { StoryFinder.story(timestamp: quotedReply.timestamp, author: quotedReply.authorAddress, transaction: $0) }
            ) else { return }

            let context: StoryContext
            if
                let contactUUID = self.threadViewModel.contactAddress?.uuid,
                quotedStory.authorAddress.isLocalAddress,
                case let .outgoing(recipientStates) = quotedStory.manifest,
                let recipientState = recipientStates[contactUUID],
                let validContext = recipientState.firstValidContext()
            {
                // If its an outgoing story from the local user and the contact
                // is in the recipient states, set the context to the first valid
                // context they are a part of.
                context = validContext
            } else {
                // Else fall back to thinking this is an incoming story from this contact.
                context = .authorUuid(quotedStory.authorUuid)
            }

            let vc = StoryPageViewController(context: context, loadMessage: quotedStory)
            presentFullScreen(vc, animated: true)
        } else {
            scrollToQuotedMessage(quotedReply, isAnimated: true)
        }
    }

    public func didTapLinkPreview(_ linkPreview: OWSLinkPreview) {
        AssertIsOnMainThread()

        guard let urlString = linkPreview.urlString,
              let url = URL(string: urlString) else {
            owsFailDebug("Invalid link preview URL.")
            return
        }

        if StickerPackInfo.isStickerPackShare(url) {
            if let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) {
                let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
                packView.present(from: self, animated: true)
                return
            } else {
                owsFailDebug("Could not parse sticker pack share URL: \(url)")
            }
        }

        if GroupManager.isPossibleGroupInviteLink(url) {
            didTapGroupInviteLink(url: url)
            return
        }

        if SignalProxy.isValidProxyLink(url) {
            didTapProxyLink(url: url)
            return
        }

        if SignalMe.isPossibleUrl(url) { return cvc_didTapSignalMeLink(url: url) }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    public func didTapContactShare(_ contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        let view = ContactViewController(contactShare: contactShare)
        navigationController?.pushViewController(view, animated: true)
    }

    public func didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.sendMessage(contactShare: contactShare, fromViewController: self)
    }

    public func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.showInviteContact(contactShare: contactShare, fromViewController: self)
    }

    public func didTapAddToContacts(contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.showAddToContacts(contactShare: contactShare, fromViewController: self)
    }

    public func didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
        packView.present(from: self, animated: true)
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

    public func cvc_didTapSignalMeLink(url: URL) {
        SignalMe.openChat(url: url, fromViewController: self)
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

        FingerprintViewController.present(from: self, address: address)
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

        let displayName = contactsManager.displayName(for: address)
        let messageFormat = NSLocalizedString("UNVERIFIED_SAFETY_NUMBER_CHANGE_DESCRIPTION_FORMAT",
                                              comment: "Description for the unverified safety number change. Embeds {name of contact with identity change}")

        let actionSheet = ActionSheetController(title: nil,
                                                message: String(format: messageFormat, displayName))
        actionSheet.customHeader = headerView

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("UNVERIFIED_SAFETY_NUMBER_VERIFY_ACTION",
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

        let keyOwner = contactsManager.displayName(for: message.theirSignalAddress())
        let titleFormat = NSLocalizedString("SAFETY_NUMBERS_ACTIONSHEET_TITLE", comment: "Action sheet heading")
        let titleText = String(format: titleFormat, keyOwner)

        let actionSheet = ActionSheetController(title: titleText, message: nil)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SHOW_SAFETY_NUMBER_ACTION",
                                                                         comment: "Action sheet item"),
                                                accessibilityIdentifier: "show_safety_number",
                                                style: .default) { [weak self] _ in
            Logger.info("Remote Key Changed actions: Show fingerprint display")
            self?.showFingerprint(address: message.theirSignalAddress())
        })

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("ACCEPT_NEW_IDENTITY_ACTION",
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

        let threadName = databaseStorage.read { transaction in
            Self.contactsManager.displayName(for: self.thread, transaction: transaction)
        }
        let alertMessage = String(format: NSLocalizedString("CORRUPTED_SESSION_DESCRIPTION",
                                                            comment: "ActionSheet title"),
                                  threadName)
        let alert = ActionSheetController(title: nil, message: alertMessage)

        alert.addAction(OWSActionSheets.cancelAction)

        alert.addAction(ActionSheetAction(title: NSLocalizedString("FINGERPRINT_SHRED_KEYMATERIAL_BUTTON",
                                                                   comment: ""),
                                          accessibilityIdentifier: "reset_session",
                                          style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let contactThread = self.thread as? TSContactThread else {
                // Corrupt Message errors only appear in contact threads.
                Logger.error("Unexpected request to reset session in group thread.")
                return
            }

            Self.databaseStorage.asyncWrite { transaction in
                Self.smJobQueues.sessionResetJobQueue.add(contactThread: contactThread, transaction: transaction)
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

        ContactSupportAlert.presentAlert(title: NSLocalizedString("SESSION_REFRESH_ALERT_TITLE",
                                                                  comment: "Title for the session refresh alert"),
                                         message: NSLocalizedString("SESSION_REFRESH_ALERT_MESSAGE",
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
        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            GroupManager.sendGroupUpdateMessage(thread: groupThread)
        }.done(on: DispatchQueue.global()) {
            Logger.info("Group updated, removing group creation error.")

            Self.databaseStorage.write { transaction in
                message.anyRemove(transaction: transaction)
            }
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
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

        let displayName = contactsManager.displayName(for: contactThread.contactAddress)

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

    public func didTapGroupCall() {
        AssertIsOnMainThread()

        showGroupLobbyOrActiveCall()
    }

    public func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()
        if spamChallengeResolver.isPausingMessages {
            SpamCaptchaViewController.presentActionSheet(from: self)
        } else {
            spamChallengeResolver.retryPausedMessagesIfReady()
        }

    }

    public func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()

        resendFailedOutgoingMessage(message)
    }

    public func didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                             oldGroupModel: TSGroupModel,
                                                             newGroupModel: TSGroupModel) {
        AssertIsOnMainThread()

        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        let actionSheet = GroupMigrationActionSheet.actionSheetForMigratedGroup(groupThread: groupThread,
                                                                                oldGroupModel: oldGroupModel,
                                                                                newGroupModel: newGroupModel)
        actionSheet.present(fromViewController: self)
    }

    public func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {
        AssertIsOnMainThread()

        showGroupLinkPromotionActionSheet()
    }

    public func didTapViewGroupDescription(groupModel: TSGroupModel?) {
        AssertIsOnMainThread()

        func getGroupModel() -> TSGroupModel? {
            if let groupModel = groupModel {
                return groupModel
            }
            if let groupThread = thread as? TSGroupThread {
                return groupThread.groupModel
            }
            return nil
        }
        guard let groupModel = getGroupModel() else {
            owsFailDebug("Unexpectedly missing group model.")
            return
        }

        let vc = GroupDescriptionViewController(groupModel: groupModel)
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
        requesterUuid: UUID
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
                    withGroupModel: groupModel,
                    updateDescription: "Blocking join request",
                    updateBlock: {
                        // If the user in question has canceled their request,
                        // this call will still block them.
                        GroupManager.acceptOrDenyMemberRequestsV2(
                            groupModel: groupModel,
                            uuids: [requesterUuid],
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

        let url = "https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8"
        UIApplication.shared.open(URL(string: url)!, options: [:], completionHandler: nil)
    }

    public func didTapUpdateSystemContact(_ address: SignalServiceAddress, newNameComponents: PersonNameComponents) {
        guard let navigationController else {
            return owsFailDebug("Missing navigationController.")
        }
        contactsViewHelper.checkEditingAuthorization(
            authorizedBehavior: .pushViewController(on: navigationController, viewController: {
                let result = self.contactsViewHelper.contactViewController(
                    for: address,
                    editImmediately: true,
                    addToExisting: nil,
                    updatedNameComponents: newNameComponents
                )
                result.delegate = self
                return result
            }),
            unauthorizedBehavior: .presentError(from: self)
        )
    }

    public func didTapPhoneNumberChange(uuid: UUID, phoneNumberOld: String, phoneNumberNew: String) {
        guard let navigationController else {
            return owsFailDebug("Missing navigationController.")
        }
        contactsViewHelper.checkEditingAuthorization(
            authorizedBehavior: .pushViewController(on: navigationController, viewController: {
                guard let existingContact: CNContact = self.databaseStorage.read(block: {
                    guard let contact = self.contactsManagerImpl.contact(forPhoneNumber: phoneNumberOld, transaction: $0) else { return nil }
                    return self.contactsManager.cnContact(withId: contact.cnContactId)
                }) else {
                    owsFailDebug("Missing existing contact for phone number change.")
                    return nil
                }

                let address = SignalServiceAddress(uuid: uuid, phoneNumber: phoneNumberNew)
                let result = self.contactsViewHelper.contactViewController(
                    for: address,
                    editImmediately: true,
                    addToExisting: existingContact,
                    updatedNameComponents: nil
                )
                result.delegate = self
                return result
            }),
            unauthorizedBehavior: .presentError(from: self)
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
}
