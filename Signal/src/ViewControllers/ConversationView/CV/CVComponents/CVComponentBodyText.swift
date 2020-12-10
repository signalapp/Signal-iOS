//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentBodyText: CVComponentBase, CVComponent {

    struct State: Equatable {
        let bodyText: CVComponentState.BodyText
        let isTruncatedTextVisible: Bool
        let searchText: String?
        let hasTapForMore: Bool

        public var canUseDedicatedCell: Bool {
            if hasTapForMore || searchText != nil {
                return false
            }
            switch bodyText.state {
            case .bodyText:
                return true
            case .oversizeTextDownloading:
                return false
            case .remotelyDeleted:
                return false
            }
        }
    }
    private let bodyTextState: State

    private var bodyText: CVComponentState.BodyText {
        bodyTextState.bodyText
    }
    private var isTruncatedTextVisible: Bool {
        bodyTextState.isTruncatedTextVisible
    }
    private var searchText: String? {
        bodyTextState.searchText
    }
    private var hasTapForMore: Bool {
        bodyTextState.hasTapForMore
    }

    private var displayableBodyText: DisplayableText? {
        switch bodyText.state {
        case .bodyText(let displayableBodyText):
            return displayableBodyText
        case .oversizeTextDownloading:
            return nil
        case .remotelyDeleted:
            return nil
        }
    }

    init(itemModel: CVItemModel, bodyTextState: State) {
        self.bodyTextState = bodyTextState

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewBodyText(componentDelegate: componentDelegate)
    }

    private var isJumbomoji: Bool {
        guard isTextOnlyMessage,
              let displayableBodyText = self.displayableBodyText,
              displayableBodyText.jumbomojiCount > 0 else {
            return false
        }
        return true
    }

    static func buildState(interaction: TSInteraction,
                           bodyText: CVComponentState.BodyText,
                           viewStateSnapshot: CVViewStateSnapshot,
                           hasTapForMore: Bool) -> State {
        let textExpansion = viewStateSnapshot.textExpansion
        let searchText = viewStateSnapshot.searchText

        let isTruncatedTextVisible = textExpansion.isTextExpanded(interactionId: interaction.uniqueId)
        return State(bodyText: bodyText,
                     isTruncatedTextVisible: isTruncatedTextVisible,
                     searchText: searchText,
                     hasTapForMore: hasTapForMore)
    }

    private var textMessageFont: UIFont {
        owsAssertDebug(DisplayableText.kMaxJumbomojiCount == 5)

        if let displayableBodyText = self.displayableBodyText,
           isJumbomoji {
            let basePointSize = UIFont.ows_dynamicTypeBodyClamped.pointSize
            switch displayableBodyText.jumbomojiCount {
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
                owsFailDebug("Unexpected jumbomoji count: \(displayableBodyText.jumbomojiCount)")
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

        switch bodyText.state {
        case .bodyText(let displayableBodyText):
            configureForBodyText(componentView: componentView,
                                 displayableBodyText: displayableBodyText)
        case .oversizeTextDownloading:
            owsAssertDebug(!componentView.isDedicatedCellView)

            configureForOversizeTextDownloading(componentView: componentView)
        case .remotelyDeleted:
            owsAssertDebug(!componentView.isDedicatedCellView)

            configureForRemotelyDeleted(componentView: componentView)
        }
    }

    private func configureForRemotelyDeleted(componentView: CVComponentViewBodyText) {
        // TODO: The border, foreground and background colors are wrong.
        configureForLabel(componentView: componentView,
                          labelConfig: labelConfigForRemotelyDeleted)
    }

    private func configureForOversizeTextDownloading(componentView: CVComponentViewBodyText) {
        configureForLabel(componentView: componentView,
                          labelConfig: labelConfigForOversizeTextDownloading)
    }

    private func configureForLabel(componentView: CVComponentViewBodyText,
                                   labelConfig: CVLabelConfig) {
        let label = componentView.label
        labelConfig.applyForRendering(label: label)
        label.setCompressionResistanceVerticalHigh()

        let hStackView = componentView.hStackView
        hStackView.addArrangedSubview(label)
    }

    public func configureForBodyText(componentView: CVComponentViewBodyText,
                                     displayableBodyText: DisplayableText) {

        let hStackView = componentView.hStackView
        let textView = componentView.textView

        var shouldIgnoreEvents = false
        if let outgoingMessage = interaction as? TSOutgoingMessage {
            // Ignore taps on links in outgoing messages that haven't been sent yet, as
            // this interferes with "tap to retry".
            shouldIgnoreEvents = outgoingMessage.messageState != .sent
        }
        textView.shouldIgnoreEvents = shouldIgnoreEvents

        textView.ensureShouldLinkifyText(displayableBodyText.shouldAllowLinkification)

        let textViewConfig = self.textViewConfig(displayableBodyText: displayableBodyText)
        textViewConfig.applyForRendering(textView: textView)
        let isReusing = componentView.rootView.superview != nil
        if !isReusing {
            hStackView.addArrangedSubview(textView)
        }

        let accessibilityDescription = displayableBodyText.displayAttributedText.string
        textView.accessibilityLabel = accessibilityLabel(description: accessibilityDescription)
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
                             textAlignment: .center)
    }

    private var labelConfigForOversizeTextDownloading: CVLabelConfig {
        let text = NSLocalizedString("MESSAGE_STATUS_DOWNLOADING",
                                     comment: "message status while message is downloading.")
        return CVLabelConfig(text: text,
                             font: textMessageFont.ows_italic,
                             textColor: bodyTextColor,
                             textAlignment: .center)
    }

    private func textViewConfig(displayableBodyText: DisplayableText) -> CVTextViewConfig {

        // Honor dynamic type in the message bodies.
        let linkTextAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.foregroundColor: bodyTextColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let displayableAttributedText: NSAttributedString
        let displayableTextAlignment: NSTextAlignment
        if displayableBodyText.isTextTruncated && isTruncatedTextVisible {
            displayableAttributedText = displayableBodyText.fullAttributedText
            displayableTextAlignment = displayableBodyText.fullTextNaturalAlignment
        } else {
            owsAssertDebug(!isTruncatedTextVisible)
            displayableAttributedText = displayableBodyText.displayAttributedText
            displayableTextAlignment = displayableBodyText.displayTextNaturalAlignment
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = displayableTextAlignment

        let attributedText = displayableAttributedText.mutableCopy() as! NSMutableAttributedString
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

        switch bodyText.state {
        case .bodyText(let displayableBodyText):
            let textViewConfig = self.textViewConfig(displayableBodyText: displayableBodyText)
            let bodyTextSize = CVText.measureTextView(config: textViewConfig, maxWidth: maxWidth)
            return bodyTextSize.ceil
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
        let textView = componentView.textView
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
        fileprivate let textView: OWSMessageTextView
        fileprivate let label = UILabel()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hStackView
        }

        required init(componentDelegate: CVComponentDelegate) {
            self.componentDelegate = componentDelegate
            textView = Self.buildTextView()

            super.init()

            textView.delegate = self
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

            textView.text = nil
            label.text = nil
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
