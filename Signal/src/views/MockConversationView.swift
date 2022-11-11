//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

protocol MockConversationDelegate: AnyObject {
    var mockConversationViewWidth: CGFloat { get }
}

// MARK: -

class MockConversationView: UIView {

    weak var delegate: MockConversationDelegate?

    let hasWallpaper: Bool

    enum MockItem {
        case date
        case outgoing(text: String)
        case incoming(text: String)
    }
    struct MockModel {
        let items: [MockItem]
    }
    var model: MockModel {
        didSet {
            AssertIsOnMainThread()
            update()
        }
    }

    public var customChatColor: ChatColor? {
        didSet {
            update()
        }
    }

    init(model: MockModel, hasWallpaper: Bool, customChatColor: ChatColor?) {
        self.model = model
        self.hasWallpaper = hasWallpaper
        self.customChatColor = customChatColor

        super.init(frame: .zero)

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()

        update()
    }

    private func setup() {
        if !hasWallpaper { backgroundColor = Theme.backgroundColor }

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        update()
    }

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        return stackView
    }()

    private let thread = MockThread(contactAddress: SignalServiceAddress(phoneNumber: "+fake-id"))

    override var frame: CGRect {
        didSet {
            let didChangeWidth = frame.width != oldValue.width
            if didChangeWidth {
                update()
            }
        }
    }

    override var bounds: CGRect {
        didSet {
            let didChangeWidth = bounds.width != oldValue.width
            if didChangeWidth {
                update()
            }
        }
    }

    private func reset() {
        stackView.removeAllSubviews()
    }

    private func update() {

        reset()

        guard let delegate = self.delegate else {
            return
        }
        // We create our contents using the size of this view.
        // The wrinkle is that this view is often embedded within
        // a UITableView that will measure the contents of this
        // view (it's cell) before this view & its cell have been
        // displayed, when they still have zero width.  Therefore
        // we need to consult our delegate for the expected width.
        let viewWidth = delegate.mockConversationViewWidth
        guard viewWidth > 0 else {
            return
        }

        var renderItems = [CVRenderItem]()
        databaseStorage.read { transaction in
            let chatColor = self.customChatColor ?? ChatColors.chatColorForRendering(thread: thread,
                                                                                     transaction: transaction)
            let conversationStyle = ConversationStyle(
                type: .`default`,
                thread: self.thread,
                viewWidth: viewWidth,
                hasWallpaper: hasWallpaper,
                isWallpaperPhoto: false,
                chatColor: chatColor
            )
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)
            for item in model.items {
                let interaction: TSInteraction
                switch item {
                case .date:
                    interaction = DateHeaderInteraction(thread: self.thread, timestamp: NSDate.ows_millisecondTimeStamp())
                case .outgoing(let text):
                    interaction = MockOutgoingMessage(messageBody: text, thread: self.thread, transaction: transaction)
                case .incoming(let text):
                    interaction = MockIncomingMessage(messageBody: text, thread: self.thread)
                }

                guard let renderItem = CVLoader.buildStandaloneRenderItem(
                    interaction: interaction,
                    thread: self.thread,
                    threadAssociatedData: threadAssociatedData,
                    conversationStyle: conversationStyle,
                    transaction: transaction
                ) else {
                    owsFailDebug("Could not build renderItem.")
                    continue
                }
                renderItems.append(renderItem)
            }
        }

        var nextSpacerHeight: CGFloat = 0
        for (index, renderItem) in renderItems.enumerated() {
            if index > 0 {
                stackView.addArrangedSubview(.spacer(withHeight: nextSpacerHeight))
            }
            let cellView = CVCellView()
            cellView.configure(renderItem: renderItem, componentDelegate: self)
            cellView.isCellVisible = true
            cellView.autoSetDimension(.height, toSize: renderItem.cellMeasurement.cellSize.height)
            stackView.addArrangedSubview(cellView)

            switch renderItem.interaction {
            case is DateHeaderInteraction:
                nextSpacerHeight = 20
            default:
                nextSpacerHeight = 12
            }
        }
    }
}

// MARK: - Mock Classes

@objc
private class MockThread: TSContactThread {
    public override var shouldBeSaved: Bool {
        return false
    }

    override var uniqueId: String { "MockThread" }

    override func anyWillInsert(with transaction: SDSAnyWriteTransaction) {
        // no - op
        owsFailDebug("shouldn't save mock thread")
    }
}

// MARK: -

private class MockIncomingMessage: TSIncomingMessage {
    init(messageBody: String, thread: TSThread) {
        let builder = TSIncomingMessageBuilder(thread: thread,
                                               authorAddress: SignalServiceAddress(phoneNumber: "+fake-id"),
                                               sourceDeviceId: 1,
                                               messageBody: messageBody)
        super.init(incomingMessageWithBuilder: builder)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }

    public override var shouldBeSaved: Bool {
        return false
    }

    override func anyWillInsert(with transaction: SDSAnyWriteTransaction) {
        owsFailDebug("shouldn't save mock message")
    }
}

// MARK: -

private class MockOutgoingMessage: TSOutgoingMessage {
    init(messageBody: String, thread: TSThread, transaction: SDSAnyReadTransaction) {
        let builder = TSOutgoingMessageBuilder(thread: thread, messageBody: messageBody)
        super.init(outgoingMessageWithBuilder: builder, transaction: transaction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }

    public override var shouldBeSaved: Bool {
        return false
    }

    override func anyWillInsert(with transaction: SDSAnyWriteTransaction) {
        owsFailDebug("shouldn't save mock message")
    }

    class MockOutgoingMessageRecipientState: TSOutgoingMessageRecipientState {
        override var state: OWSOutgoingMessageRecipientState {
            return OWSOutgoingMessageRecipientState.sent
        }

        override var deliveryTimestamp: NSNumber? {
            return NSNumber(value: NSDate.ows_millisecondTimeStamp())
        }

        override var readTimestamp: NSNumber? {
            return NSNumber(value: NSDate.ows_millisecondTimeStamp())
        }
    }

    override var messageState: TSOutgoingMessageState { .sent }

    override func readRecipientAddresses() -> [SignalServiceAddress] {
        // makes message appear as read
        return [SignalServiceAddress(phoneNumber: "+123123123123123123")]
    }

    override func recipientState(for recipientAddress: SignalServiceAddress) -> TSOutgoingMessageRecipientState? {
        return MockOutgoingMessageRecipientState()
    }
}

// MARK: -

extension MockConversationView: CVComponentDelegate {

    func cvc_enqueueReload() {}

    func cvc_enqueueReloadWithoutCaches() {}

    func cvc_didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func cvc_didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    func cvc_didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

    func cvc_didLongPressTextViewItem(_ cell: CVCell,
                                      itemViewModel: CVItemViewModelImpl,
                                      shouldAllowReply: Bool) {}

    func cvc_didLongPressMediaViewItem(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl,
                                       shouldAllowReply: Bool) {}

    func cvc_didLongPressQuote(_ cell: CVCell,
                               itemViewModel: CVItemViewModelImpl,
                               shouldAllowReply: Bool) {}

    func cvc_didLongPressSystemMessage(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl) {}

    func cvc_didLongPressSticker(_ cell: CVCell,
                                 itemViewModel: CVItemViewModelImpl,
                                 shouldAllowReply: Bool) {}

    func cvc_didChangeLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_didEndLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_didCancelLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: -

    func cvc_didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_didTapSenderAvatar(_ interaction: TSInteraction) {}

    func cvc_shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { false }

    func cvc_didTapReactions(reactionState: InteractionReactionState,
                             message: TSMessage) {}

    func cvc_didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {}

    var cvc_hasPendingMessageRequest: Bool { false }

    func cvc_didTapFailedOrPendingDownloads(_ message: TSMessage) {}

    func cvc_didTapBrokenVideo() {}

    // MARK: - Messages

    func cvc_didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                             attachmentStream: TSAttachmentStream,
                             imageView: UIView) {}

    func cvc_didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction { .default }

    func cvc_didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel) {}

    func cvc_didTapLinkPreview(_ linkPreview: OWSLinkPreview) {}

    func cvc_didTapContactShare(_ contactShare: ContactShareViewModel) {}

    func cvc_didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {}

    func cvc_didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {}

    func cvc_didTapAddToContacts(contactShare: ContactShareViewModel) {}

    func cvc_didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {}

    func cvc_didTapGroupInviteLink(url: URL) {}

    func cvc_didTapProxyLink(url: URL) {}

    func cvc_didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    // Never wrap gifts on the mock conversation view
    func cvc_willWrapGift(_ messageUniqueId: String) -> Bool { false }

    func cvc_willShakeGift(_ messageUniqueId: String) -> Bool { false }

    func cvc_willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge, isExpired: Bool, isRedeemed: Bool) {}

    func cvc_prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        return {}
    }

    var view: UIView! { self }

    var isConversationPreview: Bool { true }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    // MARK: - Selection

    public var selectionState: CVSelectionState { CVSelectionState() }

    // MARK: - System Cell

    func cvc_didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {}

    func cvc_didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {}

    func cvc_didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage) {}

    func cvc_didTapCorruptedMessage(_ message: TSErrorMessage) {}

    func cvc_didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    func cvc_didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    func cvc_didTapShowFingerprint(_ address: SignalServiceAddress) {}

    func cvc_didTapIndividualCall(_ call: TSCall) {}

    func cvc_didTapGroupCall() {}

    func cvc_didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {}

    func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                          oldGroupModel: TSGroupModel,
                                                          newGroupModel: TSGroupModel) {}

    func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    func cvc_didTapViewGroupDescription(groupModel: TSGroupModel?) {}

    func cvc_didTapShowConversationSettings() {}

    func cvc_didTapShowConversationSettingsAndShowMemberRequests() {}

    func cvc_didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterUuid: UUID
    ) {}

    func cvc_didTapShowUpgradeAppUI() {}

    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents) {}

    func cvc_didTapPhoneNumberChange(uuid: UUID, phoneNumberOld: String, phoneNumberNew: String) {}

    func cvc_didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func cvc_didTapViewOnceExpired(_ interaction: TSInteraction) {}

    func cvc_didTapUnknownThreadWarningGroup() {}
    func cvc_didTapUnknownThreadWarningContact() {}
    func cvc_didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}
}
