//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
public import SignalUI

extension ConversationViewController {
    public func updateNavigationTitle() {
        AssertIsOnMainThread()

        self.title = nil

        if thread.isNoteToSelf {
            headerView.titleIcon = Theme.iconImage(.official)
            headerView.titleIconSize = 16
        } else {
            headerView.titleIcon = nil
        }

        let attributedName = NSMutableAttributedString(
            string: threadViewModel.name,
            attributes: [
                .foregroundColor: Theme.primaryTextColor
            ]
        )

        if conversationViewModel.isSystemContact {
            let contactIcon = SignalSymbol.personCircle.attributedString(
                dynamicTypeBaseSize: 14,
                weight: .bold,
                leadingCharacter: .space
            )
            attributedName.append(contactIcon)
        }

        if headerView.attributedTitle != attributedName {
            headerView.attributedTitle = attributedName
        }
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
            showDebugUIForThread(thread, fromViewController: self)
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
            owsAssertDebug(navigationItem.searchController != nil)
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

                    if conversationViewModel.groupCallInProgress {
                        let pill = JoinGroupCallPill()
                        pill.addTarget(
                            self,
                            action: #selector(showGroupLobbyOrActiveCall),
                            for: .touchUpInside
                        )
                        let returnString = OWSLocalizedString(
                            "RETURN_CALL_PILL_BUTTON",
                            comment: "Button to return to current group call"
                        )
                        pill.buttonText = self.isCurrentCallForThread ? returnString : CallStrings.joinCallPillButtonTitle
                        videoCallButton.customView = pill
                    } else {
                        videoCallButton.image = Theme.iconImage(.buttonVideoCall)
                        videoCallButton.target = self
                        videoCallButton.action = #selector(showGroupLobbyOrActiveCall)
                    }

                    videoCallButton.isEnabled = (
                        AppEnvironment.shared.callService.callServiceState.currentCall == nil
                        || self.isCurrentCallForThread
                    )
                    videoCallButton.accessibilityLabel = OWSLocalizedString(
                        "VIDEO_CALL_LABEL",
                        comment: "Accessibility label for placing a video call"
                    )
                    self.groupCallBarButtonItem = videoCallButton
                    barButtons.append(videoCallButton)
                } else {
                    let audioCallButton = UIBarButtonItem(
                        image: Theme.iconImage(.buttonVoiceCall),
                        style: .plain,
                        target: self,
                        action: #selector(startIndividualAudioCall)
                    )
                    audioCallButton.isEnabled = AppEnvironment.shared.callService.callServiceState.currentCall == nil
                    audioCallButton.accessibilityLabel = OWSLocalizedString(
                        "VOICE_CALL_LABEL",
                        comment: "Accessibility label for placing a voice call"
                    )
                    barButtons.append(audioCallButton)

                    let videoCallButton = UIBarButtonItem(
                        image: Theme.iconImage(.buttonVideoCall),
                        style: .plain,
                        target: self,
                        action: #selector(startIndividualVideoCall)
                    )
                    videoCallButton.isEnabled = AppEnvironment.shared.callService.callServiceState.currentCall == nil
                    videoCallButton.accessibilityLabel = OWSLocalizedString(
                        "VIDEO_CALL_LABEL",
                        comment: "Accessibility label for placing a video call"
                    )
                    barButtons.append(videoCallButton)
                }
            }

            navigationItem.rightBarButtonItems = barButtons
            showGroupCallTooltipIfNecessary()
            return
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
        let isVerified = conversationViewModel.shouldShowVerifiedBadge

        if isMuted {
            subtitleText.appendTemplatedImage(named: "bell-slash-compact", font: subtitleFont)
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

            subtitleText.appendTemplatedImage(named: Theme.iconName(.timer16), font: subtitleFont)
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

            subtitleText.append(SignalSymbol.safetyNumber.attributedString(staticFontSize: subtitleFont.pointSize))

            subtitleText.append(iconSpacer, attributes: attributes)
            subtitleText.append(
                SafetyNumberStrings.verified,
                attributes: attributes
            )
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
        voiceMemoDraft: VoiceMessageInterruptedDraft?,
        editTarget: TSOutgoingMessage?
    ) -> ConversationInputToolbar {
        AssertIsOnMainThread()
        owsAssertDebug(hasViewWillAppearEverBegun)

        let quotedReply: DraftQuotedReplyModel?
        if let draftReply = draftReply {
            quotedReply = buildDraftQuotedReply(draftReply)
        } else {
            quotedReply = nil
        }

        let inputToolbar = ConversationInputToolbar(
            conversationStyle: conversationStyle,
            spoilerState: viewState.spoilerState,
            mediaCache: mediaCache,
            messageDraft: messageDraft,
            quotedReplyDraft: quotedReply,
            editTarget: editTarget,
            inputToolbarDelegate: self,
            inputTextViewDelegate: self,
            mentionDelegate: self
        )
        inputToolbar.accessibilityIdentifier = "inputToolbar"
        if let voiceMemoDraft = voiceMemoDraft {
            inputToolbar.showVoiceMemoDraft(voiceMemoDraft)
        }

        return inputToolbar
    }

    func buildDraftQuotedReply(_ draftReply: ThreadReplyInfo) -> DraftQuotedReplyModel? {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            guard let interaction = try? InteractionFinder.interactions(
                withTimestamp: draftReply.timestamp,
                filter: { candidate in
                    if let incoming = candidate as? TSIncomingMessage {
                        return incoming.authorAddress.aci == draftReply.author
                    }
                    if candidate is TSOutgoingMessage {
                        return DependenciesBridge.shared.tsAccountManager
                            .localIdentifiers(tx: transaction.asV2Read)?.aci == draftReply.author
                    }
                    return false
                },
                transaction: transaction
            ).first as? TSMessage else {
                return nil
            }
            if interaction is OWSPaymentMessage {
                return DraftQuotedReplyModel.fromOriginalPaymentMessage(interaction, tx: transaction)
            }
            return DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReply(
                originalMessage: interaction,
                tx: transaction.asV2Read
            )

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
