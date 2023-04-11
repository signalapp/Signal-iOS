//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CVComponentBodyText: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .bodyText }

    struct State: Equatable {
        let bodyText: CVComponentState.BodyText
        let isTextExpanded: Bool
        let searchText: String?
        let revealedSpoilerIndexes: Set<Int>
        let hasTapForMore: Bool
        let shouldUseAttributedText: Bool
        let hasPendingMessageRequest: Bool
        fileprivate let items: [CVTextLabel.Item]

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
    private var revealedSpoilerIndexes: Set<Int> {
        bodyTextState.revealedSpoilerIndexes
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

    private static func shouldIgnoreEvents(interaction: TSInteraction) -> Bool {
        guard let outgoingMessage = interaction as? TSOutgoingMessage else {
            return false
        }
        // Ignore taps on links in outgoing messages that haven't been sent yet, as
        // this interferes with "tap to retry".
        return outgoingMessage.messageState != .sent
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

    private static func detectItems(text: String,
                                    attributedString: NSAttributedString?,
                                    hasPendingMessageRequest: Bool,
                                    shouldAllowLinkification: Bool,
                                    textWasTruncated: Bool) -> [CVTextLabel.Item] {

        // Use a lock to ensure that measurement on and off the main thread
        // don't conflict.
        unfairLock.withLock {
            guard !hasPendingMessageRequest else {
                // Do not linkify if there is a pending message request.
                return []
            }

            if textWasTruncated {
                owsAssertDebug(text.hasSuffix(DisplayableText.truncatedTextSuffix))
            }

            var items = [CVTextLabel.Item]()
            // Detect and discard overlapping items, preferring mentions to data items.
            func hasItemOverlap(_ newItem: CVTextLabel.Item) -> Bool {
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
                attributedString.enumerateMentionsAndStyles { mention, _, range, _ in
                    guard let mention = mention else { return }
                    let mentionItem = CVTextLabel.MentionItem(mention: mention, range: range)
                    let item: CVTextLabel.Item = .mention(mentionItem: mentionItem)
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
                if textWasTruncated {
                    if NSMaxRange(match.range) == NSMaxRange(text.entireRange) {
                        // This implies that the data detector *included* our "…" suffix.
                        // We don't expect this to happen, but if it does it's certainly not intended!
                        continue
                    }
                    if (text as NSString).substring(after: match.range) == DisplayableText.truncatedTextSuffix {
                        // More likely the item right before the "…" was detected.
                        // Conservatively assume that the item was truncated.
                        continue
                    }
                }

                guard let snippet = (text as NSString).substring(with: match.range).strippedOrNil else {
                    owsFailDebug("Invalid snippet.")
                    continue
                }

                let matchUrl = match.url

                let dataType: CVTextLabel.DataItem.DataType
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

                let dataItem = CVTextLabel.DataItem(dataType: dataType,
                                                    range: match.range,
                                                    snippet: snippet,
                                                    url: url)
                let item: CVTextLabel.Item = .dataItem(dataItem: dataItem)
                guard !hasItemOverlap(item) else {
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
        let revealedSpoilerIndexes = viewStateSnapshot.spoilerReveal.revealedSpoilerIndexes(
            interactionUniqueId: interaction.uniqueId
        )

        let items: [CVTextLabel.Item]
        var shouldUseAttributedText = false
        if let displayableText = bodyText.displayableText,
           let textValue = bodyText.textValue(isTextExpanded: isTextExpanded) {

            let shouldAllowLinkification = displayableText.shouldAllowLinkification
            let textWasTruncated = !isTextExpanded && displayableText.isTextTruncated

            switch textValue {
            case .text(let text):
                items = detectItems(text: text,
                                    attributedString: nil,
                                    hasPendingMessageRequest: hasPendingMessageRequest,
                                    shouldAllowLinkification: shouldAllowLinkification,
                                    textWasTruncated: textWasTruncated)

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
                let dataItems = detectItems(
                    text: attributedText.string,
                    attributedString: attributedText,
                    hasPendingMessageRequest: hasPendingMessageRequest,
                    shouldAllowLinkification: shouldAllowLinkification,
                    textWasTruncated: textWasTruncated
                )
                if FeatureFlags.textFormattingReceiveSupport {
                    var spoilerIndex = 0
                    var spoilerItems = [CVTextLabel.Item]()
                    attributedText.enumerateMentionsAndStyles { _, style, range, _  in
                        guard let style, style.contains(.spoiler) else { return }
                        let index = spoilerIndex
                        spoilerIndex += 1
                        guard revealedSpoilerIndexes.contains(index).negated else { return }
                        spoilerItems.append(.unrevealedSpoiler(
                            CVTextLabel.UnrevealedSpoilerItem(
                                index: index,
                                interactionUniqueId: interaction.uniqueId,
                                range: range
                            )
                        ))
                    }
                    // Spoilers take precedence and overwrite other items. Where their ranges overlap,
                    // we need to cut off the detected item ranges and replace with spoiler range.
                    items = NSRangeUtil.replacingRanges(
                        in: dataItems.sorted(by: { $0.range.location < $1.range.location }),
                        withOverlapsIn: spoilerItems
                    )
                } else {
                    items = dataItems
                }

                shouldUseAttributedText = true
            }
        } else {
            items = []
        }

        return State(bodyText: bodyText,
                     isTextExpanded: isTextExpanded,
                     searchText: searchText,
                     revealedSpoilerIndexes: revealedSpoilerIndexes,
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

    public var textMessageFont: UIFont {
        owsAssertDebug(DisplayableText.kMaxJumbomojiCount == 5)

        if let jumbomojiCount = bodyText.jumbomojiCount {
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
        CVTextLabel.Config(attributedString: textViewConfig.text.attributedString,
                           font: textViewConfig.font,
                           textColor: textViewConfig.textColor,
                           selectionStyling: textSelectionStyling,
                           textAlignment: textViewConfig.textAlignment ?? .natural,
                           lineBreakMode: .byWordWrapping,
                           numberOfLines: 0,
                           cacheKey: textViewConfig.cacheKey,
                           items: bodyTextState.items)
    }

    public func bodyTextLabelConfig(labelConfig: CVLabelConfig) -> CVTextLabel.Config {
        // CVTextLabel requires that attributedString has
        // default attributes applied to the entire string's range.
        let textAlignment: NSTextAlignment = labelConfig.textAlignment ?? .natural
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        let attributedText = labelConfig.attributedString.mutableCopy() as! NSMutableAttributedString
        attributedText.addAttributes(
            [
                .font: labelConfig.font,
                .foregroundColor: labelConfig.textColor,
                .paragraphStyle: paragraphStyle
            ],
            range: attributedText.entireRange
        )

        return CVTextLabel.Config(attributedString: attributedText,
                                  font: labelConfig.font,
                                  textColor: labelConfig.textColor,
                                  selectionStyling: textSelectionStyling,
                                  textAlignment: textAlignment,
                                  lineBreakMode: .byWordWrapping,
                                  numberOfLines: 0,
                                  cacheKey: labelConfig.cacheKey,
                                  items: bodyTextState.items)
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
        configureForBodyTextLabel(componentView: componentView,
                                  bodyTextLabelConfig: bodyTextLabelConfig,
                                  cellMeasurement: cellMeasurement)
    }

    private func configureForBodyTextLabel(componentView: CVComponentViewBodyText,
                                           bodyTextLabelConfig: CVTextLabel.Config,
                                           cellMeasurement: CVCellMeasurement) {
        AssertIsOnMainThread()

        let bodyTextLabel = componentView.bodyTextLabel
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

    public func buildBodyTextLabelConfig() -> CVTextLabel.Config {
        switch bodyText {
        case .bodyText(let displayableText):
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

    private typealias TextConfig = CVTextViewConfig

    private func textConfig(displayableText: DisplayableText) -> TextConfig {
        let textValue = displayableText.textValue(isTextExpanded: isTextExpanded)
        return self.textViewConfig(displayableText: displayableText,
                                   attributedText: textValue.attributedString)
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
                                   shouldAllowLinkification: Bool,
                                   textWasTruncated: Bool) {

        let items = detectItems(text: attributedText.string,
                                attributedString: attributedText,
                                hasPendingMessageRequest: hasPendingMessageRequest,
                                shouldAllowLinkification: shouldAllowLinkification,
                                textWasTruncated: textWasTruncated)
        Self.linkifyData(attributedText: attributedText,
                         linkifyStyle: linkifyStyle,
                         items: items)
    }

    private static func linkifyData(attributedText: NSMutableAttributedString,
                                    linkifyStyle: LinkifyStyle,
                                    items: [CVTextLabel.Item]) {

        // Sort so that we can detect overlap.
        let items = items.sorted {
            $0.range.location < $1.range.location
        }

        var lastIndex: Int = 0
        for item in items {
            let range = item.range

            guard range.location >= lastIndex else {
                owsFailDebug("Overlapping ranges.")
                continue
            }
            switch item {
            case .mention, .referencedUser, .unrevealedSpoiler:
                // Do nothing; these are already styled.
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

        if FeatureFlags.textFormattingReceiveSupport {
            // Styles take precedence over everything else, so apply them last.
            // TODO[TextFormatting]: spoilers in search results should change both
            // the highlight and the text color to yellow.
            MessageBodyRanges.applyStyleAttributes(
                on: attributedText,
                baseFont: textMessageFont,
                textColor: bodyTextColor,
                spoilerStyler: { spoilerIndex, _ in
                    if revealedSpoilerIndexes.contains(spoilerIndex) {
                        return .revealed
                    } else {
                        return .concealedWithHighlight(bodyTextColor)
                    }
                }
            )
        }

        var extraCacheKeyFactors = [String]()
        if hasPendingMessageRequest {
            extraCacheKeyFactors.append("hasPendingMessageRequest")
        }
        extraCacheKeyFactors.append("items: \(!bodyTextState.items.isEmpty)")

        return CVTextViewConfig(attributedText: attributedText,
                                font: textMessageFont,
                                textColor: bodyTextColor,
                                textAlignment: textAlignment,
                                linkTextAttributes: linkTextAttributes,
                                extraCacheKeyFactors: extraCacheKeyFactors)
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

        let bodyTextLabel = componentView.bodyTextLabel
        if let item = bodyTextLabel.itemForGesture(sender: sender) {
            bodyTextLabel.animate(selectedItem: item)
            componentDelegate.didTapBodyTextItem(item)
            return true
        }
        if hasTapForMore {
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            componentDelegate.didTapTruncatedTextMessage(itemViewModel)
            return true
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

        required init(componentDelegate: CVComponentDelegate) {
            self.componentDelegate = componentDelegate

            super.init()
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

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
