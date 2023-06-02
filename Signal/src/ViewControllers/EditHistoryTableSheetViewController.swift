//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class EditHistoryTableSheetViewController: OWSTableSheetViewController {

    internal enum Constants {
        static let cellSpacing: CGFloat = 12.0
    }

    var parentRenderItem: CVRenderItem?
    var renderItems = [CVRenderItem]()
    let spoilerReveal: SpoilerRevealState

    init(
        message: TSMessage,
        spoilerReveal: SpoilerRevealState,
        database: SDSDatabaseStorage
    ) {
        self.spoilerReveal = spoilerReveal

        super.init()

        do {
            try loadEditHistory(message: message, database: database)
            updateTableContents(shouldReload: true)
        } catch {
            owsFailDebug("Error reading edit history: \(error)")
        }
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    // MARK: - Table Update

    private func loadEditHistory(message: TSMessage, database: SDSDatabaseStorage) throws {
        try database.read { tx in
            let edits = try EditMessageFinder.findEditHistory(
                for: message,
                transaction: tx
            ).compactMap { $1 }

            guard let thread = TSThread.anyFetch(
                uniqueId: message.uniqueThreadId,
                transaction: tx
            ) else {
                owsFailDebug("Missing thread.")
                return
            }

            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(
                for: thread,
                transaction: tx
            )

            parentRenderItem = buildRenderItem(
                thread: thread,
                threadAssociatedData: threadAssociatedData,
                message: message,
                tx: tx)

            var renderItems = [CVRenderItem]()
            for edit in edits {
                if let item = buildRenderItem(
                    thread: thread,
                    threadAssociatedData: threadAssociatedData,
                    message: edit,
                    tx: tx
                ) {
                    renderItems.append(item)
                }
            }
            self.renderItems = renderItems
        }
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }
        guard let parentItem = parentRenderItem else { return }

        let topSection = OWSTableSection()
        topSection.add(createMessageListTableItem(items: [parentItem]))
        contents.addSection(topSection)

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
        contents.addSection(section)
    }

    // MARK: - Utility Methods

    private func createMessageListTableItem(items: [CVRenderItem]) -> OWSTableItem {
        return OWSTableItem { [weak self] in
            guard let self = self else { return UITableViewCell() }

            let views = items.map { item in
                let cellView = CVCellView()
                cellView.configure(renderItem: item, componentDelegate: self)
                cellView.isCellVisible = true
                cellView.autoSetDimension(.height, toSize: item.cellSize.height)
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

    private func buildRenderItem(
        thread: TSThread,
        threadAssociatedData: ThreadAssociatedData,
        message interaction: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> CVRenderItem? {

        let chatColor = ChatColors.chatColorForRendering(
            thread: thread,
            transaction: tx
        )

        let cellInsets = tableViewController.cellOuterInsets
        let viewWidth = tableViewController.view.frame.inset(by: cellInsets).width
        let conversationStyle = ConversationStyle(
            type: .messageDetails,
            thread: thread,
            viewWidth: viewWidth,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: chatColor
        )

        return CVLoader.buildStandaloneRenderItem(
            interaction: interaction,
            thread: thread,
            threadAssociatedData: threadAssociatedData,
            conversationStyle: conversationStyle,
            spoilerReveal: self.spoilerReveal,
            transaction: tx
        )
    }
}

// MARK: - CVComponentDelegate

extension EditHistoryTableSheetViewController: CVComponentDelegate {

    func enqueueReload() {}

    func enqueueReloadWithoutCaches() {}

    func didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    func didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

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

    func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didEndLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl) {}

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

    func didTapFailedOrPendingDownloads(_ message: TSMessage) {}

    func didTapBrokenVideo() {}

    func didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachmentStream: TSAttachmentStream,
        imageView: UIView) {}

    func didTapGenericAttachment(
        _ attachment: CVComponentGenericAttachment
    ) -> CVAttachmentTapAction { .default }

    func didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel) {}

    func didTapLinkPreview(_ linkPreview: OWSLinkPreview) {}

    func didTapContactShare(_ contactShare: ContactShareViewModel) {}

    func didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {}

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

    func didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage) {}

    func didTapCorruptedMessage(_ message: TSErrorMessage) {}

    func didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    func didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    func didTapShowFingerprint(_ address: SignalServiceAddress) {}

    func didTapIndividualCall(_ call: TSCall) {}

    func didTapGroupCall() {}

    func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapGroupMigrationLearnMore() {}

    func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    func didTapViewGroupDescription(groupModel: TSGroupModel?) {}

    func didTapShowConversationSettings() {}

    func didTapShowConversationSettingsAndShowMemberRequests() {}

    func didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterUuid: UUID) {}

    func didTapShowUpgradeAppUI() {}

    func didTapUpdateSystemContact(
        _ address: SignalServiceAddress,
        newNameComponents: PersonNameComponents) {}

    func didTapPhoneNumberChange(
        uuid: UUID,
        phoneNumberOld: String,
        phoneNumberNew: String) {}

    func didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func didTapViewOnceExpired(_ interaction: TSInteraction) {}

    func didTapUnknownThreadWarningGroup() {}
    func didTapUnknownThreadWarningContact() {}
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}
}
