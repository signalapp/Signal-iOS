//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class MockConversationView: UIView {

    let hasWallpaper: Bool

    var mode: Mode {
        didSet {
            AssertIsOnMainThread()
            update()
        }
    }

    // TODO: Right now, we don't respect the conversation
    // color when rendering message bubbles. If we
    // re-introduce colors we'll of course need to fix that,
    // but hopefully no changes are needed here.
    var conversationColor: ConversationColorName {
        set {
            AssertIsOnMainThread()
            thread.conversationColorName = newValue
            update()
        }
        get { thread.conversationColorName }
    }

    // TODO: This could definitely be smarter / support more variants.
    enum Mode {
        case outgoingIncoming(outgoingText: String, incomingText: String)
        case dateIncomingOutgoing(incomingText: String, outgoingText: String)
    }

    init(mode: Mode, hasWallpaper: Bool) {
        self.mode = mode
        self.hasWallpaper = hasWallpaper
        super.init(frame: .zero)

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    private var incomingText: String {
        switch mode {
        case .dateIncomingOutgoing(let incomingText, _):
            return incomingText
        case .outgoingIncoming(_, let incomingText):
            return incomingText
        }
    }

    private var outgoingText: String {
        switch mode {
        case .dateIncomingOutgoing(_, let outgoingText):
            return outgoingText
        case .outgoingIncoming(let outgoingText, _):
            return outgoingText
        }
    }

    private let thread = MockThread(contactAddress: SignalServiceAddress(phoneNumber: "+fake-id"))
    private lazy var conversationStyle = ConversationStyle(
        type: .`default`,
        thread: thread,
        viewWidth: 0,
        hasWallpaper: hasWallpaper
    )

    // This is mostly a developer convenience - OWSMessageCell asserts at some point
    // that the available method width is greater than 0.
    // We ultimately use the width of the picker view which will be larger.
    private let kMinimumConversationWidth: CGFloat = 300
    override var bounds: CGRect {
        didSet {
            let didChangeWidth = bounds.width != oldValue.width
            if didChangeWidth {
                update()
            }
        }
    }

    private func update() {
        let viewWidth = max(bounds.size.width, kMinimumConversationWidth)
        self.conversationStyle = ConversationStyle(
            type: .`default`,
            thread: self.thread,
            viewWidth: viewWidth,
            hasWallpaper: hasWallpaper
        )

        stackView.removeAllSubviews()

        var outgoingRenderItem: CVRenderItem?
        var incomingRenderItem: CVRenderItem?
        var dateHeaderRenderItem: CVRenderItem?

        databaseStorage.uiRead { transaction in
            let outgoingMessage = MockOutgoingMessage(messageBody: self.outgoingText, thread: self.thread)
            outgoingRenderItem = CVLoader.buildStandaloneRenderItem(
                interaction: outgoingMessage,
                thread: self.thread,
                conversationStyle: self.conversationStyle,
                transaction: transaction
            )

            let incomingMessage = MockIncomingMessage(messageBody: self.incomingText, thread: self.thread)
            incomingRenderItem = CVLoader.buildStandaloneRenderItem(
                interaction: incomingMessage,
                thread: self.thread,
                conversationStyle: self.conversationStyle,
                transaction: transaction
            )

            let dateHeader = DateHeaderInteraction(thread: self.thread, timestamp: NSDate.ows_millisecondTimeStamp())
            dateHeaderRenderItem = CVLoader.buildStandaloneRenderItem(
                interaction: dateHeader,
                thread: self.thread,
                conversationStyle: self.conversationStyle,
                transaction: transaction
            )
        }

        let outgoingMessageView = CVCellView()
        if let renderItem = outgoingRenderItem {
            outgoingMessageView.configure(renderItem: renderItem, componentDelegate: self)
            outgoingMessageView.isCellVisible = true
        } else {
            owsFailDebug("Missing outgoingRenderItem.")
        }

        let incomingMessageView = CVCellView()
        if let renderItem = incomingRenderItem {
            incomingMessageView.configure(renderItem: renderItem, componentDelegate: self)
            incomingMessageView.isCellVisible = true
        } else {
            owsFailDebug("Missing incomingRenderItem.")
        }

        let dateHeaderView = CVCellView()
        if let renderItem = dateHeaderRenderItem {
            dateHeaderView.configure(renderItem: renderItem, componentDelegate: self)
            dateHeaderView.isCellVisible = true
        } else {
            owsFailDebug("Missing incomingRenderItem.")
        }

        switch mode {
        case .outgoingIncoming:
            stackView.addArrangedSubview(outgoingMessageView)
            stackView.addArrangedSubview(.spacer(withHeight: 12))
            stackView.addArrangedSubview(incomingMessageView)
        case .dateIncomingOutgoing:
            stackView.addArrangedSubview(dateHeaderView)
            stackView.addArrangedSubview(.spacer(withHeight: 20))
            stackView.addArrangedSubview(incomingMessageView)
            stackView.addArrangedSubview(.spacer(withHeight: 12))
            stackView.addArrangedSubview(outgoingMessageView)
        }
    }
}

// MARK: - Mock Classes

@objc
private class MockThread: TSContactThread {
    public override var shouldBeSaved: Bool {
        return false
    }

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
    init(messageBody: String, thread: TSThread) {
        let builder = TSOutgoingMessageBuilder(thread: thread, messageBody: messageBody)
        super.init(outgoingMessageWithBuilder: builder)
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

    func cvc_didTapMention(_ mention: Mention) {}

    func cvc_didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    var view: UIView { self }

    // MARK: - Selection

    var isShowingSelectionUI: Bool { false }

    func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool { false }

    func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

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

    func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                          oldGroupModel: TSGroupModel,
                                                          newGroupModel: TSGroupModel) {}

    func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    func cvc_didTapShowConversationSettings() {}

    func cvc_didTapShowConversationSettingsAndShowMemberRequests() {}

    func cvc_didTapShowUpgradeAppUI() {}

    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents) {}

    func cvc_didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func cvc_didTapViewOnceExpired(_ interaction: TSInteraction) {}
}
