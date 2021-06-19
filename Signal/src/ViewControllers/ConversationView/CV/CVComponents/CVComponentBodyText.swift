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
        let hasPendingMessageRequest: Bool
        fileprivate let items: [CVBodyTextLabel.Item]

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

    private var isJumbomoji: Bool {
        componentState.isJumbomojiMessage
    }

    private static func shouldIgnoreEvents(interaction: TSInteraction) -> Bool {
        guard let outgoingMessage = interaction as? TSOutgoingMessage else {
            return false
        }
        // Ignore taps on links in outgoing messages that haven't been sent yet, as
        // this interferes with "tap to retry".
        return outgoingMessage.messageState != .sent
    }
    private var shouldIgnoreEvents: Bool { Self.shouldIgnoreEvents(interaction: interaction) }

    private static func buildDataDetector(shouldAllowLinkification: Bool) -> NSDataDetector? {
        var checkingTypes = NSTextCheckingResult.CheckingType()
        if shouldAllowLinkification {
            checkingTypes.insert(.link)
        }
        checkingTypes.insert(.address)
        checkingTypes.insert(.phoneNumber)
        // TODO:
        let shouldDetectDates = false
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

    private static func detectItems(text: String,
                                    attributedString: NSAttributedString?,
                                    hasPendingMessageRequest: Bool,
                                    shouldAllowLinkification: Bool) -> [CVBodyTextLabel.Item] {

        // Use a lock to ensure that measurement on and off the main thread
        // don't conflict.
        unfairLock.withLock {
            guard !hasPendingMessageRequest else {
                // Do not linkify if there is a pending message request.
                return []
            }

            var items = [CVBodyTextLabel.Item]()
            // Detect and discard overlapping items, preferring mentions to data items.
            func hasItemOverlap(_ newItem: CVBodyTextLabel.Item) -> Bool {
                for oldItem in items {
                    if let overlap = oldItem.range.intersection(newItem.range),
                       overlap.length > 0 {
                        return true
                    }
                }
                return false
            }

            // Add mentions.
            if let attributedString = attributedString {
                attributedString.enumerateMentions { mention, range, _ in
                    guard let mention = mention else { return }
                    let mentionItem = CVBodyTextLabel.MentionItem(mention: mention, range: range)
                    let item: CVBodyTextLabel.Item = .mention(mentionItem: mentionItem)
                    guard !hasItemOverlap(item) else {
                        owsFailDebug("Item overlap.")
                        return
                    }
                    items.append(item)
                }
            }

            // NSDataDetector and UIDataDetector behavior should be aligned.
            //
            // TODO: We might want to move this detection logic into
            // DisplayableText so that we can leverage caching.
            guard let detector = dataDetector(shouldAllowLinkification: shouldAllowLinkification) else {
                // If the data detectors can't be built, default to using attributed text.
                owsFailDebug("Could not build dataDetector.")
                return []
            }
            for match in detector.matches(in: text, options: [], range: text.entireRange) {
                guard let snippet = (text as NSString).substring(with: match.range).strippedOrNil else {
                    owsFailDebug("Invalid snippet.")
                    continue
                }

                let matchUrl = match.url

                let dataType: CVBodyTextLabel.DataItem.DataType
                var customUrl: URL?
                let resultType: NSTextCheckingResult.CheckingType = match.resultType
                if resultType.contains(.orthography) {
                    Logger.verbose("orthography")
                    continue
                } else if resultType.contains(.spelling) {
                    Logger.verbose("spelling")
                    continue
                } else if resultType.contains(.grammar) {
                    Logger.verbose("grammar")
                    continue
                } else if resultType.contains(.date) {
                    dataType = .date

                    guard matchUrl == nil else {
                        // Skip building customUrl; we already have a URL.
                        break
                    }

                    // NSTextCheckingResult.date is in GMT.
                    guard let gmtDate = match.date else {
                        owsFailDebug("Missing date.")
                        continue
                    }
                    // "calshow:" URLs expect GMT.
                    let timeInterval = gmtDate.timeIntervalSinceReferenceDate
                    // I'm not sure if there's official docs around these links.
                    guard let calendarUrl = URL(string: "calshow:\(timeInterval)") else {
                        owsFailDebug("Couldn't build calendarUrl.")
                        continue
                    }
                    customUrl = calendarUrl
                } else if resultType.contains(.address) {
                    Logger.verbose("address")

                    dataType = .address

                    guard matchUrl == nil else {
                        // Skip building customUrl; we already have a URL.
                        break
                    }

                    // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
                    guard let urlEncodedAddress = snippet.encodeURIComponent else {
                        owsFailDebug("Could not URL encode address.")
                        continue
                    }
                    let urlString = "https://maps.apple.com/?q=" + urlEncodedAddress
                    guard let mapUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build mapUrl.")
                        continue
                    }
                    customUrl = mapUrl
                } else if resultType.contains(.link) {
                    if let url = matchUrl,
                       url.absoluteString.lowercased().hasPrefix("mailto:"),
                       !snippet.lowercased().hasPrefix("mailto:") {
                        Logger.verbose("emailAddress")
                        dataType = .emailAddress
                    } else {
                        Logger.verbose("link")
                        dataType = .link
                    }
                } else if resultType.contains(.quote) {
                    Logger.verbose("quote")
                    continue
                } else if resultType.contains(.dash) {
                    Logger.verbose("dash")
                    continue
                } else if resultType.contains(.replacement) {
                    Logger.verbose("replacement")
                    continue
                } else if resultType.contains(.correction) {
                    Logger.verbose("correction")
                    continue
                } else if resultType.contains(.regularExpression) {
                    Logger.verbose("regularExpression")
                    continue
                } else if resultType.contains(.phoneNumber) {
                    Logger.verbose("phoneNumber")

                    dataType = .phoneNumber

                    guard matchUrl == nil else {
                        // Skip building customUrl; we already have a URL.
                        break
                    }

                    // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html
                    let characterSet = CharacterSet(charactersIn: "+0123456789")
                    guard let phoneNumber = snippet.components(separatedBy: characterSet.inverted).joined().nilIfEmpty else {
                        owsFailDebug("Invalid phoneNumber.")
                        continue
                    }
                    let urlString = "tel:" + phoneNumber
                    guard let phoneNumberUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build phoneNumberUrl.")
                        continue
                    }
                    customUrl = phoneNumberUrl
                } else if resultType.contains(.transitInformation) {
                    Logger.verbose("transitInformation")

                    dataType = .transitInformation

                    guard matchUrl == nil else {
                        // Skip building customUrl; we already have a URL.
                        break
                    }

                    guard let components = match.components,
                          let airline = components[.airline]?.nilIfEmpty,
                          let flight = components[.flight]?.nilIfEmpty else {
                        Logger.warn("Missing components.")
                        continue
                    }
                    let query = airline + " " + flight
                    guard let urlEncodedQuery = query.encodeURIComponent else {
                        owsFailDebug("Could not URL encode query.")
                        continue
                    }
                    let urlString = "https://www.google.com/?q=" + urlEncodedQuery
                    guard let transitUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build transitUrl.")
                        continue
                    }
                    customUrl = transitUrl
                } else {
                    let snippet = (text as NSString).substring(with: match.range)
                    Logger.verbose("snippet: '\(snippet)'")
                    owsFailDebug("Unknown link type: \(resultType.rawValue)")
                    continue
                }

                guard let url = customUrl ?? matchUrl else {
                    owsFailDebug("Missing url: \(dataType).")
                    continue
                }

                let dataItem = CVBodyTextLabel.DataItem(dataType: dataType,
                                                        range: match.range,
                                                        snippet: snippet,
                                                        url: url)
                let item: CVBodyTextLabel.Item = .dataItem(dataItem: dataItem)
                guard !hasItemOverlap(item) else {
                    owsFailDebug("Item overlap.")
                    continue
                }
                items.append(item)
            }
            return items
        }
    }

    static func buildState(interaction: TSInteraction,
                           bodyText: CVComponentState.BodyText,
                           viewStateSnapshot: CVViewStateSnapshot,
                           hasTapForMore: Bool,
                           hasPendingMessageRequest: Bool) -> State {
        let textExpansion = viewStateSnapshot.textExpansion
        let searchText = viewStateSnapshot.searchText
        let isTextExpanded = textExpansion.isTextExpanded(interactionId: interaction.uniqueId)

        let items: [CVBodyTextLabel.Item]
        var shouldUseAttributedText = false
        if let displayableText = bodyText.displayableText,
           let textValue = bodyText.textValue(isTextExpanded: isTextExpanded) {

            let shouldAllowLinkification = displayableText.shouldAllowLinkification

            switch textValue {
            case .text(let text):
                items = detectItems(text: text,
                                    attributedString: nil,
                                    hasPendingMessageRequest: hasPendingMessageRequest,
                                    shouldAllowLinkification: shouldAllowLinkification)

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
            case .attributedText(let attributedText):
                items = detectItems(text: attributedText.string,
                                    attributedString: attributedText,
                                    hasPendingMessageRequest: hasPendingMessageRequest,
                                    shouldAllowLinkification: shouldAllowLinkification)
                shouldUseAttributedText = true
            }
        } else {
            items = []
        }

        return State(bodyText: bodyText,
                     isTextExpanded: isTextExpanded,
                     searchText: searchText,
                     hasTapForMore: hasTapForMore,
                     shouldUseAttributedText: shouldUseAttributedText,
                     hasPendingMessageRequest: hasPendingMessageRequest,
                     items: items)
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

    private var textSelectionColor: UIColor {
        guard let message = interaction as? TSMessage else {
            return .black
        }
        return conversationStyle.bubbleSecondaryTextColor(isIncoming: message.isIncoming)
    }

    public func bodyTextLabelConfig(textViewConfig: CVTextViewConfig) -> CVBodyTextLabel.Config {
        let selectionColor = textSelectionColor
        return CVBodyTextLabel.Config(attributedString: textViewConfig.text.attributedString,
                                      font: textViewConfig.font,
                                      textColor: textViewConfig.textColor,
                                      selectionColor: selectionColor,
                                      textAlignment: textViewConfig.textAlignment ?? .natural,
                                      lineBreakMode: .byWordWrapping,
                                      numberOfLines: 0,
                                      cacheKey: textViewConfig.cacheKey,
                                      items: bodyTextState.items)
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewBodyText else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        switch bodyText {
        case .bodyText(let displayableText):
            configureForBodyText(componentView: componentView,
                                 displayableText: displayableText,
                                 cellMeasurement: cellMeasurement)
        case .oversizeTextDownloading:
            owsAssertDebug(!componentView.isDedicatedCellView)

            configureForOversizeTextDownloading(componentView: componentView,
                                                cellMeasurement: cellMeasurement)
        case .remotelyDeleted:
            owsAssertDebug(!componentView.isDedicatedCellView)

            configureForRemotelyDeleted(componentView: componentView,
                                        cellMeasurement: cellMeasurement)
        }
    }

    private func configureForRemotelyDeleted(componentView: CVComponentViewBodyText,
                                             cellMeasurement: CVCellMeasurement) {
        _ = configureForLabel(componentView: componentView,
                              labelConfig: labelConfigForRemotelyDeleted,
                              cellMeasurement: cellMeasurement)
    }

    private func configureForOversizeTextDownloading(componentView: CVComponentViewBodyText,
                                                     cellMeasurement: CVCellMeasurement) {
        _ = configureForLabel(componentView: componentView,
                              labelConfig: labelConfigForOversizeTextDownloading,
                              cellMeasurement: cellMeasurement)
    }

    private func configureForLabel(componentView: CVComponentViewBodyText,
                                   labelConfig: CVLabelConfig,
                                   cellMeasurement: CVCellMeasurement) -> UILabel {
        let label = componentView.ensuredLabel
        labelConfig.applyForRendering(label: label)

        if label.superview == nil {
            let stackView = componentView.stackView
            stackView.reset()

            stackView.configure(config: stackViewConfig,
                                cellMeasurement: cellMeasurement,
                                measurementKey: Self.measurementKey_stackView,
                                subviews: [ label ])
        }

        return label
    }

    public func configureForBodyText(componentView: CVComponentViewBodyText,
                                     displayableText: DisplayableText,
                                     cellMeasurement: CVCellMeasurement) {

        switch textConfig(displayableText: displayableText) {
        case .labelConfig(let labelConfig):
            _ = configureForLabel(componentView: componentView,
                                  labelConfig: labelConfig,
                                  cellMeasurement: cellMeasurement)
        case .textViewConfig(let textViewConfig):
            let bodyTextLabel = componentView.ensuredBodyTextLabel
            let bodyTextLabelConfig = self.bodyTextLabelConfig(textViewConfig: textViewConfig)
            bodyTextLabel.configureForRendering(config: bodyTextLabelConfig)

            if bodyTextLabel.view.superview == nil {
                let stackView = componentView.stackView
                stackView.reset()
                stackView.configure(config: stackViewConfig,
                                    cellMeasurement: cellMeasurement,
                                    measurementKey: Self.measurementKey_stackView,
                                    subviews: [ bodyTextLabel.view ])
            }
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

    public enum LinkifyStyle {
        case linkAttribute
        case underlined(bodyTextColor: UIColor)
    }

    private func linkifyData(attributedText: NSMutableAttributedString) {
        Self.linkifyData(attributedText: attributedText,
                         linkifyStyle: .underlined(bodyTextColor: bodyTextColor),
                         items: bodyTextState.items)
    }

    public static func linkifyData(attributedText: NSMutableAttributedString,
                                   linkifyStyle: LinkifyStyle,
                                   hasPendingMessageRequest: Bool,
                                   shouldAllowLinkification: Bool) {

        let items = detectItems(text: attributedText.string,
                                attributedString: attributedText,
                                hasPendingMessageRequest: hasPendingMessageRequest,
                                shouldAllowLinkification: shouldAllowLinkification)
        Self.linkifyData(attributedText: attributedText,
                         linkifyStyle: linkifyStyle,
                         items: items)
    }

    private static func linkifyData(attributedText: NSMutableAttributedString,
                                    linkifyStyle: LinkifyStyle,
                                    items: [CVBodyTextLabel.Item]) {

        // Sort so that we can detect overlap.
        let items = items.sorted { (left, right) in
            left.range.location < right.range.location
        }

        var lastIndex: Int = 0
        for item in items {
            let range = item.range

            guard range.location >= lastIndex else {
                owsFailDebug("Overlapping ranges.")
                continue
            }
            switch item {
            case .mention:
                // Do nothing; mentions are already styled.
                continue
            case .dataItem(let dataItem):
                guard let link = dataItem.url.absoluteString.nilIfEmpty else {
                    owsFailDebug("Could not build data link.")
                    continue
                }

                switch linkifyStyle {
                case .linkAttribute:
                    attributedText.addAttribute(.link, value: link, range: range)
                case .underlined(let bodyTextColor):
                    attributedText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    attributedText.addAttribute(.underlineColor, value: bodyTextColor, range: range)
                }

                lastIndex = max(lastIndex, range.location + range.length)
            }
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
        linkifyData(attributedText: attributedText)

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

    private static let measurementKey_stackView = "CVComponentBodyText.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let textSize: CGSize = {
            switch bodyText {
            case .bodyText(let displayableText):
                switch textConfig(displayableText: displayableText) {
                case .labelConfig(let labelConfig):
                    return CVText.measureLabel(config: labelConfig, maxWidth: maxWidth).ceil
                case .textViewConfig(let textViewConfig):
                    let bodyTextLabelConfig = self.bodyTextLabelConfig(textViewConfig: textViewConfig)
                    return CVText.measureBodyTextLabel(config: bodyTextLabelConfig, maxWidth: maxWidth).ceil
                }
            case .oversizeTextDownloading:
                return CVText.measureLabel(config: labelConfigForOversizeTextDownloading, maxWidth: maxWidth).ceil
            case .remotelyDeleted:
                return CVText.measureLabel(config: labelConfigForRemotelyDeleted, maxWidth: maxWidth).ceil
            }
        }()
        let textInfo = textSize.asManualSubviewInfo
        let stackMeasurement = ManualStackView.measure(config: stackViewConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: [ textInfo ],
                                                       maxWidth: maxWidth)
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
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

        if let bodyTextLabel = componentView.possibleBodyTextLabel,
           let item = bodyTextLabel.itemForGesture(sender: sender) {
            bodyTextLabel.animate(selectedItem: item)
            componentDelegate.cvc_didTapBodyTextItem(.init(item: item))
            return true
        }

        if hasTapForMore {
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            componentDelegate.cvc_didTapTruncatedTextMessage(itemViewModel)
            return true
        }

        return false
    }

    public override func findLongPressHandler(sender: UILongPressGestureRecognizer,
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

        guard let bodyTextLabel = componentView.possibleBodyTextLabel,
              let item = bodyTextLabel.itemForGesture(sender: sender) else {
            return nil
        }
        bodyTextLabel.animate(selectedItem: item)
        return CVLongPressHandler(delegate: componentDelegate,
                                  renderItem: renderItem,
                                  gestureLocation: .bodyText(item: item))
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewBodyText: NSObject, CVComponentView {

        public weak var componentDelegate: CVComponentDelegate?

        fileprivate let stackView = ManualStackView(name: "bodyText")

        private var _bodyTextLabel: CVBodyTextLabel?
        fileprivate var possibleBodyTextLabel: CVBodyTextLabel? { _bodyTextLabel }
        fileprivate var ensuredBodyTextLabel: CVBodyTextLabel {
            if let bodyTextLabel = _bodyTextLabel {
                return bodyTextLabel
            }
            let bodyTextLabel = CVBodyTextLabel()
            _bodyTextLabel = bodyTextLabel
            return bodyTextLabel
        }

        private var _label: UILabel?
        fileprivate var possibleLabel: UILabel? { _label }
        fileprivate var ensuredLabel: UILabel {
            if let label = _label {
                return label
            }
            let label = CVLabel()
            _label = label
            return label
        }

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        required init(componentDelegate: CVComponentDelegate) {
            self.componentDelegate = componentDelegate

            super.init()
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            if !isDedicatedCellView {
                stackView.reset()
            }

            _label?.text = nil
            _bodyTextLabel?.reset()
        }
    }
}

// MARK: -

extension CVComponentBodyText: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        switch bodyText {
        case .bodyText(let displayableText):
            // NOTE: we use the full text.
            return displayableText.fullTextValue.stringValue
        case .oversizeTextDownloading:
            return labelConfigForOversizeTextDownloading.stringValue
        case .remotelyDeleted:
            return labelConfigForRemotelyDeleted.stringValue
        }
    }
}
