//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

@objc
protocol PinnedMessageInteractionManagerDelegate: AnyObject {
    func goToMessage(message: TSMessage)
    func unpinMessage(message: TSMessage)
}

class PinnedMessagesDetailsViewController: OWSViewController, DatabaseChangeDelegate, PinnedMessageLongPressDelegate.ActionDelegate {
    private var pinnedMessages: [TSMessage]
    private let threadViewModel: ThreadViewModel
    private let db: DB
    private var messageLongPressDelegates: [PinnedMessageLongPressDelegate] = []
    private var pinnedMessageManager: PinnedMessageManager

    private weak var delegate: PinnedMessageInteractionManagerDelegate?

    init(
        pinnedMessages: [TSMessage],
        threadViewModel: ThreadViewModel,
        database: DB,
        delegate: PinnedMessageInteractionManagerDelegate,
        databaseChangeObserver: DatabaseChangeObserver,
        pinnedMessageManager: PinnedMessageManager
    ) {
        self.pinnedMessages = pinnedMessages
        self.threadViewModel = threadViewModel
        self.db = database
        self.delegate = delegate
        self.pinnedMessageManager = pinnedMessageManager

        super.init()

        view.backgroundColor = .Signal.groupedBackground

        databaseChangeObserver.appendDatabaseChangeDelegate(self)

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "PINNED_MESSAGES_DETAILS_TITLE",
            comment: "Title for Pinned Messages detail view"
        )
        titleLabel.font = .dynamicTypeHeadlineClamped.semibold()
        titleLabel.textColor = UIColor.Signal.label
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = threadViewModel.name
        subtitleLabel.font = .dynamicTypeSubheadlineClamped
        subtitleLabel.textColor = UIColor.Signal.secondaryLabel
        subtitleLabel.textAlignment = .center

        let titleStackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStackView.axis = .vertical
        titleStackView.alignment = .center
        titleStackView.spacing = 4

        navigationItem.titleView = titleStackView
    }

    private func layoutPinnedMessages(tx: DBReadTransaction) {
        messageLongPressDelegates = []
        view.subviews.forEach { $0.removeFromSuperview() }

        let scrollView = UIScrollView()
        let paddedContainerView = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12

        var currentDaysBefore = -1
        for (index, message) in pinnedMessages.reversed().enumerated() {
            guard let renderItem = buildRenderItem(thread: threadViewModel.threadRecord, threadAssociatedData: threadViewModel.associatedData, message: message, tx: tx)
            else {
                continue
            }

            let longPressDelegate = PinnedMessageLongPressDelegate(itemViewModel: CVItemViewModelImpl(renderItem: renderItem))
            longPressDelegate.actionDelegate = self
            messageLongPressDelegates.append(longPressDelegate)

            let itemDate = Date(millisecondsSince1970: message.timestamp)
            let daysPrior = DateUtil.daysFrom(firstDate: itemDate, toSecondDate: Date())

            if daysPrior != currentDaysBefore {
                currentDaysBefore = daysPrior
                let dateInteraction = DateHeaderInteraction(thread: threadViewModel.threadRecord, timestamp: message.timestamp)
                if let dateItem = buildDateRenderItem(dateInteraction: dateInteraction, tx: tx)
                {
                    let cellView = CVCellView()
                    cellView.configure(renderItem: dateItem, componentDelegate: self)
                    cellView.isCellVisible = true
                    cellView.autoSetDimension(.height, toSize: dateItem.cellSize.height)

                    stack.addArrangedSubview(cellView)
                }
            }
            stack.addArrangedSubview(
                buildButtonAndCellStack(
                    renderItem: renderItem,
                    message: message,
                    reversedIndex: index
                )
            )
        }

        paddedContainerView.addSubview(stack)
        scrollView.addSubview(paddedContainerView)
        view.addSubview(scrollView)

        scrollView.autoPinEdgesToSuperviewEdges()
        paddedContainerView.autoPinEdgesToSuperviewEdges()
        stack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        paddedContainerView.autoMatch(.width, to: .width, of: scrollView)

    }

    private func updatePinnedMessageState() {
        guard let threadId = threadViewModel.threadRecord.sqliteRowId else {
            return
        }
        db.read { tx in
            pinnedMessages = pinnedMessageManager.fetchPinnedMessagesForThread(threadId: threadId, tx: tx)
            layoutPinnedMessages(tx: tx)
        }
        view.layoutIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        db.read { tx in
            layoutPinnedMessages(tx: tx)
        }
    }

    private func buildButtonAndCellStack(renderItem: CVRenderItem, message: TSMessage, reversedIndex: Int) -> UIStackView {
        let cellHStack = UIStackView()
        cellHStack.axis = .horizontal
        cellHStack.alignment = .trailing
        cellHStack.distribution = .fill

        let goToMessageButton = UIButton()
        goToMessageButton.setImage(.arrowRightCircle, for: .normal)
        goToMessageButton.tintColor = UIColor.Signal.secondaryLabel
        goToMessageButton.backgroundColor = UIColor.Signal.tertiaryFill
        goToMessageButton.translatesAutoresizingMaskIntoConstraints = false
        goToMessageButton.layer.cornerRadius = 18
        goToMessageButton.clipsToBounds = true

        goToMessageButton.tag = reversedIndex
        goToMessageButton.addTarget(self, action: #selector(goToMessage), for: .touchUpInside)

        let cellView = CVCellView()
        cellView.configure(renderItem: renderItem, componentDelegate: self)
        cellView.isCellVisible = true
        cellView.autoSetDimension(.height, toSize: renderItem.cellSize.height)
        cellView.autoSetDimension(.width, toSize: renderItem.cellSize.width)

        let uiContextMenuInteraction = UIContextMenuInteraction(delegate: messageLongPressDelegates[reversedIndex])
        cellView.addInteraction(uiContextMenuInteraction)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if message.isOutgoing {
            cellHStack.addArrangedSubview(spacer)
            cellHStack.addArrangedSubview(goToMessageButton)
            cellHStack.addArrangedSubview(cellView)
        } else {
            cellHStack.addArrangedSubview(cellView)
            cellHStack.addArrangedSubview(goToMessageButton)
            cellHStack.addArrangedSubview(spacer)
        }
        NSLayoutConstraint.activate([
            goToMessageButton.heightAnchor.constraint(equalToConstant: 36),
            goToMessageButton.widthAnchor.constraint(equalToConstant: 36),
        ])

        return cellHStack
    }

    private func buildDateRenderItem(dateInteraction: DateHeaderInteraction, tx: DBReadTransaction) -> CVRenderItem? {
        let conversationStyle = ConversationStyle(
            type: .messageDetails,
            thread: threadViewModel.threadRecord,
            viewWidth: view.frame.size.width,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: DependenciesBridge.shared.chatColorSettingStore.resolvedChatColor(
                for: threadViewModel.threadRecord,
                tx: tx
            )
        )

        return CVLoader.buildStandaloneRenderItem(
            interaction: dateInteraction,
            thread: threadViewModel.threadRecord,
            threadAssociatedData: threadViewModel.associatedData,
            conversationStyle: conversationStyle,
            spoilerState: self.spoilerState,
            transaction: tx
        )
    }

    private func buildRenderItem(
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
        message: TSMessage,
        forceDateHeader: Bool = false,
        tx: DBReadTransaction
    ) -> CVRenderItem? {
        let conversationStyle = ConversationStyle(
            type: .messageDetails,
            thread: thread,
            viewWidth: view.frame.size.width,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: DependenciesBridge.shared.chatColorSettingStore.resolvedChatColor(
                for: thread,
                tx: tx
            )
        )

        // TODO: correct spoilerState
        return CVLoader.buildStandaloneRenderItem(
            interaction: message,
            thread: thread,
            threadAssociatedData: threadAssociatedData,
            conversationStyle: conversationStyle,
            spoilerState: SpoilerRenderState(),
            transaction: tx
        )
    }

    // MARK: - Interactions

    @objc
    private func goToMessage(sender: UIButton) {
        // We index in reverse order because of how UIKit lays out the pinned messages (top to bottom)
        // versus how we store them for displaying in the CVC banner view (most -> least recent)
        let reversedArray = pinnedMessages.reversed().map { $0 }
        guard reversedArray.indices.contains(sender.tag) else {
            return
        }
        let message = reversedArray[sender.tag]
        delegate?.goToMessage(message: message)
        dismiss(animated: true)
    }

    // MARK: - DatabaseChangeDelegate

    func databaseChangesDidUpdate(databaseChanges: any SignalServiceKit.DatabaseChanges) {
        let pinnedMessagesSet = Set(pinnedMessages.map(\.uniqueId))
        guard Set(databaseChanges.interactionUniqueIds).isDisjoint(with: pinnedMessagesSet) == false else {
            return
        }
        updatePinnedMessageState()
    }

    func databaseChangesDidUpdateExternally() {
        updatePinnedMessageState()
    }

    func databaseChangesDidReset() {
        updatePinnedMessageState()
    }

    // MARK: - PinnedMessageLongPressActionDelegate

    func deleteMessage(itemViewModel: CVItemViewModelImpl) {
        itemViewModel.interaction.presentDeletionActionSheet(from: self)
    }

    func unpinMessage(itemViewModel: CVItemViewModelImpl) {
        dismiss(animated: true)
        guard let message = itemViewModel.interaction as? TSMessage else { return }
        delegate?.unpinMessage(message: message)
    }
}

// MARK: - UIContextMenuInteractionDelegate

private class PinnedMessageLongPressDelegate: NSObject, UIContextMenuInteractionDelegate {
    fileprivate protocol ActionDelegate: AnyObject {
        func deleteMessage(itemViewModel: CVItemViewModelImpl)
        func unpinMessage(itemViewModel: CVItemViewModelImpl)
    }

    let itemViewModel: CVItemViewModelImpl

    weak var actionDelegate: ActionDelegate?

    init(itemViewModel: CVItemViewModelImpl) {
        self.itemViewModel = itemViewModel
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {

        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil,
            actionProvider: { [weak self] _ in
                guard let self = self else { return UIMenu(children: []) }
                var actions: [UIAction] = []
                if itemViewModel.canCopyOrShareOrSpeakText {
                    actions.append(
                        UIAction(
                            title: OWSLocalizedString(
                                "CONTEXT_MENU_COPY",
                                comment: "Context menu button title"
                            ),
                            image: .copyLight
                        ) { [weak self] _ in
                            self?.itemViewModel.copyTextAction()
                    })
                }

                if itemViewModel.canSaveMedia {
                    actions.append(
                        UIAction(
                            title: OWSLocalizedString(
                                "CONTEXT_MENU_SAVE_MEDIA",
                                comment: "Context menu button title"
                            ),
                            image: .saveLight
                        ) { [weak self] _ in
                            self?.itemViewModel.saveMediaAction()
                    })
                }

                actions.append(contentsOf: [
                    UIAction(
                        title: OWSLocalizedString(
                            "PINNED_MESSAGES_UNPIN",
                            comment: "Action menu item to unpin a message"
                        ),
                        image: .pinSlash
                    ) { [weak self] _ in
                        guard let self = self else { return }
                        actionDelegate?.unpinMessage(itemViewModel: itemViewModel)
                    },
                    UIAction(
                        title: OWSLocalizedString(
                            "CONTEXT_MENU_DELETE_MESSAGE",
                            comment: "Context menu button title"
                        ),
                        image: .trashLight
                    ) { [weak self] _ in
                            guard let self = self else { return }
                            actionDelegate?.deleteMessage(itemViewModel: itemViewModel)
                    }]
                )

                return UIMenu(children: actions)
            }
        )
    }
}

// MARK: - CVComponentDelegate

extension PinnedMessagesDetailsViewController: CVComponentDelegate {
    var spoilerState: SignalUI.SpoilerRenderState {
        return SpoilerRenderState()
    }

    func enqueueReload() {}

    func enqueueReloadWithoutCaches() {}

    func didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    func didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

    func didDoubleTapTextViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didLongPressTextViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressMediaViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressQuote(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressSystemMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl) {}

    func didLongPressSticker(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressPaymentMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool
    ) {}

    func didLongPressPoll(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool
    ) {}

    func didTapPayment(_ payment: PaymentsHistoryItem) {}

    func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didEndLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: -

    func willBecomeVisibleWithFailedOrPendingDownloads(_ message: TSMessage) {}

    func didTapFailedOrPendingDownloads(_ message: TSMessage) {}

    func didCancelDownload(_ message: TSMessage, attachmentId: Attachment.IDType) {}

    // MARK: -

    func didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapSenderAvatar(_ interaction: TSInteraction) {}

    func shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { false }

    func didTapReactions(
        reactionState: InteractionReactionState,
        message: TSMessage) {}

    func didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapShowEditHistory(_ itemViewModel: CVItemViewModelImpl) {}

    var hasPendingMessageRequest: Bool { false }

    func didTapUndownloadableMedia() {}

    func didTapUndownloadableGenericFile() {}

    func didTapUndownloadableOversizeText() {}

    func didTapUndownloadableAudio() {}

    func didTapUndownloadableSticker() {}

    func didTapBrokenVideo() {}

    func didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachmentStream: ReferencedAttachmentStream,
        imageView: UIView
    ) {}

    func didTapGenericAttachment(
        _ attachment: CVComponentGenericAttachment
    ) -> CVAttachmentTapAction { .default }

    func didTapQuotedReply(_ quotedReply: QuotedReplyModel) {}

    func didTapLinkPreview(_ linkPreview: OWSLinkPreview) {}

    func didTapContactShare(_ contactShare: ContactShareViewModel) {}

    func didTapSendMessage(to phoneNumbers: [String]) {}

    func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {}

    func didTapAddToContacts(contactShare: ContactShareViewModel) {}

    func didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {}

    func didTapGroupInviteLink(url: URL) {}

    func didTapProxyLink(url: URL) {}

    func didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    func willWrapGift(_ messageUniqueId: String) -> Bool { false }

    func willShakeGift(_ messageUniqueId: String) -> Bool { false }

    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapGiftBadge(
        _ itemViewModel: CVItemViewModelImpl,
        profileBadge: ProfileBadge,
        isExpired: Bool,
        isRedeemed: Bool) {}

    func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        return {}
    }

    var isConversationPreview: Bool { true }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    public var selectionState: CVSelectionState { CVSelectionState() }

    func didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapCorruptedMessage(_ message: TSErrorMessage) {}

    func didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    func didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    func didTapShowFingerprint(_ address: SignalServiceAddress) {}

    func didTapIndividualCall(_ call: TSCall) {}

    func didTapLearnMoreMissedCallFromBlockedContact(_ call: TSCall) {}

    func didTapGroupCall() {}

    func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapGroupMigrationLearnMore() {}

    func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    func didTapViewGroupDescription(newGroupDescription: String) {}

    func didTapNameEducation(type: SafetyTipsType) {}

    func didTapShowConversationSettings() {}

    func didTapShowConversationSettingsAndShowMemberRequests() {}

    func didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterAci: Aci) {}

    func didTapShowUpgradeAppUI() {}

    func didTapUpdateSystemContact(
        _ address: SignalServiceAddress,
        newNameComponents: PersonNameComponents) {}

    func didTapPhoneNumberChange(aci: Aci, phoneNumberOld: String, phoneNumberNew: String) {}

    func didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func didTapViewOnceExpired(_ interaction: TSInteraction) {}

    func didTapContactName(thread: TSContactThread) {}

    func didTapUnknownThreadWarningGroup() {}
    func didTapUnknownThreadWarningContact() {}
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}

    func didTapActivatePayments() {}
    func didTapSendPayment() {}

    func didTapThreadMergeLearnMore(phoneNumber: String) {}

    func didTapReportSpamLearnMore() {}

    func didTapMessageRequestAcceptedOptions() {}

    func didTapJoinCallLinkCall(callLink: CallLink) {}

    func didTapViewVotes(poll: OWSPoll) {}

    func didTapViewPoll(pollInteractionUniqueId: String) {}

    func didTapVoteOnPoll(poll: OWSPoll, optionIndex: UInt32, isUnvote: Bool) {}

    func didTapViewPinnedMessage(pinnedMessageUniqueId: String) {}
}
