//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

final public class CVComponentBodyText: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .bodyText }

    struct State: Equatable {
        let bodyText: CVComponentState.BodyText
        let isTextExpanded: Bool
        let searchText: String?
        let revealedSpoilerIds: Set<Int>
        let shouldUseAttributedText: Bool
        let hasPendingMessageRequest: Bool
        fileprivate let items: [CVTextLabel.Item]

        public var canUseDedicatedCell: Bool {
            if searchText != nil {
                return false
            }
            switch bodyText {
            case .bodyText(_, let hasTapForMore):
                return !hasTapForMore
            case .oversizeTextDownloading:
                return false
            case .oversizeTextUndownloadable:
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
    private var revealedSpoilerIds: Set<Int> {
        bodyTextState.revealedSpoilerIds
    }
    private var hasPendingMessageRequest: Bool {
        bodyTextState.hasPendingMessageRequest
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

    private static func shouldIgnoreEvents(interaction: TSInteraction) -> Bool {
        guard let outgoingMessage = interaction as? TSOutgoingMessage else {
            return false
        }
        // Ignore taps on links in outgoing messages that have failed to send, as
        // this interferes with "tap to retry".
        return outgoingMessage.messageState == .failed
    }
    private var shouldIgnoreEvents: Bool { Self.shouldIgnoreEvents(interaction: interaction) }

    // TODO:
    private static let shouldDetectDates = false

    private static func buildDataDetector(shouldAllowLinkification: Bool) -> NSDataDetector? {
        var checkingTypes = NSTextCheckingResult.CheckingType()
        if shouldAllowLinkification {
            checkingTypes.insert(.link)
        }
        checkingTypes.insert(.address)
        checkingTypes.insert(.phoneNumber)
        if shouldDetectDates {
            checkingTypes.insert(.date)
        }

        do {
            return try NSDataDetector(types: checkingTypes.rawValue)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private static var dataDetectorWithLinks: NSDataDetector? = {
        buildDataDetector(shouldAllowLinkification: true)
    }()

    private static var dataDetectorWithoutLinks: NSDataDetector? = {
        buildDataDetector(shouldAllowLinkification: false)
    }()

    // DataDetectors are expensive to build, so we reuse them.
    private static func dataDetector(shouldAllowLinkification: Bool) -> NSDataDetector? {
        shouldAllowLinkification ? dataDetectorWithLinks : dataDetectorWithoutLinks
    }

    private static let unfairLock = UnfairLock()

    public static func detectItems(
        text: DisplayableText,
        hasPendingMessageRequest: Bool,
        shouldAllowLinkification: Bool,
        textWasTruncated: Bool,
        revealedSpoilerIds: Set<StyleIdType>,
        interactionUniqueId: String,
        interactionIdentifier: InteractionSnapshotIdentifier
    ) -> [CVTextLabel.Item] {

        // Use a lock to ensure that measurement on and off the main thread
        // don't conflict.
        unfairLock.withLock {
            guard !hasPendingMessageRequest else {
                // Do not linkify if there is a pending message request.
                return []
            }

            let dataDetector = buildDataDetector(shouldAllowLinkification: shouldAllowLinkification)

            func detectItems(plaintext: String) -> [CVTextLabel.Item] {
                return TextCheckingDataItem.detectedItems(in: plaintext, using: dataDetector).compactMap {
                    if textWasTruncated {
                        if NSMaxRange($0.range) == NSMaxRange(plaintext.entireRange) {
                            // This implies that the data detector *included* our "…" suffix.
                            // We don't expect this to happen, but if it does it's certainly not intended!
                            return nil
                        }
                        if plaintext.substring(afterRange: $0.range) == DisplayableText.truncatedTextSuffix {
                            // More likely the item right before the "…" was detected.
                            // Conservatively assume that the item was truncated.
                            return nil
                        }
                    }
                    return .dataItem(dataItem: $0)
                }
            }

            let items: [CVTextLabel.Item]

            switch text.textValue(isTextExpanded: !textWasTruncated) {
            case .attributedText(let attributedText):
                items = detectItems(plaintext: attributedText.string)
            case .text(let text):
                items = detectItems(plaintext: text)
            case .messageBody(let messageBody):
                items = messageBody
                    .tappableItems(
                        revealedSpoilerIds: revealedSpoilerIds,
                        dataDetector: dataDetector
                    )
                    .compactMap {
                        switch $0 {
                        case .unrevealedSpoiler(let unrevealedSpoilerItem):
                            return .unrevealedSpoiler(CVTextLabel.UnrevealedSpoilerItem(
                                spoilerId: unrevealedSpoilerItem.id,
                                interactionUniqueId: interactionUniqueId,
                                interactionIdentifier: interactionIdentifier,
                                range: unrevealedSpoilerItem.range
                            ))
                        case .mention(let mentionItem):
                            return .mention(mentionItem: CVTextLabel.MentionItem(
                                mentionAci: mentionItem.mentionAci,
                                range: mentionItem.range
                            ))
                        case .data(let dataItem):
                            // TODO: omit data items ending before elipsis down in tappableItems
                            return .dataItem(dataItem: dataItem)
                        }
                    }
            }

            return items
        }
    }

    static func buildState(interaction: TSInteraction,
                           bodyText: CVComponentState.BodyText,
                           viewStateSnapshot: CVViewStateSnapshot,
                           hasPendingMessageRequest: Bool) -> State {
        let textExpansion = viewStateSnapshot.textExpansion
        let searchText = viewStateSnapshot.searchText
        let isTextExpanded = textExpansion.isTextExpanded(interactionId: interaction.uniqueId)
        let revealedSpoilerIds = viewStateSnapshot.spoilerReveal[.fromInteraction(interaction)] ?? Set()

        let items: [CVTextLabel.Item]
        var shouldUseAttributedText = false
        if let displayableText = bodyText.displayableText {

            let shouldAllowLinkification = displayableText.shouldAllowLinkification
            let textWasTruncated = !isTextExpanded && displayableText.isTextTruncated

            items = detectItems(
                text: displayableText,
                hasPendingMessageRequest: hasPendingMessageRequest,
                shouldAllowLinkification: shouldAllowLinkification,
                textWasTruncated: textWasTruncated,
                revealedSpoilerIds: revealedSpoilerIds,
                interactionUniqueId: interaction.uniqueId,
                interactionIdentifier: .fromInteraction(interaction)
            )

            switch displayableText.textValue(isTextExpanded: isTextExpanded) {
            case .text:
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
                    shouldUseAttributedText = !items.isEmpty
                }
            case .attributedText, .messageBody:
                shouldUseAttributedText = true
            }
        } else {
            items = []
        }

        return State(bodyText: bodyText,
                     isTextExpanded: isTextExpanded,
                     searchText: searchText,
                     revealedSpoilerIds: revealedSpoilerIds,
                     shouldUseAttributedText: shouldUseAttributedText,
                     hasPendingMessageRequest: hasPendingMessageRequest,
                     items: items)
    }

    static func buildComponentState(
        message: TSMessage,
        viewStateSnapshot: CVViewStateSnapshot,
        transaction: DBReadTransaction
    ) throws -> CVComponentState.BodyText? {

        func build(displayableText: DisplayableText) -> CVComponentState.BodyText? {
            guard !displayableText.fullTextValue.isEmpty else {
                return nil
            }
            let hasTapForMore: Bool = {
                guard displayableText.isTextTruncated else {
                    return false
                }
                let isTruncatedTextVisible = viewStateSnapshot.textExpansion.isTextExpanded(
                    interactionId: message.uniqueId
                )
                return !isTruncatedTextVisible
            }()
            return .bodyText(displayableText: displayableText, hasTapForMore: hasTapForMore)
        }

        func bodyDisplayableText() -> DisplayableText? {
            if let body = message.body, !body.isEmpty {
                return CVComponentState.displayableBodyText(
                    text: body,
                    ranges: message.bodyRanges,
                    interaction: message,
                    transaction: transaction
                )
            } else {
                return nil
            }
        }

        // TODO: We might want to treat text that is completely stripped
        // as not present.
        if let oversizeTextAttachment = message.oversizeTextAttachment(transaction: transaction) {
            if let oversizeTextAttachmentStream = oversizeTextAttachment.asStream() {
                let displayableText = CVComponentState.displayableBodyText(
                    oversizeTextAttachment: oversizeTextAttachmentStream,
                    ranges: message.bodyRanges,
                    interaction: message,
                    transaction: transaction
                )
                return build(displayableText: displayableText)
            } else if oversizeTextAttachment.asAnyPointer() != nil {
                return .oversizeTextDownloading
            } else {
                if let displayableText = bodyDisplayableText() {
                    return .oversizeTextUndownloadable(truncatedBody: displayableText)
                } else {
                    return nil
                }
            }
        } else if let displayableText = bodyDisplayableText() {
            return build(displayableText: displayableText)
        } else {
            // No body text.
            return nil
        }
    }

    public var textMessageFont: UIFont {
        owsAssertDebug(DisplayableText.kMaxJumbomojiCount == 5)

        if let jumbomojiCount = bodyText.jumbomojiCount {
            let basePointSize = UIFont.dynamicTypeBodyClamped.pointSize
            switch jumbomojiCount {
            case 0:
                break
            case 1:
                return UIFont.regularFont(ofSize: basePointSize * 3.5)
            case 2:
                return UIFont.regularFont(ofSize: basePointSize * 3.0)
            case 3:
                return UIFont.regularFont(ofSize: basePointSize * 2.75)
            case 4:
                return UIFont.regularFont(ofSize: basePointSize * 2.5)
            case 5:
                return UIFont.regularFont(ofSize: basePointSize * 2.25)
            default:
                owsFailDebug("Unexpected jumbomoji count: \(jumbomojiCount)")
            }
        }

        return UIFont.dynamicTypeBody
    }

    private var bodyTextColor: UIColor {
        guard let message = interaction as? TSMessage else {
            return .black
        }
        return conversationStyle.bubbleTextColor(message: message)
    }

    private var textSelectionStyling: [NSAttributedString.Key: Any] {
        var foregroundColor: UIColor = .black
        if let message = interaction as? TSMessage {
            foregroundColor = conversationStyle.bubbleSecondaryTextColor(isIncoming: message.isIncoming)
        }

        return [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: foregroundColor,
            .foregroundColor: foregroundColor
        ]
    }

    public func bodyTextLabelConfig(textViewConfig: CVTextViewConfig) -> CVTextLabel.Config {
        CVTextLabel.Config(
            text: textViewConfig.text,
            displayConfig: textViewConfig.displayConfiguration,
            font: textViewConfig.font,
            textColor: textViewConfig.textColor,
            selectionStyling: textSelectionStyling,
            textAlignment: textViewConfig.textAlignment ?? .natural,
            lineBreakMode: .byWordWrapping,
            numberOfLines: 0,
            cacheKey: textViewConfig.cacheKey,
            items: bodyTextState.items,
            linkifyStyle: textViewConfig.linkifyStyle
        )
    }

    public func bodyTextLabelConfig(labelConfig: CVLabelConfig) -> CVTextLabel.Config {
        // CVTextLabel requires that attributedString has
        // default attributes applied to the entire string's range.
        let textAlignment: NSTextAlignment = labelConfig.textAlignment ?? .natural
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment

        return CVTextLabel.Config(
            text: labelConfig.text,
            displayConfig: labelConfig.displayConfig,
            font: labelConfig.font,
            textColor: labelConfig.textColor,
            selectionStyling: textSelectionStyling,
            textAlignment: textAlignment,
            lineBreakMode: .byWordWrapping,
            numberOfLines: 0,
            cacheKey: labelConfig.cacheKey,
            items: bodyTextState.items,
            linkifyStyle: linkifyStyle
        )
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        AssertIsOnMainThread()
        guard let componentView = componentView as? CVComponentViewBodyText else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let bodyTextLabelConfig = buildBodyTextLabelConfig()
        configureForBodyTextLabel(
            componentView: componentView,
            bodyTextLabelConfig: bodyTextLabelConfig,
            cellMeasurement: cellMeasurement,
            spoilerAnimationManager: componentDelegate.spoilerState.animationManager
        )
    }

    private func configureForBodyTextLabel(
        componentView: CVComponentViewBodyText,
        bodyTextLabelConfig: CVTextLabel.Config,
        cellMeasurement: CVCellMeasurement,
        spoilerAnimationManager: SpoilerAnimationManager
    ) {
        AssertIsOnMainThread()

        let bodyTextLabel = componentView.bodyTextLabel
        bodyTextLabel.configureForRendering(config: bodyTextLabelConfig, spoilerAnimationManager: spoilerAnimationManager)

        if bodyTextLabel.view.superview == nil {
            let stackView = componentView.stackView
            stackView.reset()
            stackView.configure(config: stackViewConfig,
                                cellMeasurement: cellMeasurement,
                                measurementKey: Self.measurementKey_stackView,
                                subviews: [ bodyTextLabel.view ])
        }
    }

    public func buildBodyTextLabelConfig() -> CVTextLabel.Config {
        switch bodyText {
        case .bodyText(let displayableText, _), .oversizeTextUndownloadable(let displayableText):
            return bodyTextLabelConfig(textViewConfig: textConfig(displayableText: displayableText))
        case .oversizeTextDownloading:
            return bodyTextLabelConfig(labelConfig: labelConfigForOversizeTextDownloading)
        case .remotelyDeleted:
            return bodyTextLabelConfig(labelConfig: labelConfigForRemotelyDeleted)
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
                        ? OWSLocalizedString("THIS_MESSAGE_WAS_DELETED", comment: "text indicating the message was remotely deleted")
                        : OWSLocalizedString("YOU_DELETED_THIS_MESSAGE", comment: "text indicating the message was remotely deleted by you"))
        return CVLabelConfig(
            text: .text(text),
            displayConfig: .forUnstyledText(font: textMessageFont.italic(), textColor: bodyTextColor),
            font: textMessageFont.italic(),
            textColor: bodyTextColor,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center
        )
    }

    private var labelConfigForOversizeTextDownloading: CVLabelConfig {
        let text = OWSLocalizedString("MESSAGE_STATUS_DOWNLOADING",
                                     comment: "message status while message is downloading.")
        return CVLabelConfig(
            text: .text(text),
            displayConfig: .forUnstyledText(font: textMessageFont.italic(), textColor: bodyTextColor),
            font: textMessageFont.italic(),
            textColor: bodyTextColor,
            numberOfLines: 0,
            lineBreakMode: .byWordWrapping,
            textAlignment: .center
        )
    }

    private typealias TextConfig = CVTextViewConfig

    private func textConfig(displayableText: DisplayableText) -> TextConfig {
        return self.textViewConfig(displayableText: displayableText)
    }

    public static func configureTextView(_ textView: UITextView,
                                         interaction: TSInteraction,
                                         displayableText: DisplayableText) {
        let dataDetectorTypes: UIDataDetectorTypes = {
            // If we're link-ifying with NSDataDetector, UITextView doesn't need to do data detection.
            guard !shouldIgnoreEvents(interaction: interaction),
                  displayableText.shouldAllowLinkification else {
                return []
            }
            return [.link, .address, .calendarEvent, .phoneNumber]
        }()
        if textView.dataDetectorTypes != dataDetectorTypes {
            // Setting dataDetectorTypes is expensive, so we only
            // update the property if the value has changed.
            textView.dataDetectorTypes = dataDetectorTypes
        }
    }

    private var linkTextAttributes: [NSAttributedString.Key: Any] {
        return [
            NSAttributedString.Key.foregroundColor: bodyTextColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private var linkifyStyle: CVTextLabel.LinkifyStyle { .underlined(bodyTextColor: bodyTextColor) }

    private func textViewConfig(displayableText: DisplayableText) -> CVTextViewConfig {
        let textAlignment = (isTextExpanded
                                ? displayableText.fullTextNaturalAlignment
                                : displayableText.displayTextNaturalAlignment)

        let text = displayableText.textValue(isTextExpanded: isTextExpanded)
        let linkItems = bodyTextState.items

        var matchedSearchRanges = [NSRange]()
        if let searchText = searchText,
           searchText.count >= ConversationSearchController.kMinimumSearchTextLength {
            let searchableText = FullTextSearchIndexer.normalizeText(searchText)
            let pattern = NSRegularExpression.escapedPattern(for: searchableText)
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

                func runRegex(_ string: String) {
                    for match in regex.matches(in: string, options: [.withoutAnchoringBounds], range: string.entireRange) {
                        owsAssertDebug(match.range.length >= ConversationSearchController.kMinimumSearchTextLength)
                        matchedSearchRanges.append(match.range)
                    }
                }

                switch text {
                case .text(let text):
                    runRegex(text)
                case .attributedText(let attributedText):
                    runRegex(attributedText.string)
                case .messageBody(let messageBody):
                    matchedSearchRanges = messageBody.matches(for: regex)
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }

        let displayConfiguration = HydratedMessageBody.DisplayConfiguration.messageBubble(
            isIncoming: isIncoming,
            revealedSpoilerIds: revealedSpoilerIds,
            searchRanges: .matchedRanges(matchedSearchRanges)
        )

        var extraCacheKeyFactors = [String]()
        if hasPendingMessageRequest {
            extraCacheKeyFactors.append("hasPendingMessageRequest")
        }
        extraCacheKeyFactors.append("items: \(!bodyTextState.items.isEmpty)")

        return CVTextViewConfig(
            text: text,
            font: textMessageFont,
            textColor: bodyTextColor,
            textAlignment: textAlignment,
            displayConfiguration: displayConfiguration,
            linkTextAttributes: linkTextAttributes,
            linkifyStyle: linkifyStyle,
            linkItems: linkItems,
            matchedSearchRanges: matchedSearchRanges,
            extraCacheKeyFactors: extraCacheKeyFactors
        )
    }

    private static let measurementKey_stackView = "CVComponentBodyText.measurementKey_stackView"
    private static let measurementKey_textMeasurement = "CVComponentBodyText.measurementKey_textMeasurement"
    private static let measurementKey_maxWidth = "CVComponentBodyText.measurementKey_maxWidth"

    // Extract the max width used for measuring for this component.
    public static func bodyTextMaxWidth(measurementBuilder: CVCellMeasurement.Builder) -> CGFloat? {
        measurementBuilder.getValue(key: measurementKey_maxWidth)
    }

    // Extract the overall measurement for this component.
    public static func bodyTextMeasurement(measurementBuilder: CVCellMeasurement.Builder) -> CVTextLabel.Measurement? {
        measurementBuilder.getObject(key: measurementKey_textMeasurement) as? CVTextLabel.Measurement
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        let maxWidth = max(maxWidth, 0)

        let bodyTextLabelConfig = buildBodyTextLabelConfig()

        let textMeasurement = CVText.measureBodyTextLabel(config: bodyTextLabelConfig, maxWidth: maxWidth)
        measurementBuilder.setObject(key: Self.measurementKey_textMeasurement, value: textMeasurement)
        measurementBuilder.setValue(key: Self.measurementKey_maxWidth, value: maxWidth)
        let textSize = textMeasurement.size.ceil
        let textInfo = textSize.asManualSubviewInfo
        let stackMeasurement = ManualStackView.measure(config: stackViewConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: [ textInfo ],
                                                       maxWidth: maxWidth)
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UIGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {
        guard let componentView = componentView as? CVComponentViewBodyText else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        guard !shouldIgnoreEvents else {
            return false
        }

        let bodyTextLabel = componentView.bodyTextLabel
        if let item = bodyTextLabel.itemForGesture(sender: sender) {
            bodyTextLabel.animate(selectedItem: item)
            componentDelegate.didTapBodyTextItem(item)
            return true
        }
        switch bodyText {
        case .bodyText(_, let hasTapForMore) where hasTapForMore:
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            componentDelegate.didTapTruncatedTextMessage(itemViewModel)
            return true
        case .oversizeTextUndownloadable:
            componentDelegate.didTapUndownloadableOversizeText()
            return true
        default:
            break
        }

        return false
    }

    public override func findLongPressHandler(sender: UIGestureRecognizer,
                                              componentDelegate: CVComponentDelegate,
                                              componentView: CVComponentView,
                                              renderItem: CVRenderItem) -> CVLongPressHandler? {

        guard let componentView = componentView as? CVComponentViewBodyText else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }

        guard !shouldIgnoreEvents else {
            return nil
        }

        let bodyTextLabel = componentView.bodyTextLabel
        guard let item = bodyTextLabel.itemForGesture(sender: sender) else {
            return nil
        }
        bodyTextLabel.animate(selectedItem: item)
        return CVLongPressHandler(delegate: componentDelegate,
                                  renderItem: renderItem,
                                  gestureLocation: .bodyText(item: item))
    }

    // MARK: -

    fileprivate class BodyTextRootView: ManualStackView {}

    public static func findBodyTextRootView(_ view: UIView) -> UIView? {
        if view is BodyTextRootView {
            return view
        }
        for subview in view.subviews {
            if let rootView = findBodyTextRootView(subview) {
                return rootView
            }
        }
        return nil
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewBodyText: NSObject, CVComponentView {

        public weak var componentDelegate: CVComponentDelegate?

        fileprivate let stackView = BodyTextRootView(name: "bodyText")

        public let bodyTextLabel = CVTextLabel()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        init(componentDelegate: CVComponentDelegate) {
            self.componentDelegate = componentDelegate

            super.init()
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {
            bodyTextLabel.setIsCellVisible(isCellVisible)
        }

        public func reset() {
            if !isDedicatedCellView {
                stackView.reset()
            }

            bodyTextLabel.reset()
        }
    }
}

// MARK: -

extension CVComponentBodyText: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        switch bodyText {
        case .bodyText(let displayableText, _), .oversizeTextUndownloadable(let displayableText):
            // NOTE: we use the full text.
            return displayableText.fullTextValue.accessibilityDescription
        case .oversizeTextDownloading:
            return labelConfigForOversizeTextDownloading.text.accessibilityDescription
        case .remotelyDeleted:
            return labelConfigForRemotelyDeleted.text.accessibilityDescription
        }
    }
}
