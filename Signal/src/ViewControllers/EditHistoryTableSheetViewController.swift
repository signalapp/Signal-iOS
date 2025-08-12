//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

protocol MessageEditHistoryViewDelegate: AnyObject {
    func editHistoryMessageWasDeleted()
}

class EditHistoryTableSheetViewController: OWSTableSheetViewController {

    internal enum Constants {
        static let cellSpacing: CGFloat = 12.0
    }

    weak var delegate: MessageEditHistoryViewDelegate?

    var parentRenderItems: [CVRenderItem]?
    var renderItems = [CVRenderItem]()
    let threadViewModel: ThreadViewModel
    let spoilerState: SpoilerRenderState
    private var message: TSMessage
    private let database: SDSDatabaseStorage
    private let editManager: EditManager

    init(
        message: TSMessage,
        threadViewModel: ThreadViewModel,
        spoilerState: SpoilerRenderState,
        editManager: EditManager,
        database: SDSDatabaseStorage,
        databaseChangeObserver: DatabaseChangeObserver
    ) {
        self.threadViewModel = threadViewModel
        self.spoilerState = spoilerState
        self.message = message
        self.database = database
        self.editManager = editManager
        super.init()

        databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            try self.database.write { tx in

                guard let thread = TSThread.anyFetch(
                    uniqueId: message.uniqueThreadId,
                    transaction: tx
                ) else { return }

                try self.editManager.markEditRevisionsAsRead(
                    for: self.message,
                    thread: thread,
                    tx: tx
                )
            }
        } catch {
            owsFailDebug("Failed to update edit read state")
        }
    }

    // MARK: - Table Update

    private func loadEditHistory() throws {
        let messageStillExists = try database.read { tx in
            guard let newMessage = TSInteraction.anyFetch(uniqueId: message.uniqueId, transaction: tx) as? TSMessage else {
                return false
            }
            message = newMessage

            let edits: [TSMessage] = try DependenciesBridge.shared.editMessageStore.findEditHistory(
                forMostRecentRevision: message,
                tx: tx
            ).compactMap { $0.message }

            guard let thread = TSThread.anyFetch(
                uniqueId: message.uniqueThreadId,
                transaction: tx
            ) else {
                owsFailDebug("Missing thread.")
                return false
            }

            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(
                for: thread,
                transaction: tx
            )

            parentRenderItems = buildRenderItem(
                thread: thread,
                threadAssociatedData: threadAssociatedData,
                message: message,
                forceDateHeader: true,
                tx: tx)

            var renderItems = [CVRenderItem]()
            for edit in edits {
                let items = buildRenderItem(
                    thread: thread,
                    threadAssociatedData: threadAssociatedData,
                    message: edit,
                    tx: tx
                )
                renderItems.append(contentsOf: items)
            }
            self.renderItems = renderItems

            return true
        }

        if !messageStillExists {
            delegate?.editHistoryMessageWasDeleted()
        }
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        do {
            try loadEditHistory()
        } catch {
            owsFailDebug("Error reading edit history: \(error)")
        }

        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }
        guard let parentItems = parentRenderItems else { return }

        let topSection = OWSTableSection()
        topSection.add(createMessageListTableItem(items: parentItems))
        contents.add(topSection)

        let header = OWSLocalizedString(
            "EDIT_HISTORY_LABEL",
            comment: "Label for Edit History modal"
        )

        let section = OWSTableSection()
        section.headerAttributedTitle = NSAttributedString(string: header, attributes: [
            .font: UIFont.dynamicTypeBodyClamped.semibold(),
            .foregroundColor: Theme.primaryTextColor
        ])
        section.hasBackground = true
        section.hasSeparators = false
        section.add(createMessageListTableItem(items: renderItems))
        contents.add(section)
    }

    // MARK: - Utility Methods

    private func createMessageListTableItem(items: [CVRenderItem]) -> OWSTableItem {
        return OWSTableItem { [weak self] in
            guard let self = self else { return UITableViewCell() }

            let views = items.enumerated().map { (index, item) in
                let cellView = CVCellView()
                cellView.configure(renderItem: item, componentDelegate: self)
                cellView.isCellVisible = true
                cellView.autoSetDimension(.height, toSize: item.cellSize.height)

                // Its not 100% ideal to use an alternate mechanism to handle taps, but
                // hooking up full cell tap handling is a larger effort and for now
                // we just want to handle long text taps on this view.
                cellView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.didTapCell)))
                cellView.tag = index

                return cellView
            }

            let stack = UIStackView(arrangedSubviews: views)
            stack.spacing = Constants.cellSpacing
            stack.axis = .vertical
            stack.alignment = .fill

            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(stack)
            stack.autoPinEdgesToSuperviewMargins()

            return cell
        }
    }

    @objc
    func didTapCell(_ recognizer: UITapGestureRecognizer) {
        guard
            let view = recognizer.view as? CVCellView,
            let item = view.renderItem,
            item.itemModel.componentState.displayableBodyText?.isTextTruncated == true
        else {
            return
        }
        let itemViewModel = CVItemViewModelImpl(renderItem: item)
        let longTextVC = LongTextViewController(
            itemViewModel: itemViewModel,
            threadViewModel: threadViewModel,
            spoilerState: spoilerState
        )
        longTextVC.delegate = self
        let navVc = OWSNavigationController(rootViewController: longTextVC)
        self.present(navVc, animated: true)
    }

    var currentDaysBefore: Int = -1
    private func buildRenderItem(
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
        message interaction: TSMessage,
        forceDateHeader: Bool = false,
        tx: DBReadTransaction
    ) -> [CVRenderItem] {
        var results = [CVRenderItem]()
        let cellInsets = tableViewController.cellOuterInsets
        let viewWidth = tableViewController.view.frame.inset(by: cellInsets).width
        let conversationStyle = ConversationStyle(
            type: .messageDetails,
            thread: thread,
            viewWidth: viewWidth,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: DependenciesBridge.shared.chatColorSettingStore.resolvedChatColor(
                for: thread,
                tx: tx
            )
        )

        let itemDate = Date(millisecondsSince1970: interaction.timestamp)
        let daysPrior = DateUtil.daysFrom(firstDate: itemDate, toSecondDate: Date())
        if forceDateHeader || daysPrior > currentDaysBefore {
            currentDaysBefore = daysPrior

            let dateInteraction = DateHeaderInteraction(thread: thread, timestamp: interaction.timestamp)
            if let dateItem = CVLoader.buildStandaloneRenderItem(
                interaction: dateInteraction,
                thread: thread,
                threadAssociatedData: threadAssociatedData,
                conversationStyle: conversationStyle,
                spoilerState: self.spoilerState,
                transaction: tx
            ) {
                results.append(dateItem)
            }
        }

        if let item =  CVLoader.buildStandaloneRenderItem(
            interaction: interaction,
            thread: thread,
            threadAssociatedData: threadAssociatedData,
            conversationStyle: conversationStyle,
            spoilerState: self.spoilerState,
            transaction: tx
        ) {
            results.append(item)
        }
        return results
    }
}

// MARK: - DatabaseChangeDelegate

extension EditHistoryTableSheetViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: SignalServiceKit.DatabaseChanges) {
        guard databaseChanges.didUpdate(interaction: self.message) else {
            return
        }

        updateTableContents()
    }

    func databaseChangesDidUpdateExternally() {
        updateTableContents()
    }

    func databaseChangesDidReset() {
        updateTableContents()
    }
}

// MARK: - CVComponentDelegate

extension EditHistoryTableSheetViewController: CVComponentDelegate {

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
}

extension EditHistoryTableSheetViewController: LongTextViewDelegate {
    func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController) {
        self.dismiss(animated: true)
    }
}
