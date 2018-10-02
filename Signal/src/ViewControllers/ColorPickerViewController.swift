//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class OWSColorPickerAccessoryView: NeverClearView {
    override var intrinsicContentSize: CGSize {
        return CGSize(width: kSwatchSize, height: kSwatchSize)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return self.intrinsicContentSize
    }

    let kSwatchSize: CGFloat = 24

    @objc
    required init(color: UIColor) {
        super.init(frame: .zero)

        let circleView = CircleView()
        circleView.backgroundColor = color
        addSubview(circleView)
        circleView.autoSetDimensions(to: CGSize(width: kSwatchSize, height: kSwatchSize))
        circleView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@objc (OWSCircleView)
class CircleView: UIView {
    override var bounds: CGRect {
        didSet {
            self.layer.cornerRadius = self.bounds.size.height / 2
        }
    }
}

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
        selectedRing.autoSetDimensions(to: CGSize(width: cellHeight, height: cellHeight))

        selectedRing.layer.borderColor = Theme.secondaryColor.cgColor
        selectedRing.layer.borderWidth = 2
        selectedRing.autoPinEdgesToSuperviewEdges()
        selectedRing.isHidden = true

        // Color Swatch
        swatchView.backgroundColor = conversationColor.primaryColor

        let swatchSize: CGFloat = ScaleFromIPhone5(46)
        swatchView.autoSetDimensions(to: CGSize(width: swatchSize, height: swatchSize))

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

    private let colorViews: [ColorView]
    let conversationStyle: ConversationStyle
    var outgoingMessageView = OWSMessageBubbleView(forAutoLayout: ())
    var incomingMessageView = OWSMessageBubbleView(forAutoLayout: ())
    weak var delegate: ColorPickerViewDelegate?

    // This is mostly a developer convenience - OWSMessageCell asserts at some point
    // that the available method width is greater than 0.
    // We ultimately use the width of the picker view which will be larger.
    let kMinimumConversationWidth: CGFloat = 300
    override var bounds: CGRect {
        didSet {
            updateMockConversationView()
        }
    }

    let mockConversationView: UIView = UIView()

    init(thread: TSThread) {
        let allConversationColors = OWSConversationColor.conversationColorNames.map { OWSConversationColor.conversationColorOrDefault(colorName: $0) }

        self.colorViews = allConversationColors.map { ColorView(conversationColor: $0) }

        self.conversationStyle = ConversationStyle(thread: thread)

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
        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        titleLabel.textColor = Theme.primaryColor

        headerView.addSubview(titleLabel)
        titleLabel.ows_autoPinToSuperviewMargins()

        let bottomBorderView = UIView()
        bottomBorderView.backgroundColor = Theme.hairlineColor
        headerView.addSubview(bottomBorderView)
        bottomBorderView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        bottomBorderView.autoSetDimension(.height, toSize: CGHairlineWidth())

        return headerView
    }

    private func updateMockConversationView() {
        conversationStyle.viewWidth = max(bounds.size.width, kMinimumConversationWidth)
        mockConversationView.subviews.forEach { $0.removeFromSuperview() }

        // outgoing
        outgoingMessageView = OWSMessageBubbleView(forAutoLayout: ())
        let outgoingItem = MockConversationViewItem()
        let outgoingText = NSLocalizedString("COLOR_PICKER_DEMO_MESSAGE_1", comment: "The first of two messages demonstrating the chosen conversation color, by rendering this message in an outgoing message bubble.")
        outgoingItem.interaction = MockOutgoingMessage(messageBody: outgoingText)
        outgoingItem.displayableBodyText = DisplayableText.displayableText(outgoingText)
        outgoingItem.interactionType = .outgoingMessage

        outgoingMessageView.viewItem = outgoingItem
        outgoingMessageView.cellMediaCache = NSCache()
        outgoingMessageView.conversationStyle = conversationStyle
        outgoingMessageView.configureViews()
        outgoingMessageView.loadContent()
        let outgoingCell = UIView()
        outgoingCell.addSubview(outgoingMessageView)
        outgoingMessageView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .leading)
        let outgoingSize = outgoingMessageView.measureSize()
        outgoingMessageView.autoSetDimensions(to: outgoingSize)

        // incoming
        incomingMessageView = OWSMessageBubbleView(forAutoLayout: ())
        let incomingItem = MockConversationViewItem()
        let incomingText = NSLocalizedString("COLOR_PICKER_DEMO_MESSAGE_2", comment: "The second of two messages demonstrating the chosen conversation color, by rendering this message in an incoming message bubble.")
        incomingItem.interaction = MockIncomingMessage(messageBody: incomingText)
        incomingItem.displayableBodyText = DisplayableText.displayableText(incomingText)
        incomingItem.interactionType = .incomingMessage

        incomingMessageView.viewItem = incomingItem
        incomingMessageView.cellMediaCache = NSCache()
        incomingMessageView.conversationStyle = conversationStyle
        incomingMessageView.configureViews()
        incomingMessageView.loadContent()
        let incomingCell = UIView()
        incomingCell.addSubview(incomingMessageView)
        incomingMessageView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .trailing)
        let incomingSize = incomingMessageView.measureSize()
        incomingMessageView.autoSetDimensions(to: incomingSize)

        let messagesStackView = UIStackView(arrangedSubviews: [outgoingCell, incomingCell])
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
            row.distribution = UIStackViewDistribution.equalSpacing
            return row
        }
        let rowsStackView = UIStackView(arrangedSubviews: rows)
        rowsStackView.axis = .vertical
        rowsStackView.spacing = ScaleFromIPhone5To7Plus(12, 30)

        paletteView.addSubview(rowsStackView)
        rowsStackView.ows_autoPinToSuperviewMargins()

        // no-op gesture to keep taps from dismissing SheetView
        paletteView.addGestureRecognizer(UITapGestureRecognizer(target: nil, action: nil))
        return paletteView
    }
}

// MARK: Mock Classes for rendering demo conversation

@objc
private class MockConversationViewItem: NSObject, ConversationViewItem {
    var interaction: TSInteraction = TSMessage()
    var interactionType: OWSInteractionType = OWSInteractionType.unknown
    var quotedReply: OWSQuotedReplyModel?
    var isGroupThread: Bool = false
    var hasBodyText: Bool = true
    var isQuotedReply: Bool = false
    var hasQuotedAttachment: Bool = false
    var hasQuotedText: Bool = false
    var hasCellHeader: Bool = false
    var isExpiringMessage: Bool = false
    var shouldShowDate: Bool = false
    var shouldShowSenderAvatar: Bool = false
    var senderName: NSAttributedString?
    var shouldHideFooter: Bool = false
    var isFirstInCluster: Bool = true
    var isLastInCluster: Bool = true
    var unreadIndicator: OWSUnreadIndicator?
    var lastAudioMessageView: OWSAudioMessageView?
    var audioDurationSeconds: CGFloat = 0
    var audioProgressSeconds: CGFloat = 0
    var messageCellType: OWSMessageCellType = .textMessage
    var displayableBodyText: DisplayableText?
    var attachmentStream: TSAttachmentStream?
    var attachmentPointer: TSAttachmentPointer?
    var mediaSize: CGSize  = .zero
    var displayableQuotedText: DisplayableText?
    var quotedAttachmentMimetype: String?
    var quotedRecipientId: String?
    var didCellMediaFailToLoad: Bool = false
    var contactShare: ContactShareViewModel?
    var systemMessageText: String?
    var authorConversationColorName: String?
    var hasBodyTextActionContent: Bool = false
    var hasMediaActionContent: Bool = false

    override init() {
        super.init()
    }

    func dequeueCell(for collectionView: UICollectionView, indexPath: IndexPath) -> ConversationViewCell {
        owsFailDebug("unexpected invocation")
        return ConversationViewCell(forAutoLayout: ())
    }

    func replace(_ interaction: TSInteraction, transaction: YapDatabaseReadTransaction) {
        owsFailDebug("unexpected invocation")
        return
    }

    func clearCachedLayoutState() {
        owsFailDebug("unexpected invocation")
        return
    }

    func copyMediaAction() {
        owsFailDebug("unexpected invocation")
        return
    }

    func copyTextAction() {
        owsFailDebug("unexpected invocation")
        return
    }

    func shareMediaAction() {
        owsFailDebug("unexpected invocation")
        return
    }

    func shareTextAction() {
        owsFailDebug("unexpected invocation")
        return
    }

    func saveMediaAction() {
        owsFailDebug("unexpected invocation")
        return
    }

    func deleteAction() {
        owsFailDebug("unexpected invocation")
        return
    }

    func canSaveMedia() -> Bool {
        owsFailDebug("unexpected invocation")
        return false
    }

    func audioPlaybackState() -> AudioPlaybackState {
        owsFailDebug("unexpected invocation")
        return AudioPlaybackState.paused
    }

    func setAudioPlaybackState(_ state: AudioPlaybackState) {
        owsFailDebug("unexpected invocation")
        return
    }

    func setAudioProgress(_ progress: CGFloat, duration: CGFloat) {
        owsFailDebug("unexpected invocation")
        return
    }

    func cellSize() -> CGSize {
        owsFailDebug("unexpected invocation")
        return CGSize.zero
    }

    func vSpacing(withPreviousLayoutItem previousLayoutItem: ConversationViewLayoutItem) -> CGFloat {
        owsFailDebug("unexpected invocation")
        return 2
    }
}

private class MockIncomingMessage: TSIncomingMessage {
    init(messageBody: String) {
        super.init(incomingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(),
                   in: TSThread(),
                   authorId: "+fake-id",
                   sourceDeviceId: 1,
                   messageBody: messageBody,
                   attachmentIds: [],
                   expiresInSeconds: 0,
                   quotedMessage: nil,
                   contactShare: nil)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }

    override func save(with transaction: YapDatabaseReadWriteTransaction) {
        // no - op
        owsFailDebug("shouldn't save mock message")
    }
}

private class MockOutgoingMessage: TSOutgoingMessage {
    init(messageBody: String) {
        super.init(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(),
                   in: nil,
                   messageBody: messageBody,
                   attachmentIds: [],
                   expiresInSeconds: 0,
                   expireStartedAt: 0,
                   isVoiceMessage: false,
                   groupMetaMessage: .unspecified,
                   quotedMessage: nil,
                   contactShare: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }

    override func save(with transaction: YapDatabaseReadWriteTransaction) {
        // no - op
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

    override func readRecipientIds() -> [String] {
        // makes message appear as read
        return ["fake-non-empty-id"]
    }

    override func recipientState(forRecipientId recipientId: String) -> TSOutgoingMessageRecipientState? {
        return MockOutgoingMessageRecipientState()
    }
}
