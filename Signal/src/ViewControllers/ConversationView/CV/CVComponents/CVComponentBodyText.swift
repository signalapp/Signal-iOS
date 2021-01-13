//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentBodyText: CVComponentBase, CVComponent {

    struct State: Equatable {
        let bodyText: CVComponentState.BodyText
        let isTextExpanded: Bool
        let searchText: String?
        let hasTapForMore: Bool
        let shouldUseAttributedText: Bool

        public var canUseDedicatedCell: Bool {
            if hasTapForMore || searchText != nil {
                return false
            }
            switch bodyText {
            case .bodyText:
                return true
            case .oversizeTextDownloading:
                return false
            case .remotelyDeleted:
                return false
            }
        }

        var textValue: CVTextValue? {
            bodyText.textValue(isTextExpanded: isTextExpanded)
        }
    }
    private let bodyTextState: State

    private var bodyText: CVComponentState.BodyText {
        bodyTextState.bodyText
    }
    private var textValue: CVTextValue? {
        bodyTextState.textValue
    }
    private var isTextExpanded: Bool {
        bodyTextState.isTextExpanded
    }
    private var searchText: String? {
        bodyTextState.searchText
    }
    private var hasTapForMore: Bool {
        bodyTextState.hasTapForMore
    }
    public var shouldUseAttributedText: Bool {
        bodyTextState.shouldUseAttributedText
    }

    init(itemModel: CVItemModel, bodyTextState: State) {
        self.bodyTextState = bodyTextState

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewBodyText(componentDelegate: componentDelegate)
    }

    private var isJumbomoji: Bool {
        componentState.isJumbomojiMessage
    }

    private static func buildDataDetectorWithLinks(shouldAllowLinkification: Bool) -> NSDataDetector? {
        let uiDataDetectorTypes: UIDataDetectorTypes = (shouldAllowLinkification
                                                            ? kOWSAllowedDataDetectorTypes
                                                            : kOWSAllowedDataDetectorTypesExceptLinks)
        var nsDataDetectorTypes: NSTextCheckingTypes = 0
        if uiDataDetectorTypes.contains(UIDataDetectorTypes.link) {
            nsDataDetectorTypes |= NSTextCheckingResult.CheckingType.link.rawValue
        }
        if uiDataDetectorTypes.contains(UIDataDetectorTypes.address) {
            nsDataDetectorTypes |= NSTextCheckingResult.CheckingType.address.rawValue
        }
        // TODO: There doesn't seem to be an equivalent to UIDataDetectorTypes.calendarEvent.

        do {
            return try NSDataDetector(types: nsDataDetectorTypes)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private static var dataDetectorWithLinks: NSDataDetector? = {
        buildDataDetectorWithLinks(shouldAllowLinkification: true)
    }()

    private static var dataDetectorWithoutLinks: NSDataDetector? = {
        buildDataDetectorWithLinks(shouldAllowLinkification: false)
    }()

    // DataDetectors are expensive to build, so we reuse them.
    private static func dataDetector(shouldAllowLinkification: Bool) -> NSDataDetector? {
        shouldAllowLinkification ? dataDetectorWithLinks : dataDetectorWithoutLinks
    }

    private static let unfairLock = UnfairLock()

    private static func shouldUseAttributedText(text: String,
                                                shouldAllowLinkification: Bool) -> Bool {
        // Use a lock to ensure that measurement on and off the main thread
        // don't conflict.
        unfairLock.withLock {
            // NSDataDetector and UIDataDetector behavior should be aligned.
            //
            // TODO: We might want to move this detection logic into
            // DisplayableText so that we can leverage caching.
            guard let detector = dataDetector(shouldAllowLinkification: shouldAllowLinkification) else {
                // If the data detectors can't be built, default to using attributed text.
                owsFailDebug("Could not build dataDetector.")
                return true
            }
            return !detector.matches(in: text, options: [], range: text.entireRange).isEmpty
        }
    }

    static func buildState(interaction: TSInteraction,
                           bodyText: CVComponentState.BodyText,
                           viewStateSnapshot: CVViewStateSnapshot,
                           hasTapForMore: Bool) -> State {
        let textExpansion = viewStateSnapshot.textExpansion
        let searchText = viewStateSnapshot.searchText
        let isTextExpanded = textExpansion.isTextExpanded(interactionId: interaction.uniqueId)

        var shouldUseAttributedText = false
        if let displayableText = bodyText.displayableText,
           let textValue = bodyText.textValue(isTextExpanded: isTextExpanded) {
            switch textValue {
            case .text(let text):
                // UILabels are much cheaper than UITextViews, and we can
                // usually use them for rendering body text.
                //
                // We need to use attributed text in a UITextViews if:
                //
                // * We're displaying search results (and need to highlight matches).
                // * The text value is an attributed string (has mentions).
                // * The text value should be linkified.
                if searchText != nil {
                    shouldUseAttributedText = true
                } else {
                    let shouldAllowLinkification = displayableText.shouldAllowLinkification
                    shouldUseAttributedText = self.shouldUseAttributedText(text: text,
                                                                           shouldAllowLinkification: shouldAllowLinkification)
                }
            case .attributedText:
                shouldUseAttributedText = true
            }
        }

        return State(bodyText: bodyText,
                     isTextExpanded: isTextExpanded,
                     searchText: searchText,
                     hasTapForMore: hasTapForMore,
                     shouldUseAttributedText: shouldUseAttributedText)
    }

    static func buildComponentState(message: TSMessage,
                                    transaction: SDSAnyReadTransaction) throws -> CVComponentState.BodyText? {

        func build(displayableText: DisplayableText) -> CVComponentState.BodyText? {
            guard !displayableText.fullTextValue.stringValue.isEmpty else {
                return nil
            }
            return .bodyText(displayableText: displayableText)
        }

        // TODO: We might want to treat text that is completely stripped
        // as not present.
        if let oversizeTextAttachment = message.oversizeTextAttachment(with: transaction.unwrapGrdbRead) {
            if let oversizeTextAttachmentStream = oversizeTextAttachment as? TSAttachmentStream {
                let displayableText = CVComponentState.displayableBodyText(oversizeTextAttachment: oversizeTextAttachmentStream,
                                                                           ranges: message.bodyRanges,
                                                                           interaction: message,
                                                                           transaction: transaction)
                return build(displayableText: displayableText)
            } else if nil != oversizeTextAttachment as? TSAttachmentPointer {
                // TODO: Handle backup restore.
                // TODO: If there's media, should we display that while the oversize text is downloading?
                return .oversizeTextDownloading
            } else {
                throw OWSAssertionError("Invalid oversizeTextAttachment.")
            }
        } else if let body = message.body, !body.isEmpty {
            let displayableText = CVComponentState.displayableBodyText(text: body,
                                                                       ranges: message.bodyRanges,
                                                                       interaction: message,
                                                                       transaction: transaction)
            return build(displayableText: displayableText)
        } else {
            // No body text.
            return nil
        }
    }

    private var textMessageFont: UIFont {
        owsAssertDebug(DisplayableText.kMaxJumbomojiCount == 5)

        if isJumbomoji, let jumbomojiCount = bodyText.jumbomojiCount {
            let basePointSize = UIFont.ows_dynamicTypeBodyClamped.pointSize
            switch jumbomojiCount {
            case 0:
                break
            case 1:
                return UIFont.ows_regularFont(withSize: basePointSize * 3.5)
            case 2:
                return UIFont.ows_regularFont(withSize: basePointSize * 3.0)
            case 3:
                return UIFont.ows_regularFont(withSize: basePointSize * 2.75)
            case 4:
                return UIFont.ows_regularFont(withSize: basePointSize * 2.5)
            case 5:
                return UIFont.ows_regularFont(withSize: basePointSize * 2.25)
            default:
                owsFailDebug("Unexpected jumbomoji count: \(jumbomojiCount)")
                break
            }
        }

        return UIFont.ows_dynamicTypeBody
    }

    private var bodyTextColor: UIColor {
        guard let message = interaction as? TSMessage else {
            return .black
        }
        return conversationStyle.bubbleTextColor(message: message)
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewBodyText else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let hStackView = componentView.hStackView
        hStackView.apply(config: stackViewConfig)

        switch bodyText {
        case .bodyText(let displayableText):
            configureForBodyText(componentView: componentView, displayableText: displayableText)
        case .oversizeTextDownloading:
            owsAssertDebug(!componentView.isDedicatedCellView)

            configureForOversizeTextDownloading(componentView: componentView)
        case .remotelyDeleted:
            owsAssertDebug(!componentView.isDedicatedCellView)

            configureForRemotelyDeleted(componentView: componentView)
        }
    }

    private func configureForRemotelyDeleted(componentView: CVComponentViewBodyText) {
        // TODO: Set accessibilityLabel.
        _ = configureForLabel(componentView: componentView,
                          labelConfig: labelConfigForRemotelyDeleted)
    }

    private func configureForOversizeTextDownloading(componentView: CVComponentViewBodyText) {
        // TODO: Set accessibilityLabel.
        _ = configureForLabel(componentView: componentView,
                          labelConfig: labelConfigForOversizeTextDownloading)
    }

    private func configureForLabel(componentView: CVComponentViewBodyText,
                                   labelConfig: CVLabelConfig) -> UILabel {
        let label = componentView.ensuredLabel
        labelConfig.applyForRendering(label: label)

        label.isHiddenInStackView = false
        if label.superview == nil {
            let hStackView = componentView.hStackView
            hStackView.addArrangedSubview(label)
            label.setCompressionResistanceVerticalHigh()
        }
        componentView.possibleTextView?.isHiddenInStackView = true

        return label
    }

    public func configureForBodyText(componentView: CVComponentViewBodyText,
                                     displayableText: DisplayableText) {

        switch textConfig(displayableText: displayableText) {
        case .labelConfig(let labelConfig):
            let label = configureForLabel(componentView: componentView, labelConfig: labelConfig)
            label.accessibilityLabel = accessibilityLabel(description: labelConfig.stringValue)
        case .textViewConfig(let textViewConfig):
            let textView = componentView.ensuredTextView

            var shouldIgnoreEvents = false
            if let outgoingMessage = interaction as? TSOutgoingMessage {
                // Ignore taps on links in outgoing messages that haven't been sent yet, as
                // this interferes with "tap to retry".
                shouldIgnoreEvents = outgoingMessage.messageState != .sent
            }
            textView.shouldIgnoreEvents = shouldIgnoreEvents

            textView.ensureShouldLinkifyText(displayableText.shouldAllowLinkification)

            textViewConfig.applyForRendering(textView: textView)

            textView.accessibilityLabel = accessibilityLabel(description: textViewConfig.stringValue)

            textView.isHiddenInStackView = false
            if textView.superview == nil {
                let hStackView = componentView.hStackView
                hStackView.addArrangedSubview(textView)
            }
            componentView.possibleLabel?.isHiddenInStackView = true
        }
    }

    private var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private var labelConfigForRemotelyDeleted: CVLabelConfig {
        let text = (isIncoming
                        ? NSLocalizedString("THIS_MESSAGE_WAS_DELETED", comment: "text indicating the message was remotely deleted")
                        : NSLocalizedString("YOU_DELETED_THIS_MESSAGE", comment: "text indicating the message was remotely deleted by you"))
        return CVLabelConfig(text: text,
                             font: textMessageFont.ows_italic,
                             textColor: bodyTextColor,
                             numberOfLines: 0,
                             lineBreakMode: .byWordWrapping,
                             textAlignment: .center)
    }

    private var labelConfigForOversizeTextDownloading: CVLabelConfig {
        let text = NSLocalizedString("MESSAGE_STATUS_DOWNLOADING",
                                     comment: "message status while message is downloading.")
        return CVLabelConfig(text: text,
                             font: textMessageFont.ows_italic,
                             textColor: bodyTextColor,
                             numberOfLines: 0,
                             lineBreakMode: .byWordWrapping,
                             textAlignment: .center)
    }

    private enum TextConfig {
        case labelConfig(labelConfig: CVLabelConfig)
        case textViewConfig(textViewConfig: CVTextViewConfig)
    }

    private func textConfig(displayableText: DisplayableText) -> TextConfig {

        let textValue = displayableText.textValue(isTextExpanded: isTextExpanded)

        switch textValue {
        case .text(let text):
            if shouldUseAttributedText {
                let attributedText = NSAttributedString(string: text)
                let textViewConfig = self.textViewConfig(displayableText: displayableText,
                                                         attributedText: attributedText)
                return .textViewConfig(textViewConfig: textViewConfig)
            } else {
                let labelConfig = CVLabelConfig(
                    text: text,
                    font: textMessageFont,
                    textColor: bodyTextColor,
                    numberOfLines: 0,
                    lineBreakMode: .byWordWrapping,
                    textAlignment: isTextExpanded
                        ? displayableText.fullTextNaturalAlignment
                        : displayableText.displayTextNaturalAlignment
                )
                return .labelConfig(labelConfig: labelConfig)
            }
        case .attributedText(let attributedText):
            let textViewConfig = self.textViewConfig(displayableText: displayableText,
                                                     attributedText: attributedText)
            return .textViewConfig(textViewConfig: textViewConfig)
        }
    }

    private func textViewConfig(displayableText: DisplayableText,
                                attributedText attributedTextParam: NSAttributedString) -> CVTextViewConfig {

        // Honor dynamic type in the message bodies.
        let linkTextAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.foregroundColor: bodyTextColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let textAlignment = (isTextExpanded
                                ? displayableText.fullTextNaturalAlignment
                                : displayableText.displayTextNaturalAlignment)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment

        let attributedText = attributedTextParam.mutableCopy() as! NSMutableAttributedString
        attributedText.addAttributes(
            [
                .font: textMessageFont,
                .foregroundColor: bodyTextColor,
                .paragraphStyle: paragraphStyle
            ],
            range: attributedText.entireRange
        )

        if let searchText = searchText,
           searchText.count >= ConversationSearchController.kMinimumSearchTextLength {
            let searchableText = FullTextSearchFinder.normalize(text: searchText)
            let pattern = NSRegularExpression.escapedPattern(for: searchableText)
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                for match in regex.matches(in: attributedText.string,
                                           options: [.withoutAnchoringBounds],
                                           range: attributedText.string.entireRange) {
                    owsAssertDebug(match.range.length >= ConversationSearchController.kMinimumSearchTextLength)
                    attributedText.addAttribute(.backgroundColor, value: UIColor.yellow, range: match.range)
                    attributedText.addAttribute(.foregroundColor, value: UIColor.ows_black, range: match.range)
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }

        return CVTextViewConfig(attributedText: attributedText,
                                font: textMessageFont,
                                textColor: bodyTextColor,
                                linkTextAttributes: linkTextAttributes)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        switch bodyText {
        case .bodyText(let displayableText):
            switch textConfig(displayableText: displayableText) {
            case .labelConfig(let labelConfig):
                return CVText.measureLabel(config: labelConfig, maxWidth: maxWidth).ceil
            case .textViewConfig(let textViewConfig):
                return CVText.measureTextView(config: textViewConfig, maxWidth: maxWidth).ceil
            }
        case .oversizeTextDownloading:
            return CVText.measureLabel(config: labelConfigForOversizeTextDownloading, maxWidth: maxWidth).ceil
        case .remotelyDeleted:
            return CVText.measureLabel(config: labelConfigForRemotelyDeleted, maxWidth: maxWidth).ceil
        }
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        if let mention = tappedMention(sender: sender,
                                       componentView: componentView) {
            componentDelegate.cvc_didTapMention(mention)
            return true
        }

        if hasTapForMore {
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            componentDelegate.cvc_didTapTruncatedTextMessage(itemViewModel)
            return true
        }

        return false
    }

    private func tappedMention(sender: UITapGestureRecognizer,
                               componentView: CVComponentView) -> Mention? {
        guard let message = interaction as? TSMessage,
              let bodyRanges = message.bodyRanges,
              bodyRanges.hasMentions else {
            return nil
        }
        guard let componentView = componentView as? CVComponentViewBodyText else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        guard let textView = componentView.possibleTextView else {
            // Not using a text view.
            return nil
        }
        let location = sender.location(in: textView)
        guard textView.bounds.contains(location) else {
            return nil
        }

        let tappedCharacterIndex = textView.layoutManager.characterIndex(for: location,
                                                                         in: textView.textContainer,
                                                                         fractionOfDistanceBetweenInsertionPoints: nil)
        guard tappedCharacterIndex >= 0,
              tappedCharacterIndex < textView.attributedText.length else {
            return nil
        }
        guard let mention = textView.attributedText.attribute(Mention.attributeKey,
                                                              at: tappedCharacterIndex,
                                                              effectiveRange: nil) as? Mention else {
            owsFailDebug("Missing mention.")
            return nil
        }
        return mention
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewBodyText: NSObject, CVComponentView {

        public weak var componentDelegate: CVComponentDelegate?

        fileprivate let hStackView = OWSStackView(name: "bodyText")

        private var _textView: OWSMessageTextView?
        fileprivate var possibleTextView: OWSMessageTextView? { _textView }
        fileprivate var ensuredTextView: OWSMessageTextView {
            if let textView = _textView {
                return textView
            }
            let textView = Self.buildTextView()
            textView.delegate = self
            _textView = textView
            return textView
        }

        private var _label: UILabel?
        fileprivate var possibleLabel: UILabel? { _label }
        fileprivate var ensuredLabel: UILabel {
            if let label = _label {
                return label
            }
            let label = UILabel()
            _label = label
            return label
        }

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hStackView
        }

        required init(componentDelegate: CVComponentDelegate) {
            self.componentDelegate = componentDelegate

            super.init()
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        private static func buildTextView() -> OWSMessageTextView {
            let textView = CVText.buildTextView()

            return textView
        }

        public func reset() {
            if !isDedicatedCellView {
                hStackView.reset()
            }

            _textView?.text = nil
            _label?.text = nil
        }

        // MARK: - UITextViewDelegate

    }
}

// MARK: -

extension CVComponentBodyText.CVComponentViewBodyText: UITextViewDelegate {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return .shared()
    }

    // MARK: -

    public func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        shouldInteractWithUrl(url)
    }

    public func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange) -> Bool {
        shouldInteractWithUrl(url)
    }

    private func shouldInteractWithUrl(_ url: URL) -> Bool {
        guard let componentDelegate = componentDelegate else {
            owsFailDebug("Missing componentDelegate.")
            return true
        }
        guard tsAccountManager.isRegisteredAndReady else {
            return true
        }
        if StickerPackInfo.isStickerPackShare(url) {
            if let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) {
                componentDelegate.cvc_didTapStickerPack(stickerPackInfo)
                return false
            } else {
                owsFailDebug("Invalid URL: \(url)")
                return true
            }
        }
        if GroupManager.isPossibleGroupInviteLink(url) {
            componentDelegate.cvc_didTapGroupInviteLink(url: url)
            return false
        }
        return true
    }
}
