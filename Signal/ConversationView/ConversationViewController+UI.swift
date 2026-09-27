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

        let title = threadViewModel.name

        // Important as it will be displayed in <Back button popup in view controllers
        // pushed over ConversationViewController.
        navigationItem.title = title

        headerView.titleIcon = thread.isNoteToSelf || thread.isReleaseNotesThread ? Theme.iconImage(.official) : nil

        if conversationViewModel.isSystemContact {
            // To ensure a single source of text color do not set `color` attributes unless you really need to.
            let contactIcon = SignalSymbol.personCircle.attributedString(
                dynamicTypeBaseSize: 14,
                weight: .bold,
                leadingCharacter: .space,
            )
            headerView.titleLabel.attributedText = NSAttributedString(string: title).stringByAppendingString(contactIcon)
        } else {
            headerView.titleLabel.text = title
        }

        headerView.updateTitleSpinning()
    }

    public func createHeaderViews() {
        AssertIsOnMainThread()

        headerView.configure(threadViewModel: threadViewModel)
        headerView.accessibilityLabel = OWSLocalizedString(
            "CONVERSATION_SETTINGS",
            comment: "title for conversation settings screen",
        )
        headerView.accessibilityIdentifier = "headerView"
        headerView.delegate = self
        navigationItem.titleView = headerView

#if USE_DEBUG_UI
        headerView.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self,
            action: #selector(navigationTitleLongPressed),
        ))
#endif

        updateNavigationBarSubtitleLabel()
    }

#if USE_DEBUG_UI
    @objc
    private func navigationTitleLongPressed(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()

        if gestureRecognizer.state == .began {
            DebugUITableViewController.presentDebugUI(
                fromViewController: self,
                thread: thread,
            )
        }
    }
#endif

    public var unreadCountViewDiameter: CGFloat { 16 }

    private class JoinGroupCallButton: UIButton {

        private var verticalMarginConstraint: NSLayoutConstraint?
        private let iconImageView = UIImageView()

        init(title: String, primaryAction: UIAction) {
            super.init(frame: .zero)

            addAction(primaryAction, for: .primaryActionTriggered)

            iconImageView.image = if #available(iOS 26, *) { .videoFill } else { .videoFill20 }
            iconImageView.tintColor = .white

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .dynamicTypeSubheadlineClamped.semibold()
            titleLabel.textColor = .white

            let stackView = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
            stackView.spacing = 4
            stackView.alignment = .center
            stackView.translatesAutoresizingMaskIntoConstraints = false

            let buttonContentView: UIView
            if #available(iOS 26, *) {
                buttonContentView = UIView()
            } else {
                buttonContentView = PillView()
                buttonContentView.backgroundColor = .Signal.green
            }

            buttonContentView.isUserInteractionEnabled = false
            buttonContentView.translatesAutoresizingMaskIntoConstraints = false
            buttonContentView.addSubview(stackView)
            // We're keeping the reference to this constraint to update it for compact vertical size classes.
            verticalMarginConstraint = stackView.topAnchor.constraint(equalTo: buttonContentView.topAnchor)
            NSLayoutConstraint.activate([
                verticalMarginConstraint!,
                stackView.centerYAnchor.constraint(equalTo: buttonContentView.centerYAnchor),

                // Can't use layout margins here because UIKit will mess those up during portrait-landscape rotation.
                stackView.leadingAnchor.constraint(equalTo: buttonContentView.leadingAnchor, constant: 12),
                stackView.centerXAnchor.constraint(equalTo: buttonContentView.centerXAnchor),
            ])

            addSubview(buttonContentView)
            NSLayoutConstraint.activate([
                buttonContentView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                buttonContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                buttonContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                buttonContentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            ])

            updateLayoutForCurrentTraitCollection()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass {
                updateLayoutForCurrentTraitCollection()
            }
        }

        private func updateLayoutForCurrentTraitCollection() {
            // iOS 26 doesn't shrink navigation bar vertically.
            guard #unavailable(iOS 26), let verticalMarginConstraint else { return }

            let isVerticallyCompact = traitCollection.verticalSizeClass == .compact
            iconImageView.image = isVerticallyCompact ? .videoFillCompact : .videoFill20
            verticalMarginConstraint.constant = isVerticallyCompact ? 4 : 8
        }
    }

    public func updateBarButtonItems() {
        AssertIsOnMainThread()

        guard !thread.isReleaseNotesThread else {
            return
        }

        if #unavailable(iOS 26) {
            // Don't include "Back" text on view controllers pushed above us, just use the arrow.
            // iOS 26 already doesn't show back button text
            navigationItem.backBarButtonItem = .button(title: "") {}
        }

        navigationItem.hidesBackButton = false
        navigationItem.leftBarButtonItem = nil
        groupCallBarButtonItem = nil

        switch uiMode {
        case .search:
            if userLeftGroup {
                navigationItem.rightBarButtonItems = []
                return
            }
            owsAssertDebug(navigationItem.searchController != nil)
            return

        case .selection:
            navigationItem.rightBarButtonItems = [cancelSelectionBarButtonItem]
            navigationItem.leftBarButtonItem = deleteAllBarButtonItem
            navigationItem.hidesBackButton = true
            return

        case .normal:
            if userLeftGroup {
                navigationItem.rightBarButtonItems = []
                return
            }
            var barButtons = [UIBarButtonItem]()
            if canCall {
                if isGroupConversation {
                    let videoCallButton = UIBarButtonItem()

                    if conversationViewModel.groupCallInProgress {
                        let buttonTitle = isCurrentCallForThread
                            ? OWSLocalizedString(
                                "RETURN_CALL_PILL_BUTTON",
                                comment: "Button to return to current group call",
                            )
                            : CallStrings.joinCallPillButtonTitle
                        videoCallButton.customView = JoinGroupCallButton(
                            title: buttonTitle,
                            primaryAction: UIAction { [weak self] _ in self?.showGroupLobbyOrActiveCall() },
                        )

                        if #available(iOS 26, *) {
                            videoCallButton.tintColor = UIColor.Signal.green
                            videoCallButton.style = .prominent
                        }
                    } else {
                        videoCallButton.primaryAction = UIAction(
                            image: Theme.iconImage(.buttonVideoCall),
                        ) { [weak self] _ in self?.showGroupLobbyOrActiveCall() }
                    }

                    videoCallButton.isEnabled = (
                        AppEnvironment.shared.callService.callServiceState.currentCall == nil
                            || isCurrentCallForThread,
                    )
                    videoCallButton.accessibilityLabel = OWSLocalizedString(
                        "VIDEO_CALL_LABEL",
                        comment: "Accessibility label for placing a video call",
                    )
                    groupCallBarButtonItem = videoCallButton
                    barButtons.append(videoCallButton)
                } else {
                    let audioCallButton = UIBarButtonItem.button(icon: .buttonVoiceCall) { [weak self] in
                        self?.startIndividualAudioCall()
                    }
                    audioCallButton.isEnabled = AppEnvironment.shared.callService.callServiceState.currentCall == nil
                    audioCallButton.accessibilityLabel = OWSLocalizedString(
                        "VOICE_CALL_LABEL",
                        comment: "Accessibility label for placing a voice call",
                    )
                    barButtons.append(audioCallButton)

                    let videoCallButton = UIBarButtonItem.button(icon: .buttonVideoCall) { [weak self] in
                        self?.startIndividualVideoCall()
                    }
                    videoCallButton.isEnabled = AppEnvironment.shared.callService.callServiceState.currentCall == nil
                    videoCallButton.accessibilityLabel = OWSLocalizedString(
                        "VIDEO_CALL_LABEL",
                        comment: "Accessibility label for placing a video call",
                    )
                    barButtons.append(videoCallButton)
                }
            }

            navigationItem.rightBarButtonItems = barButtons
            return
        }
    }

    public func updateReleaseNotesBarButtonItems() {
        let icon: UIImage = threadViewModel.isMuted ? Theme.iconImage(.buttonUnmute) : Theme.iconImage(.buttonMute)
        let muteButton = UIBarButtonItem(
            image: icon,
            menu: ConversationSettingsViewController.muteUnmuteMenu(
                for: threadViewModel,
                from: self,
                actionExecuted: {},
            ),
        )
        muteButton.accessibilityLabel = OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTE_LABEL",
            comment: "label for 'mute thread' cell in conversation settings",
        )
        navigationItem.rightBarButtonItem = muteButton
    }

    public func updateNavigationBarSubtitleLabel() {
        let subtitleText = NSMutableAttributedString()
        let subtitleFont = headerView.subtitleLabel.font!
        // To ensure a single source of text color do not set `color` attributes unless you really need to.
        let attributes: [NSAttributedString.Key: Any] = [.font: subtitleFont]
        let hairSpace = "\u{200a}"
        let thinSpace = "\u{2009}"
        let iconSpacer = UIDevice.current.isNarrowerThanIPhone6 ? hairSpace : thinSpace
        let betweenItemSpacer = UIDevice.current.isNarrowerThanIPhone6 ? " " : "  "

        let needsMutedBadge = threadViewModel.isMuted && !thread.isReleaseNotesThread
        let hasTimer = disappearingMessagesConfiguration.isEnabled
        let badgeType = conversationViewModel.badgeType

        if needsMutedBadge {
            subtitleText.appendTemplatedImage(named: "bell-slash-compact", font: subtitleFont)
            if badgeType == nil {
                subtitleText.append(iconSpacer, attributes: attributes)
                subtitleText.append(
                    OWSLocalizedString(
                        "MUTED_BADGE",
                        comment: "Badge indicating that the user is muted.",
                    ),
                    attributes: attributes,
                )
            }
        }

        if hasTimer {
            if needsMutedBadge {
                subtitleText.append(betweenItemSpacer, attributes: attributes)
            }

            subtitleText.appendTemplatedImage(named: Theme.iconName(.timer16), font: subtitleFont)
            subtitleText.append(iconSpacer, attributes: attributes)
            subtitleText.append(
                DateUtil.formatDuration(
                    seconds: disappearingMessagesConfiguration.durationSeconds,
                    useShortFormat: true,
                ),
                attributes: attributes,
            )
        }

        if let badgeType {
            switch badgeType {
            case .verified:
                if hasTimer || needsMutedBadge {
                    subtitleText.append(betweenItemSpacer, attributes: attributes)
                }

                subtitleText.append(SignalSymbol.safetyNumber.attributedString(staticFontSize: subtitleFont.pointSize))

                subtitleText.append(iconSpacer, attributes: attributes)
                subtitleText.append(
                    SafetyNumberStrings.verified,
                    attributes: attributes,
                )
            case .official:
                if needsMutedBadge {
                    subtitleText.append(betweenItemSpacer, attributes: attributes)
                }
                subtitleText.append(
                    OWSLocalizedString("RELEASE_NOTES_CHANNEL_OFFICIAL_LABEL", comment: "Label displayed in thread details of the release notes chat"),
                    attributes: attributes,
                )
            }
        }

        headerView.subtitleLabel.attributedText = subtitleText
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
        messageDraft: MessageBody?,
        draftReply: ThreadReplyInfo?,
        voiceMemoDraft: VoiceMessageInterruptedDraft?,
        editTarget: TSOutgoingMessage?,
    ) -> ConversationInputToolbar {
        AssertIsOnMainThread()
        owsAssertDebug(hasViewWillAppearEverBegun)

        let quotedReply: DraftQuotedReplyModel?
        if let draftReply {
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
            bodyRangesTextViewDelegate: self,
        )
        inputToolbar.accessibilityIdentifier = "inputToolbar"
        if let voiceMemoDraft {
            inputToolbar.showVoiceMemoDraft(voiceMemoDraft)
        }

        return inputToolbar
    }

    func buildDraftQuotedReply(_ draftReply: ThreadReplyInfo) -> DraftQuotedReplyModel? {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let interaction = try? InteractionFinder.fetchInteractions(
                timestamp: draftReply.timestamp,
                transaction: transaction,
            ).filter { candidate in
                if let incoming = candidate as? TSIncomingMessage {
                    return incoming.authorAddress.aci == draftReply.author
                }
                if candidate is TSOutgoingMessage {
                    return DependenciesBridge.shared.tsAccountManager
                        .localIdentifiers(tx: transaction)?.aci == draftReply.author
                }
                return false
            }.first as? TSMessage
            guard let interaction else {
                return nil
            }
            if interaction is OWSPaymentMessage {
                return DraftQuotedReplyModel.fromOriginalPaymentMessage(interaction, tx: transaction)
            }
            return DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReply(
                originalMessage: interaction,
                loadNormalizedImage: NormalizedImage.loadImage(imageSource:maxPixelSize:),
                tx: transaction,
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
        guard let inputToolbar else {
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
        guard let inputToolbar else {
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
        guard let inputToolbar else {
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
            return
        }

        self.showGifPicker()
    }
}
