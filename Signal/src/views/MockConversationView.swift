//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

protocol MockConversationDelegate: AnyObject {
    var mockConversationViewWidth: CGFloat { get }
}

// MARK: -

final class MockConversationView: UIView {

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

    public var customChatColor: ColorOrGradientSetting? {
        didSet {
            update()
        }
    }

    init(model: MockModel, hasWallpaper: Bool, customChatColor: ColorOrGradientSetting?) {
        self.model = model
        self.hasWallpaper = hasWallpaper
        self.customChatColor = customChatColor

        super.init(frame: .zero)

        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    // Use a v5 UUID that's in a separate namespace from ACIs/PNIs.
    fileprivate static let mockAddress = SignalServiceAddress(try! ServiceId.parseFrom(serviceIdString: "00000000-0000-5000-8000-000000000000"))

    private let thread = MockThread(contactAddress: MockConversationView.mockAddress)

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

        let modelItems: [(MockItem, ValidatedInlineMessageBody?)] = SSKEnvironment.shared.databaseStorageRef.write { tx in
            return model.items.map { item in
                switch item {
                case .date:
                    return (item, nil)
                case .incoming(let text), .outgoing(let text):
                    return (item, DependenciesBridge.shared.attachmentContentValidator.truncatedMessageBodyForInlining(
                        MessageBody(text: text, ranges: .empty),
                        tx: tx
                    ))
                }
            }
        }

        var renderItems = [CVRenderItem]()
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let chatColor = self.customChatColor ?? DependenciesBridge.shared.chatColorSettingStore.resolvedChatColor(
                for: thread,
                tx: transaction
            )
            let conversationStyle = ConversationStyle(
                type: .`default`,
                thread: self.thread,
                viewWidth: viewWidth,
                hasWallpaper: hasWallpaper,
                isWallpaperPhoto: false,
                chatColor: chatColor
            )
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)
            for (item, text) in modelItems {
                let interaction: TSInteraction
                switch item {
                case .date:
                    interaction = DateHeaderInteraction(thread: self.thread, timestamp: NSDate.ows_millisecondTimeStamp())
                case .outgoing:
                    interaction = MockOutgoingMessage(messageBody: text!, thread: self.thread, transaction: transaction)
                case .incoming:
                    interaction = MockIncomingMessage(messageBody: text!, thread: self.thread)
                }

                guard let renderItem = CVLoader.buildStandaloneRenderItem(
                    interaction: interaction,
                    thread: self.thread,
                    threadAssociatedData: threadAssociatedData,
                    conversationStyle: conversationStyle,
                    spoilerState: SpoilerRenderState(),
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

final private class MockThread: TSContactThread {
    public override var shouldBeSaved: Bool {
        return false
    }

    override var uniqueId: String { "MockThread" }

    override func anyWillInsert(with transaction: DBWriteTransaction) {
        // no - op
        owsFailDebug("shouldn't save mock thread")
    }
}

// MARK: -

final private class MockIncomingMessage: TSIncomingMessage {
    init(messageBody: ValidatedInlineMessageBody, thread: MockThread) {
        let builder: TSIncomingMessageBuilder = .withDefaultValues(
            thread: thread,
            authorAci: thread.contactAddress.aci!,
            messageBody: messageBody
        )
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

    override func anyWillInsert(with transaction: DBWriteTransaction) {
        owsFailDebug("shouldn't save mock message")
    }
}

// MARK: -

final private class MockOutgoingMessage: TSOutgoingMessage {
    init(messageBody: ValidatedInlineMessageBody, thread: TSThread, transaction: DBReadTransaction) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(thread: thread, messageBody: messageBody)
        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: transaction
        )
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

    override func anyWillInsert(with transaction: DBWriteTransaction) {
        owsFailDebug("shouldn't save mock message")
    }

    override var messageState: TSOutgoingMessageState { .sent }

    override func readRecipientAddresses() -> [SignalServiceAddress] {
        // makes message appear as read
        return [MockConversationView.mockAddress]
    }

    override func recipientState(for recipientAddress: SignalServiceAddress) -> TSOutgoingMessageRecipientState? {
        return TSOutgoingMessageRecipientState(
            status: .read,
            statusTimestamp: Date().ows_millisecondsSince1970,
            wasSentByUD: true,
            errorCode: nil
        )
    }
}

// MARK: -

extension MockConversationView: CVComponentDelegate {

    func enqueueReload() {}

    func enqueueReloadWithoutCaches() {}

    func didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    func didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

    func didDoubleTapTextViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didLongPressTextViewItem(_ cell: CVCell,
                                  itemViewModel: CVItemViewModelImpl,
                                  shouldAllowReply: Bool) {}

    func didLongPressMediaViewItem(_ cell: CVCell,
                                   itemViewModel: CVItemViewModelImpl,
                                   shouldAllowReply: Bool) {}

    func didLongPressQuote(_ cell: CVCell,
                           itemViewModel: CVItemViewModelImpl,
                           shouldAllowReply: Bool) {}

    func didLongPressSystemMessage(_ cell: CVCell,
                                   itemViewModel: CVItemViewModelImpl) {}

    func didLongPressSticker(_ cell: CVCell,
                             itemViewModel: CVItemViewModelImpl,
                             shouldAllowReply: Bool) {}

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

    func didTapReactions(reactionState: InteractionReactionState,
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

    // MARK: - Messages

    func didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachmentStream: ReferencedAttachmentStream,
        imageView: UIView
    ) {}

    func didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction { .default }

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

    // Never wrap gifts on the mock conversation view
    func willWrapGift(_ messageUniqueId: String) -> Bool { false }

    func willShakeGift(_ messageUniqueId: String) -> Bool { false }

    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge, isExpired: Bool, isRedeemed: Bool) {}

    func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        return {}
    }

    var view: UIView! { self }

    var isConversationPreview: Bool { true }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    var spoilerState: SpoilerRenderState { return SpoilerRenderState() }

    // MARK: - Selection

    public var selectionState: CVSelectionState { CVSelectionState() }

    // MARK: - System Cell

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
        requesterAci: Aci
    ) {}

    func didTapShowUpgradeAppUI() {}

    func didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                   newNameComponents: PersonNameComponents) {}

    func didTapPhoneNumberChange(aci: Aci, phoneNumberOld: String, phoneNumberNew: String) {}

    func didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func didTapViewOnceExpired(_ interaction: TSInteraction) {}

    func didTapContactName(thread: TSContactThread) {}

    func didTapUnknownThreadWarningGroup() {}
    func didTapUnknownThreadWarningContact() {}
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}

    func didLongPressPaymentMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool
    ) { }

    func didTapPayment(_ payment: PaymentsHistoryItem) {}

    func didTapActivatePayments() {}
    func didTapSendPayment() {}

    func didTapThreadMergeLearnMore(phoneNumber: String) {}

    func didTapReportSpamLearnMore() {}

    func didTapMessageRequestAcceptedOptions() {}

    func didTapJoinCallLinkCall(callLink: CallLink) {}

    func didTapViewVotes(poll: OWSPoll) {}
}
