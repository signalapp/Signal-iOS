//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class OWSColorPickerAccessoryView: NeverClearView {
    override var intrinsicContentSize: CGSize {
        return CGSize(square: kSwatchSize)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return self.intrinsicContentSize
    }

    let kSwatchSize: CGFloat = 24

    @objc
    required init(color: UIColor) {
        super.init(frame: .zero)

        let circleView = CircleView(diameter: kSwatchSize)
        circleView.backgroundColor = color
        addSubview(circleView)
        circleView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

protocol ColorViewDelegate: class {
    func colorViewWasTapped(_ colorView: ColorView)
}

class ColorView: UIView {
    public weak var delegate: ColorViewDelegate?
    public let conversationColor: OWSConversationColor

    private let swatchView: CircleView
    private let selectedRing: CircleView
    public var isSelected: Bool = false {
        didSet {
            self.selectedRing.isHidden = !isSelected
        }
    }

    required init(conversationColor: OWSConversationColor) {
        self.conversationColor = conversationColor
        self.swatchView = CircleView()
        self.selectedRing = CircleView()

        super.init(frame: .zero)
        self.addSubview(selectedRing)
        self.addSubview(swatchView)

        // Selected Ring
        let cellHeight: CGFloat = ScaleFromIPhone5(60)
        selectedRing.autoSetDimensions(to: CGSize(square: cellHeight))

        selectedRing.layer.borderColor = Theme.secondaryTextAndIconColor.cgColor
        selectedRing.layer.borderWidth = 2
        selectedRing.autoPinEdgesToSuperviewEdges()
        selectedRing.isHidden = true

        // Color Swatch
        swatchView.backgroundColor = conversationColor.primaryColor

        let swatchSize: CGFloat = ScaleFromIPhone5(46)
        swatchView.autoSetDimensions(to: CGSize(square: swatchSize))

        swatchView.autoCenterInSuperview()

        // gestures
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        self.addGestureRecognizer(tapGesture)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: Actions

    @objc
    func didTap() {
        delegate?.colorViewWasTapped(self)
    }
}

@objc
protocol ColorPickerDelegate: class {
    func colorPicker(_ colorPicker: ColorPicker, didPickConversationColor conversationColor: OWSConversationColor)
}

@objc(OWSColorPicker)
class ColorPicker: NSObject, ColorPickerViewDelegate {

    @objc
    public weak var delegate: ColorPickerDelegate?

    @objc
    let sheetViewController: SheetViewController

    @objc
    init(thread: TSThread) {
        let colorName = thread.conversationColorName
        let currentConversationColor = OWSConversationColor.conversationColorOrDefault(colorName: colorName)
        sheetViewController = SheetViewController()

        super.init()

        let colorPickerView = ColorPickerView(thread: thread)
        colorPickerView.delegate = self
        colorPickerView.select(conversationColor: currentConversationColor)

        sheetViewController.contentView.addSubview(colorPickerView)
        colorPickerView.autoPinEdgesToSuperviewEdges()
    }

    // MARK: ColorPickerViewDelegate

    func colorPickerView(_ colorPickerView: ColorPickerView, didPickConversationColor conversationColor: OWSConversationColor) {
        self.delegate?.colorPicker(self, didPickConversationColor: conversationColor)
    }
}

protocol ColorPickerViewDelegate: class {
    func colorPickerView(_ colorPickerView: ColorPickerView, didPickConversationColor conversationColor: OWSConversationColor)
}

class ColorPickerView: UIView, ColorViewDelegate {

    private let thread: TSThread
    private let colorViews: [ColorView]
    var conversationStyle: ConversationStyle
    weak var delegate: ColorPickerViewDelegate?

    // This is mostly a developer convenience - OWSMessageCell asserts at some point
    // that the available method width is greater than 0.
    // We ultimately use the width of the picker view which will be larger.
    let kMinimumConversationWidth: CGFloat = 300
    override var bounds: CGRect {
        didSet {
            let didChangeWidth = bounds.width != oldValue.width
            if didChangeWidth {
                updateMockConversationView()
            }
        }
    }

    let mockConversationView: UIView = UIView()

    init(thread: TSThread) {

        self.thread = thread

        let allConversationColors = OWSConversationColor.conversationColorNames.map { OWSConversationColor.conversationColorOrDefault(colorName: $0) }

        self.colorViews = allConversationColors.map { ColorView(conversationColor: $0) }

        self.conversationStyle = ConversationStyle(type: .`default`,
                                                   thread: thread,
                                                   viewWidth: 0)

        super.init(frame: .zero)

        colorViews.forEach { $0.delegate = self }

        let headerView = self.buildHeaderView()
        mockConversationView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        mockConversationView.backgroundColor = Theme.backgroundColor
        self.updateMockConversationView()

        let paletteView = self.buildPaletteView(colorViews: colorViews)

        let rowsStackView = UIStackView(arrangedSubviews: [headerView, mockConversationView, paletteView])
        rowsStackView.axis = .vertical
        addSubview(rowsStackView)
        rowsStackView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: ColorViewDelegate

    func colorViewWasTapped(_ colorView: ColorView) {
        self.select(conversationColor: colorView.conversationColor)
        self.delegate?.colorPickerView(self, didPickConversationColor: colorView.conversationColor)
        updateMockConversationView()
    }

    fileprivate func select(conversationColor selectedConversationColor: OWSConversationColor) {
        colorViews.forEach { colorView in
            colorView.isSelected = colorView.conversationColor == selectedConversationColor
        }
    }

    // MARK: View Building

    private func buildHeaderView() -> UIView {
        let headerView = UIView()
        headerView.layoutMargins = UIEdgeInsets(top: 15, left: 16, bottom: 15, right: 16)

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("COLOR_PICKER_SHEET_TITLE", comment: "Modal Sheet title when picking a conversation color.")
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor

        headerView.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()

        let bottomBorderView = UIView()
        bottomBorderView.backgroundColor = Theme.hairlineColor
        headerView.addSubview(bottomBorderView)
        bottomBorderView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        bottomBorderView.autoSetDimension(.height, toSize: CGHairlineWidth())

        return headerView
    }

    private func updateMockConversationView() {
        let viewWidth = max(bounds.size.width, kMinimumConversationWidth)
        self.conversationStyle = ConversationStyle(type: .`default`,
                                                   thread: self.thread,
                                                   viewWidth: viewWidth)

        mockConversationView.subviews.forEach { $0.removeFromSuperview() }

        let containerView = self
        guard containerView.width > 0 else {
            return
        }

        var outgoingRenderItem: CVRenderItem?
        var incomingRenderItem: CVRenderItem?

        databaseStorage.uiRead { transaction in
            let thread = MockThread(contactAddress: SignalServiceAddress(phoneNumber: "+fake-id"))

            let outgoingText = NSLocalizedString("COLOR_PICKER_DEMO_MESSAGE_1", comment: "The first of two messages demonstrating the chosen conversation color, by rendering this message in an outgoing message bubble.")
            let outgoingMessage = MockOutgoingMessage(messageBody: outgoingText, thread: thread)

            let incomingText = NSLocalizedString("COLOR_PICKER_DEMO_MESSAGE_2", comment: "The second of two messages demonstrating the chosen conversation color, by rendering this message in an incoming message bubble.")
            let incomingMessage = MockIncomingMessage(messageBody: incomingText, thread: thread)

            outgoingRenderItem = CVLoader.buildStandaloneRenderItem(interaction: outgoingMessage,
                                                                    thread: thread,
                                                                    containerView: containerView,
                                                                    transaction: transaction)
            incomingRenderItem = CVLoader.buildStandaloneRenderItem(interaction: incomingMessage,
                                                                    thread: thread,
                                                                    containerView: containerView,
                                                                    transaction: transaction)
        }

        let outgoingMessageView = CVCellView()
        let incomingMessageView = CVCellView()
        if let renderItem = outgoingRenderItem {
            outgoingMessageView.configure(renderItem: renderItem, componentDelegate: self)
        } else {
            owsFailDebug("Missing outgoingRenderItem.")
        }
        if let renderItem = incomingRenderItem {
            incomingMessageView.configure(renderItem: renderItem, componentDelegate: self)
        } else {
            owsFailDebug("Missing incomingRenderItem.")
        }
        outgoingMessageView.isCellVisible = true
        incomingMessageView.isCellVisible = true

        let messagesStackView = UIStackView(arrangedSubviews: [outgoingMessageView, incomingMessageView])
        messagesStackView.axis = .vertical
        messagesStackView.spacing = 12

        mockConversationView.addSubview(messagesStackView)
        messagesStackView.autoPinEdgesToSuperviewMargins()
    }

    private func buildPaletteView(colorViews: [ColorView]) -> UIView {
        let paletteView = UIView()
        let paletteMargin = ScaleFromIPhone5(12)
        paletteView.layoutMargins = UIEdgeInsets(top: paletteMargin, left: paletteMargin, bottom: 0, right: paletteMargin)

        let kRowLength = 4
        let rows: [UIView] = colorViews.chunked(by: kRowLength).map { colorViewsInRow in
            let row = UIStackView(arrangedSubviews: colorViewsInRow)
            row.distribution = UIStackView.Distribution.equalSpacing
            return row
        }
        let rowsStackView = UIStackView(arrangedSubviews: rows)
        rowsStackView.axis = .vertical
        rowsStackView.spacing = ScaleFromIPhone5To7Plus(12, 30)

        paletteView.addSubview(rowsStackView)
        rowsStackView.autoPinEdgesToSuperviewMargins()

        // no-op gesture to keep taps from dismissing SheetView
        paletteView.addGestureRecognizer(UITapGestureRecognizer(target: nil, action: nil))
        return paletteView
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

    override func readRecipientAddresses() -> [SignalServiceAddress] {
        // makes message appear as read
        return [SignalServiceAddress(phoneNumber: "+123123123123123123")]
    }

    override func recipientState(for recipientAddress: SignalServiceAddress) -> TSOutgoingMessageRecipientState? {
        return MockOutgoingMessageRecipientState()
    }
}

// MARK: -

extension ColorPickerView: CVComponentDelegate {

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

    func cvc_didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) {}

    func cvc_didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel) {}

    func cvc_didTapLinkPreview(_ linkPreview: OWSLinkPreview) {}

    func cvc_didTapContactShare(_ contactShare: ContactShareViewModel) {}

    func cvc_didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {}

    func cvc_didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {}

    func cvc_didTapAddToContacts(contactShare: ContactShareViewModel) {}

    func cvc_didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {}

    func cvc_didTapGroupInviteLink(url: URL) {}

    func cvc_didTapMention(_ mention: Mention) {}

    // MARK: - Selection

    var isShowingSelectionUI: Bool { false }

    func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool { false }

    func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: - System Cell

    func cvc_didTapNonBlockingIdentityChange(_ address: SignalServiceAddress) {}

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
