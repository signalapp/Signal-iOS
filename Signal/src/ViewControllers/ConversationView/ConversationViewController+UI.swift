//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

extension ConversationViewController {
    public func updateNavigationTitle() {
        AssertIsOnMainThread()

        self.title = nil

        var name: String?
        var attributedName: NSAttributedString?
        var icon: UIImage?
        if let contactThread = thread as? TSContactThread {
            if thread.isNoteToSelf {
                name = MessageStrings.noteToSelf
            } else {
                name = contactsManager.displayName(for: contactThread.contactAddress)
            }

            // If the user is in the system contacts, show a badge
            let isSystemContact = databaseStorage.read { transaction in
                contactsManagerImpl.isSystemContact(address: contactThread.contactAddress, transaction: transaction)
            }
            if isSystemContact {
                icon = UIImage(named: "contact-outline-16")?.withRenderingMode(.alwaysTemplate)
            }
        } else if let groupThread = thread as? TSGroupThread {
            name = groupThread.groupNameOrDefault
        } else {
            owsFailDebug("Invalid thread.")
        }

        self.headerView.titleIcon = icon

        if nil == attributedName,
           let unattributedName = name {
            attributedName = NSAttributedString(string: unattributedName,
                                                attributes: [
                                                    .foregroundColor: Theme.primaryTextColor
                                                ])
        }

        if attributedName == headerView.attributedTitle {
            return
        }
        headerView.attributedTitle = attributedName
    }

    public func createHeaderViews() {
        AssertIsOnMainThread()

        headerView.configure(threadViewModel: threadViewModel)
        headerView.accessibilityLabel = OWSLocalizedString("CONVERSATION_SETTINGS",
                                                          comment: "title for conversation settings screen")
        headerView.accessibilityIdentifier = "headerView"
        headerView.delegate = self
        navigationItem.titleView = headerView

        if shouldUseDebugUI() {
            headerView.addGestureRecognizer(UILongPressGestureRecognizer(
                target: self,
                action: #selector(navigationTitleLongPressed)
            ))
        }

        updateNavigationBarSubtitleLabel()
    }

    @objc
    private func navigationTitleLongPressed(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()

        if gestureRecognizer.state == .began {
            showDebugUI(thread, self)
        }
    }

    public var unreadCountViewDiameter: CGFloat { 16 }

    public func updateBarButtonItems() {
        AssertIsOnMainThread()

        // Don't include "Back" text on view controllers pushed above us, just use the arrow.
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "",
                                                           style: .plain,
                                                           target: nil,
                                                           action: nil)

        navigationItem.hidesBackButton = false
        navigationItem.leftBarButtonItem = nil
        self.groupCallBarButtonItem = nil

        switch uiMode {
        case .search:
            if self.userLeftGroup {
                navigationItem.rightBarButtonItems = []
                return
            }
            if #available(iOS 13, *) {
                owsAssertDebug(navigationItem.searchController != nil)
            } else {
                navigationItem.rightBarButtonItems = []
                navigationItem.leftBarButtonItem = nil
                navigationItem.hidesBackButton = true
            }
            return
        case .selection:
            navigationItem.rightBarButtonItems = [ self.cancelSelectionBarButtonItem ]
            navigationItem.leftBarButtonItem = self.deleteAllBarButtonItem
            navigationItem.hidesBackButton = true
            return
        case .normal:
            if self.userLeftGroup {
                navigationItem.rightBarButtonItems = []
                return
            }
            var barButtons = [UIBarButtonItem]()
            if self.canCall {
                if self.isGroupConversation {
                    let videoCallButton = UIBarButtonItem()

                    if threadViewModel.groupCallInProgress {
                        let pill = JoinGroupCallPill()
                        pill.addTarget(self,
                                       action: #selector(showGroupLobbyOrActiveCall),
                                       for: .touchUpInside)
                        let returnString = OWSLocalizedString("RETURN_CALL_PILL_BUTTON",
                                                             comment: "Button to return to current group call")
                        let joinString = OWSLocalizedString("JOIN_CALL_PILL_BUTTON",
                                                           comment: "Button to join an active group call")
                        pill.buttonText = self.isCurrentCallForThread ? returnString : joinString
                        videoCallButton.customView = pill
                    } else {
                        videoCallButton.image = Theme.iconImage(.videoCall)
                        videoCallButton.target = self
                        videoCallButton.action = #selector(showGroupLobbyOrActiveCall)
                    }

                    videoCallButton.isEnabled = (self.callService.currentCall == nil
                                                    || self.isCurrentCallForThread)
                    videoCallButton.accessibilityLabel = OWSLocalizedString("VIDEO_CALL_LABEL",
                                                                           comment: "Accessibility label for placing a video call")
                    self.groupCallBarButtonItem = videoCallButton
                    barButtons.append(videoCallButton)
                } else {
                    let audioCallButton = UIBarButtonItem(
                        image: Theme.iconImage(.audioCall),
                        style: .plain,
                        target: self,
                        action: #selector(startIndividualAudioCall)
                    )
                    audioCallButton.isEnabled = !CurrentAppContext().hasActiveCall
                    audioCallButton.accessibilityLabel = OWSLocalizedString("AUDIO_CALL_LABEL",
                                                                           comment: "Accessibility label for placing an audio call")
                    barButtons.append(audioCallButton)

                    let videoCallButton = UIBarButtonItem(
                        image: Theme.iconImage(.videoCall),
                        style: .plain,
                        target: self,
                        action: #selector(startIndividualVideoCall)
                    )
                    videoCallButton.isEnabled = !CurrentAppContext().hasActiveCall
                    videoCallButton.accessibilityLabel = OWSLocalizedString("VIDEO_CALL_LABEL",
                                                                           comment: "Accessibility label for placing a video call")
                    barButtons.append(videoCallButton)
                }
            }

            navigationItem.rightBarButtonItems = barButtons
            showGroupCallTooltipIfNecessary()
            return
        }
    }

    private func shouldShowVerifiedBadge(for thread: TSThread) -> Bool {
        switch thread {
        case let groupThread as TSGroupThread:
            if groupThread.groupModel.groupMembers.isEmpty {
                return false
            }
            return !Self.identityManager.groupContainsUnverifiedMember(groupThread.uniqueId)

        case let contactThread as TSContactThread:
            return Self.identityManager.verificationState(for: contactThread.contactAddress) == .verified

        default:
            owsFailDebug("Showing conversation for unexpected thread type.")
            return false
        }
    }

    public func updateNavigationBarSubtitleLabel() {
        AssertIsOnMainThread()

        let hasCompactHeader = self.traitCollection.verticalSizeClass == .compact
        if hasCompactHeader {
            self.headerView.attributedSubtitle = nil
            return
        }

        let subtitleText = NSMutableAttributedString()
        let subtitleFont = self.headerView.subtitleFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: Theme.navbarTitleColor.withAlphaComponent(0.9)
        ]
        let hairSpace = "\u{200a}"
        let thinSpace = "\u{2009}"
        let iconSpacer = UIDevice.current.isNarrowerThanIPhone6 ? hairSpace : thinSpace
        let betweenItemSpacer = UIDevice.current.isNarrowerThanIPhone6 ? " " : "  "

        let isMuted = threadViewModel.isMuted
        let hasTimer = disappearingMessagesConfiguration.isEnabled
        let isVerified = shouldShowVerifiedBadge(for: thread)

        if isMuted {
            subtitleText.appendTemplatedImage(named: "bell-disabled-outline-24", font: subtitleFont)
            if !isVerified {
                subtitleText.append(iconSpacer, attributes: attributes)
                subtitleText.append(OWSLocalizedString("MUTED_BADGE",
                                                      comment: "Badge indicating that the user is muted."),
                                    attributes: attributes)
            }
        }

        if hasTimer {
            if isMuted {
                subtitleText.append(betweenItemSpacer, attributes: attributes)
            }

            subtitleText.appendTemplatedImage(named: "timer-outline-16", font: subtitleFont)
            subtitleText.append(iconSpacer, attributes: attributes)
            subtitleText.append(DateUtil.formatDuration(
                seconds: disappearingMessagesConfiguration.durationSeconds,
                useShortFormat: true
            ),
            attributes: attributes)
        }

        if isVerified {
            if hasTimer || isMuted {
                subtitleText.append(betweenItemSpacer, attributes: attributes)
            }

            subtitleText.appendTemplatedImage(named: "check-12", font: subtitleFont)
            subtitleText.append(iconSpacer, attributes: attributes)
            subtitleText.append(OWSLocalizedString("PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                  comment: "Badge indicating that the user is verified."),
                                attributes: attributes)
        }

        headerView.attributedSubtitle = subtitleText
    }

    public var safeContentHeight: CGFloat {
        // Don't use self.collectionView.contentSize.height as the collection view's
        // content size might not be set yet.
        //
        // We can safely call prepareLayout to ensure the layout state is up-to-date
        // since our layout uses a dirty flag internally to debounce redundant work.
        collectionView.collectionViewLayout.collectionViewContentSize.height
    }

    func buildInputToolbar(
        conversationStyle: ConversationStyle,
        messageDraft: MessageBody?,
        draftReply: ThreadReplyInfo?,
        voiceMemoDraft: VoiceMessageInterruptedDraft?
    ) -> ConversationInputToolbar {
        AssertIsOnMainThread()
        owsAssertDebug(hasViewWillAppearEverBegun)

        let quotedReply: OWSQuotedReplyModel?
        if let draftReply = draftReply {
            quotedReply = buildQuotedReply(draftReply)
        } else {
            quotedReply = nil
        }

        let inputToolbar = ConversationInputToolbar(conversationStyle: conversationStyle,
                                                    mediaCache: mediaCache,
                                                    messageDraft: messageDraft,
                                                    quotedReply: quotedReply,
                                                    inputToolbarDelegate: self,
                                                    inputTextViewDelegate: self,
                                                    mentionDelegate: self)
        inputToolbar.accessibilityIdentifier = "inputToolbar"
        if let voiceMemoDraft = voiceMemoDraft {
            inputToolbar.showVoiceMemoDraft(voiceMemoDraft)
        }

        return inputToolbar
    }

    // When responding to a message and quoting it, the input toolbar needs an OWSQuotedReplyModel.
    // Building this is a little tricky because we're putting a square peg in a round hole, and this method helps.
    // Historically, a quoted reply comes from an already-rendered message that's available at the moment that you
    // choose to reply to a message via the UI. For saved drafts, that UI component may not exist.
    // This method re-creates the steps that the app goes through when constructing a quoted reply from a message
    // by making a temporary `CVComponentState`. The ThreadReplyInfo identifies the message being responded to.
    // Since timestamps aren't unique, this is nondeterministic when things go wrong.
    func buildQuotedReply(_ draftReply: ThreadReplyInfo) -> OWSQuotedReplyModel? {
        return Self.databaseStorage.read { transaction in
            guard let interaction = try? InteractionFinder.interactions(
                withTimestamp: draftReply.timestamp,
                filter: { candidate in
                    if let incoming = candidate as? TSIncomingMessage {
                        return incoming.authorAddress == draftReply.author
                    }
                    if candidate is TSOutgoingMessage {
                        return draftReply.author.isLocalAddress
                    }
                    return false
                },
                transaction: transaction
            ).first else {
                return nil
            }
            guard let componentState = CVLoader.buildStandaloneComponentState(interaction: interaction,
                                                                              transaction: transaction) else {
                owsFailDebug("Failed to create component state.")
                return nil
            }
            let wrapper = CVComponentStateWrapper(interaction: interaction,
                                                  componentState: componentState)
            return OWSQuotedReplyModel.quotedReplyForSending(withItem: wrapper,
                                                             transaction: transaction)

        }
    }

}
// MARK: - Keyboard Shortcuts

public extension ConversationViewController {
    func focusInputToolbar() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        inputToolbar.clearDesiredKeyboard()
        self.popKeyBoard()
    }

    func openAllMedia() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }

        self.showConversationSettingsAndShowAllMedia()
    }

    func openStickerKeyboard() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        inputToolbar.showStickerKeyboard()
    }

    func openAttachmentKeyboard() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        inputToolbar.showAttachmentKeyboard()
    }

    func openGifSearch() {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            owsFailDebug("InputToolbar not yet ready.")
            return
        }
        guard nil != inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        self.showGifPicker()
    }
}
