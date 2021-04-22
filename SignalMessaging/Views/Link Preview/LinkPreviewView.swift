//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import YYImage

@objc
public protocol LinkPreviewViewDraftDelegate {
    func linkPreviewCanCancel() -> Bool
    func linkPreviewDidCancel()
}

// MARK: -

@objc
public class LinkPreviewView: ManualStackViewWithLayer {
    private weak var draftDelegate: LinkPreviewViewDraftDelegate?

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    @available(*, unavailable, message: "use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init(name: String, arrangedSubviews: [UIView] = []) {
        notImplemented()
    }

    fileprivate let rightStack = ManualStackView(name: "rightStack")
    fileprivate let textStack = ManualStackView(name: "textStack")
    fileprivate let titleStack = ManualStackView(name: "titleStack")

    fileprivate let titleLabel = CVLabel()
    fileprivate let descriptionLabel = CVLabel()
    fileprivate let displayDomainLabel = CVLabel()

    fileprivate let linkPreviewImageView = LinkPreviewImageView()

    @objc
    public init(draftDelegate: LinkPreviewViewDraftDelegate?) {
        self.draftDelegate = draftDelegate

        super.init(name: "LinkPreviewView")

        if let draftDelegate = draftDelegate,
            draftDelegate.linkPreviewCanCancel() {
            self.isUserInteractionEnabled = true
            self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))
        }
    }

    private var isDraft: Bool {
        return draftDelegate != nil
    }

    // TODO: hasAsymmetricalRounding
    public func configureForRendering(state: LinkPreviewState,
                                      hasAsymmetricalRounding: Bool,
                                      cellMeasurement: CVCellMeasurement) {
        let adapter = self.adapter(forState: state)
        adapter.configureForRendering(linkPreviewView: self,
                                      hasAsymmetricalRounding: hasAsymmetricalRounding,
                                      cellMeasurement: cellMeasurement)

//        guard state.isLoaded() else {
//            createDraftLoadingContents(state: state)
//            return
//        }
//        if isDraft {
//            createDraftContents(state: state)
//        } else if state.isGroupInviteLink {
//            createGroupLinkContents()
//        } else {
//            createSentContents()
//        }
//    }
//
//    private func createSentContents() {
//        guard let state = state else {
//            owsFailDebug("Invalid state")
//            return
//        }
//        guard let conversationStyle = state.conversationStyle else {
//            owsFailDebug("Missing conversationStyle.")
//            return
//        }
//
//        addBackgroundView(withBackgroundColor: Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray02)
//
//        if let imageView = createImageView(state: state) {
//            if Self.sentIsHero(state: state) {
//                createHeroSentContents(state: state,
//                                       conversationStyle: conversationStyle,
//                                       imageView: imageView)
//            } else if state.previewDescription()?.isEmpty == false,
//                      state.title()?.isEmpty == false {
//                createNonHeroWithDescriptionSentContents(state: state, imageView: imageView)
//            } else {
//                createNonHeroSentContents(state: state, imageView: imageView)
//            }
//        } else {
//            createNonHeroSentContents(state: state, imageView: nil)
//        }
    }

    private func adapter(forState state: LinkPreviewState) -> LinkPreviewViewAdapter {
        if !state.isLoaded() {
            return LinkPreviewViewAdapterDraftLoading(state: state)
        } else if isDraft {
            return LinkPreviewViewAdapterDraft(state: state)
        } else if state.isGroupInviteLink {
            return LinkPreviewViewAdapterGroupLink(state: state)
        } else {
            if state.hasLoadedImage {
                if Self.sentIsHero(state: state) {
                    return LinkPreviewViewAdapterSentHero(state: state)
                } else if state.previewDescription()?.isEmpty == false,
                          state.title()?.isEmpty == false {
                    return LinkPreviewViewAdapterSentWithDescription(state: state)
                } else {
                    return LinkPreviewViewAdapterSent(state: state)
                }
            } else {
                return LinkPreviewViewAdapterSent(state: state)
            }
        }
    }

    private func createNonHeroWithDescriptionSentContents(state: LinkPreviewState, imageView: UIImageView?) {
        self.axis = .vertical
        self.isLayoutMarginsRelativeArrangement = true
        self.layoutMargins = Self.sentNonHeroLayoutMargins
        self.spacing = Self.sentVSpacing
        self.alignment = .fill

        let titleStack = UIStackView()
        titleStack.isLayoutMarginsRelativeArrangement = true
        titleStack.axis = .horizontal
        titleStack.spacing = Self.sentNonHeroHSpacing
        titleStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: Self.sentVSpacing, right: 0)
        addArrangedSubview(titleStack)

        if let imageView = imageView {
            imageView.autoSetDimensions(to: CGSize(square: Self.sentNonHeroImageSize))
            imageView.contentMode = .scaleAspectFill
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            // TODO: Cropping, stroke.

            let containerView = UIView()
            containerView.addSubview(imageView)
            containerView.autoSetDimension(.height, toSize: Self.sentNonHeroImageSize, relation: .greaterThanOrEqual)

            imageView.autoCenterInSuperview()
            imageView.autoPinEdge(toSuperviewEdge: .leading)
            imageView.autoPinEdge(toSuperviewEdge: .trailing)
            titleStack.addArrangedSubview(containerView)
        }

        if let titleLabel = sentTitleLabel(state: state) {
            titleStack.addArrangedSubview(titleLabel)
        } else {
            owsFailDebug("Text stack required")
        }

        if let descriptionLabel = sentDescriptionLabel(state: state) {
            addArrangedSubview(descriptionLabel)
        } else {
            owsFailDebug("Description label required")
        }

        let domainLabel = sentDomainLabel(state: state)
        addArrangedSubview(domainLabel)
        sentBodyView = self
    }

    private func createNonHeroSentContents(state: LinkPreviewState,
                                           imageView: UIImageView?) {
        self.layoutMargins = .zero
        self.axis = .horizontal
        self.isLayoutMarginsRelativeArrangement = true
        self.layoutMargins = Self.sentNonHeroLayoutMargins
        self.spacing = Self.sentNonHeroHSpacing

        if let imageView = imageView {
            imageView.autoSetDimensions(to: CGSize(square: Self.sentNonHeroImageSize))
            imageView.contentMode = .scaleAspectFill
            imageView.setContentHuggingHigh()
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            // TODO: Cropping, stroke.
            addArrangedSubview(imageView)
        }

        let textStack = createSentTextStack(state: state)
        addArrangedSubview(textStack)

        sentBodyView = self
    }

    private func createSentTextStack(state: LinkPreviewState) -> UIStackView {
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = Self.sentVSpacing

        if let titleLabel = sentTitleLabel(state: state) {
            textStack.addArrangedSubview(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(state: state) {
            textStack.addArrangedSubview(descriptionLabel)
        }
        let domainLabel = sentDomainLabel(state: state)
        textStack.addArrangedSubview(domainLabel)

        return textStack
    }

    fileprivate static let sentTitleFontSizePoints: CGFloat = 17
    fileprivate static let sentDomainFontSizePoints: CGFloat = 12
    fileprivate static let sentVSpacing: CGFloat = 4

    // The "sent message" mode has two submodes: "hero" and "non-hero".
    fileprivate static let sentNonHeroHMargin: CGFloat = 12
    fileprivate static let sentNonHeroVMargin: CGFloat = 12
    fileprivate static var sentNonHeroLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: sentNonHeroVMargin,
                     left: sentNonHeroHMargin,
                     bottom: sentNonHeroVMargin,
                     right: sentNonHeroHMargin)
    }

    fileprivate static let sentNonHeroImageSize: CGFloat = 64
    fileprivate static let sentNonHeroHSpacing: CGFloat = 8

    fileprivate static let sentHeroHMargin: CGFloat = 12
    fileprivate static let sentHeroVMargin: CGFloat = 12
    fileprivate static var sentHeroLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: sentHeroVMargin,
                     left: sentHeroHMargin,
                     bottom: sentHeroVMargin,
                     right: sentHeroHMargin)
    }

    fileprivate static let sentTitleLineCount: Int = 2
    fileprivate static let sentDescriptionLineCount: Int = 3

    fileprivate static func sentIsHero(state: LinkPreviewState) -> Bool {
        if isSticker(state: state) || state.isGroupInviteLink {
            return false
        }
        guard let heroWidthPoints = state.conversationStyle?.maxMessageWidth else {
            return false
        }

        // On a 1x device, even tiny images like avatars can satisfy the max message width
        // On a 3x device, achieving a 3x pixel match on an og:image is rare
        // By fudging the required scaling a bit towards 2.0, we get more consistency at the
        // cost of slightly blurrier images on 3x devices.
        // These are totally made up numbers so feel free to adjust as necessary.
        let heroScalingFactors: [CGFloat: CGFloat] = [
            1.0: 2.0,
            2.0: 2.0,
            3.0: 2.3333
        ]
        let scalingFactor = heroScalingFactors[UIScreen.main.scale] ?? {
            // Oh neat a new device! Might want to add it.
            owsFailDebug("Unrecognized device scale")
            return 2.0
        }()
        let minimumHeroWidth = heroWidthPoints * scalingFactor
        let minimumHeroHeight = minimumHeroWidth * 0.33

        let widthSatisfied = state.imagePixelSize.width >= minimumHeroWidth
        let heightSatisfied = state.imagePixelSize.height >= minimumHeroHeight
        return widthSatisfied && heightSatisfied
    }

    private static func isSticker(state: LinkPreviewState) -> Bool {
        guard let urlString = state.urlString() else {
            owsFailDebug("Link preview is missing url.")
            return false
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Could not parse URL.")
            return false
        }
        return StickerPackInfo.isStickerPackShare(url)
    }

    private func createImageView(state: LinkPreviewState,
                                 rounding roundingParam: LinkPreviewImageView.Rounding? = nil) -> UIImageView? {
        guard state.isLoaded() else {
            owsFailDebug("State not loaded.")
            return nil
        }

        guard state.imageState() == .loaded else {
            return nil
        }
        guard let image = state.image() else {
            owsFailDebug("Could not load image.")
            return nil
        }
        let imageView = LinkPreviewImageView(rounding: roundingParam ?? .standard)
        imageView.image = image
        imageView.isHero = Self.sentIsHero(state: state)
        return imageView
    }

    static var defaultActivityIndicatorStyle: UIActivityIndicatorView.Style {
        Theme.isDarkThemeEnabled
        ? .white
        : .gray
    }

    // MARK: Events

    @objc func wasTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        if let cancelButton = cancelButton {
            // Permissive hot area to make it very easy to cancel the link preview.
            if cancelButton.containsGestureLocation(sender, hotAreaAdjustment: 20) {
                self.draftDelegate?.linkPreviewDidCancel()
                return
            }
        }
    }

    // MARK: Measurement

    @objc
    public func measure(maxWidth: CGFloat,
                        measurementBuilder: CVCellMeasurement.Builder,
                        state: LinkPreviewState) -> CGSize {
        let adapter = self.adapter(forState: state)
        return adapter.measure(maxWidth: maxWidth,
                               measurementBuilder: measurementBuilder,
                               state: state)
    }

    @objc
    public static func measure(withState state: LinkPreviewState) -> CGSize {
        if let sentState = state as? LinkPreviewSent {
            return self.measure(withSentState: sentState)
        } else if let groupLinkState = state as? LinkPreviewGroupLink {
            return self.measure(withGroupLinkState: groupLinkState)
        } else if let loadingState = state as? LinkPreviewLoading {
            return self.measure(withLoadingState: loadingState)
        } else {
            owsFailDebug("Invalid state.")
            return .zero
        }
    }

    @objc
    public static func measure(withLoadingState state: LinkPreviewLoading) -> CGSize {
        let size = Self.draftHeight + Self.draftMarginTop
        return CGSize(width: size, height: size)
    }

    @objc
    public static func measure(withGroupLinkState state: LinkPreviewGroupLink) -> CGSize {

        guard let conversationStyle = state.conversationStyle else {
            owsFailDebug("Missing conversationStyle.")
            return .zero
        }

        let hasImage = state.imageState() != .none

        let maxMessageWidth = conversationStyle.maxMessageWidth

        var maxTextWidth = maxMessageWidth - 2 * sentNonHeroHMargin
        if hasImage {
            maxTextWidth -= (sentNonHeroImageSize + sentNonHeroHSpacing)
        }
        let textStackSize = sentTextStackSize(state: state, maxWidth: maxTextWidth, ignoreDomain: true)

        var result = textStackSize

        result.width += sentNonHeroImageSize + sentNonHeroHSpacing
        result.height = max(result.height, sentNonHeroImageSize)

        result.width += 2 * sentNonHeroHMargin
        result.height += 2 * sentNonHeroVMargin

        return CGSizeCeil(result)
    }

    @objc
    public static func measure(withSentState state: LinkPreviewState) -> CGSize {

        guard let conversationStyle = state.conversationStyle else {
            owsFailDebug("Missing conversationStyle.")
            return .zero
        }

        switch state.imageState() {
        case .loaded:
            if sentIsHero(state: state) {
                return measureSentHero(state: state, conversationStyle: conversationStyle)
            } else if state.previewDescription()?.isEmpty == false,
                state.title()?.isEmpty == false {
                return measureSentNonHeroWithDescription(state: state, conversationStyle: conversationStyle)
            } else {
                return measureSentNonHero(state: state, conversationStyle: conversationStyle, hasImage: true)
            }
        default:
            return measureSentNonHero(state: state, conversationStyle: conversationStyle, hasImage: false)
        }
    }

    private static func measureSentHero(state: LinkPreviewState,
                                 conversationStyle: ConversationStyle) -> CGSize {
        let maxMessageWidth = conversationStyle.maxMessageWidth
        var messageHeight: CGFloat  = 0

        let heroImageSize = sentHeroImageSize(state: state, conversationStyle: conversationStyle)
        messageHeight += heroImageSize.height

        let textStackSize = sentTextStackSize(state: state,
                                              maxWidth: maxMessageWidth - 2 * sentHeroHMargin)
        messageHeight += textStackSize.height + 2 * sentHeroVMargin

        return CGSizeCeil(CGSize(width: maxMessageWidth, height: messageHeight))
    }

    private static func measureSentNonHeroWithDescription(state: LinkPreviewState,
                                                   conversationStyle: ConversationStyle) -> CGSize {
        let maxMessageWidth = conversationStyle.maxMessageWidth

        let bottomMaxTextWidth = maxMessageWidth - 2 * sentNonHeroHMargin
        let titleMaxTextWidth = bottomMaxTextWidth - (sentNonHeroImageSize + sentNonHeroHSpacing)

        let titleLabelSize = sentTitleLabelConfig(state: state)?.measure(maxWidth: titleMaxTextWidth) ?? .zero
        let descriptionLabelSize = sentDescriptionLabelConfig(state: state)?.measure(maxWidth: bottomMaxTextWidth) ?? .zero
        let domainLabelSize = sentDomainLabelConfig(state: state).measure(maxWidth: bottomMaxTextWidth)

        let bindingTitleHeight = max(titleLabelSize.height, sentNonHeroImageSize)

        var resultSize = CGSize.zero
        resultSize.height += sentNonHeroVMargin
        resultSize.height += bindingTitleHeight
        resultSize.height += sentVSpacing * 2
        resultSize.height += descriptionLabelSize.height
        resultSize.height += sentVSpacing
        resultSize.height += domainLabelSize.height
        resultSize.height += sentNonHeroVMargin

        let titleStackWidth = titleLabelSize.width + sentNonHeroHSpacing + sentNonHeroImageSize
        resultSize.width = [titleStackWidth, descriptionLabelSize.width, domainLabelSize.width].max() ?? 0
        resultSize.width += (sentNonHeroHMargin * 2)

        return CGSizeCeil(resultSize)
    }

    private static func measureSentNonHero(state: LinkPreviewState,
                                    conversationStyle: ConversationStyle,
                                    hasImage: Bool) -> CGSize {
        let maxMessageWidth = conversationStyle.maxMessageWidth

        var maxTextWidth = maxMessageWidth - 2 * sentNonHeroHMargin
        if hasImage {
            maxTextWidth -= (sentNonHeroImageSize + sentNonHeroHSpacing)
        }
        let textStackSize = sentTextStackSize(state: state, maxWidth: maxTextWidth)

        var result = textStackSize

        if hasImage {
            result.width += sentNonHeroImageSize + sentNonHeroHSpacing
            result.height = max(result.height, sentNonHeroImageSize)
        }

        result.width += 2 * sentNonHeroHMargin
        result.height += 2 * sentNonHeroVMargin

        return CGSizeCeil(result)
    }

    private static func sentLabelSize(label: UILabel, maxWidth: CGFloat) -> CGSize {
        CGSizeCeil(label.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)))
    }

    private static func sentTextStackSize(state: LinkPreviewState, maxWidth: CGFloat, ignoreDomain: Bool = false) -> CGSize {

        var labelSizes = [CGSize]()

        if !ignoreDomain {
            let config = sentDomainLabelConfig(state: state)
            let domainLabelSize = config.measure(maxWidth: maxWidth)
            labelSizes.append(domainLabelSize)
        }
        if let config = sentTitleLabelConfig(state: state) {
            let titleLabelSize = config.measure(maxWidth: maxWidth)
            labelSizes.append(titleLabelSize)
        }
        if let config = sentDescriptionLabelConfig(state: state) {
            let descriptionLabelSize = config.measure(maxWidth: maxWidth)
            labelSizes.append(descriptionLabelSize)
        }

        return measureTextStack(labelSizes: labelSizes)
    }

    private static func measureTextStack(labelSizes: [CGSize]) -> CGSize {
        let width = labelSizes.map { $0.width }.reduce(0, max)
        let height = labelSizes.map { $0.height }.reduce(0, +) + CGFloat(labelSizes.count - 1) * sentVSpacing
        return CGSize(width: width, height: height)
    }

    @objc
    fileprivate func didTapCancel() {
        draftDelegate?.linkPreviewDidCancel()
    }

    public override func reset() {
        super.reset()

        self.backgroundColor = nil

        rightStack.reset()
        textStack.reset()
        titleStack.reset()

        titleLabel.text = nil
        descriptionLabel.text = nil
        displayDomainLabel.text = nil

        linkPreviewImageView.reset()

//        self.axis = .horizontal
//        self.alignment = .center
//        self.distribution = .fill
//        self.spacing = 0
//        self.isLayoutMarginsRelativeArrangement = false
//        self.layoutMargins = .zero
//
//        cancelButton = nil
//        heroImageView = nil
//        sentBodyView = nil
    }

    fileprivate static let measurementKey_rootStack = "LinkPreviewView.measurementKey_rootStack"
    fileprivate static let measurementKey_rightStack = "LinkPreviewView.measurementKey_rightStack"
    fileprivate static let measurementKey_textStack = "LinkPreviewView.measurementKey_textStack"
    fileprivate static let measurementKey_titleStack = "LinkPreviewView.measurementKey_titleStack"
}

// MARK: -

private protocol LinkPreviewViewAdapter {
    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement)

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize
}

// MARK: -

extension LinkPreviewViewAdapter {

    func sentTitleLabel(state: LinkPreviewState) -> UILabel? {
        guard let config = sentTitleLabelConfig(state: state) else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    func sentTitleLabelConfig(state: LinkPreviewState) -> CVLabelConfig? {
        guard let text = state.title() else {
            return nil
        }
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeSubheadline.ows_semibold,
                             textColor: Theme.primaryTextColor,
                             numberOfLines: LinkPreviewView.sentTitleLineCount,
                             lineBreakMode: .byTruncatingTail)
    }

    func sentDescriptionLabel(state: LinkPreviewState) -> UILabel? {
        guard let config = sentDescriptionLabelConfig(state: state) else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    func sentDescriptionLabelConfig(state: LinkPreviewState) -> CVLabelConfig? {
        guard let text = state.previewDescription() else { return nil }
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeSubheadline,
                             textColor: Theme.primaryTextColor,
                             numberOfLines: LinkPreviewView.sentDescriptionLineCount,
                             lineBreakMode: .byTruncatingTail)
    }

    func sentDomainLabel(state: LinkPreviewState) -> UILabel {
        let label = CVLabel()
        sentDomainLabelConfig(state: state).applyForRendering(label: label)
        return label
    }

    func sentDomainLabelConfig(state: LinkPreviewState) -> CVLabelConfig {
        var labelText: String
        if let displayDomain = state.displayDomain(),
           displayDomain.count > 0 {
            labelText = displayDomain.lowercased()
        } else {
            labelText = NSLocalizedString("LINK_PREVIEW_UNKNOWN_DOMAIN", comment: "Label for link previews with an unknown host.").uppercased()
        }
        if let date = state.date() {
            labelText.append(" ⋅ \(LinkPreviewView.dateFormatter.string(from: date))")
        }
        return CVLabelConfig(text: labelText,
                             font: UIFont.ows_dynamicTypeCaption1,
                             textColor: Theme.secondaryTextAndIconColor)
    }

    func configureSentTextStack(linkPreviewView: LinkPreviewView,
                                state: LinkPreviewState,
                                textStack: ManualStackView,
                                textStackConfig: ManualStackView.Config,
                                cellMeasurement: CVCellMeasurement) {

        var subviews = [UIView]()

        if let titleLabel = sentTitleLabel(state: state) {
            subviews.append(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(state: state) {
            subviews.append(descriptionLabel)
        }
        let domainLabel = sentDomainLabel(state: state)
        subviews.append(domainLabel)

        textStack.configure(config: textStackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: LinkPreviewView.measurementKey_textStack,
                            subviews: subviews)
    }

    func measureSentTextStack(state: LinkPreviewState,
                              textStackConfig: ManualStackView.Config,
                              measurementBuilder: CVCellMeasurement.Builder,
                              maxLabelWidth: CGFloat) -> CGSize {

        var subviewInfos = [ManualStackSubviewInfo]()

        if let labelConfig = sentTitleLabelConfig(state: state) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            subviewInfos.append(labelSize.asManualSubviewInfo)
        }
        if let labelConfig = sentDescriptionLabelConfig(state: state) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            subviewInfos.append(labelSize.asManualSubviewInfo)
        }
        let labelConfig = sentDomainLabelConfig(state: state)
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
        subviewInfos.append(labelSize.asManualSubviewInfo)

        let measurement = ManualStackView.measure(config: textStackConfig,
                                                  measurementBuilder: measurementBuilder,
                                                  measurementKey: LinkPreviewView.measurementKey_textStack,
                                                  subviewInfos: subviewInfos)
        return measurement.measuredSize
    }
}

// MARK: -

private class LinkPreviewViewAdapterDraft: LinkPreviewViewAdapter {

    static let draftHeight: CGFloat = 72
    static let draftMarginTop: CGFloat = 6
    var imageSize: CGFloat { Self.draftHeight }
    var hasImage: Bool { state.hasLoadedImage }
    let cancelSize: CGFloat = 20

    let state: LinkPreviewState

    init(state: LinkPreviewState) {
        self.state = state
    }

    var rootStackConfig: ManualStackView.Config {
        let hMarginLeading: CGFloat = hasImage ? 6 : 12
        let hMarginTrailing: CGFloat = 12
        let layoutMargins = UIEdgeInsets(top: Self.draftMarginTop,
                                         leading: hMarginLeading,
                                         bottom: 0,
                                         trailing: hMarginTrailing)
        return ManualStackView.Config(axis: .horizontal,
                                      alignment: .fill,
                                      spacing: 8,
                                      layoutMargins: layoutMargins)
    }

    var rightStackConfig: ManualStackView.Config {
        return ManualStackView.Config(axis: .horizontal,
                                      alignment: .fill,
                                      spacing: 8,
                                      layoutMargins: .zero)
    }

    var textStackConfig: ManualStackView.Config {
        return ManualStackView.Config(axis: .vertical,
                                      alignment: .leading,
                                      spacing: 2,
                                      layoutMargins: .zero)
    }

    var titleLabelConfig: CVLabelConfig? {
        guard let text = state.title()?.nilIfEmpty else {
            return nil
        }
        return CVLabelConfig(text: text,
                             font: .ows_dynamicTypeBody,
                             textColor: Theme.primaryTextColor)
    }

    var descriptionLabelConfig: CVLabelConfig? {
        guard let text = state.previewDescription()?.nilIfEmpty else {
            return nil
        }
        return CVLabelConfig(text: text,
                             font: .ows_dynamicTypeSubheadline,
                             textColor: Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray90)
    }

    var displayDomainLabelConfig: CVLabelConfig? {
        guard let displayDomain = state.displayDomain()?.nilIfEmpty else {
            return nil
        }
        var text = displayDomain.lowercased()
        if let date = state.date() {
            text.append(" ⋅ \(LinkPreviewView.dateFormatter.string(from: date))")
        }
        return CVLabelConfig(text: text,
                             font: .ows_dynamicTypeCaption1,
                             textColor: Theme.secondaryTextAndIconColor)
    }

    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement) {

        var rootStackSubviews = [UIView]()
        var rightStackSubviews = [UIView]()

        // Image

        if hasImage {
            let linkPreviewImageView = linkPreviewView.linkPreviewImageView
            if let imageView = linkPreviewImageView.configureForDraft(state: state,
                                                                      hasAsymmetricalRounding: hasAsymmetricalRounding) {
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                rootStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                let imageView = UIView.transparentSpacer()
                rootStackSubviews.append(imageView)
            }
        }

        // Text

        var textStackSubviews = [UIView]()

        if let titleLabelConfig = self.titleLabelConfig {
            let titleLabel = linkPreviewView.titleLabel
            titleLabelConfig.applyForRendering(label: titleLabel)
            textStackSubviews.append(titleLabel)
        }

        if let descriptionLabelConfig = self.descriptionLabelConfig {
            let descriptionLabel = linkPreviewView.descriptionLabel
            descriptionLabelConfig.applyForRendering(label: descriptionLabel)
            textStackSubviews.append(descriptionLabel)
        }

        if let displayDomainLabelConfig = self.displayDomainLabelConfig {
            let displayDomainLabel = linkPreviewView.displayDomainLabel
            displayDomainLabelConfig.applyForRendering(label: displayDomainLabel)
            textStackSubviews.append(displayDomainLabel)
        }

        let textStack = linkPreviewView.textStack
        textStack.configure(config: textStackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: LinkPreviewView.measurementKey_textStack,
                            subviews: textStackSubviews)
        guard let textMeasurement = cellMeasurement.measurement(key: LinkPreviewView.measurementKey_textStack) else {
            owsFailDebug("Missing measurement.")
            return
        }
        let textWrapper = ManualLayoutView(name: "textWrapper")
        textWrapper.addSubviewToCenterOnSuperview(textStack,
                                                  size: textMeasurement.measuredSize)
        rightStackSubviews.append(textWrapper)

        // Right

        let rightStack = linkPreviewView.rightStack
        rightStack.configure(config: rightStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: LinkPreviewView.measurementKey_rightStack,
                             subviews: rightStackSubviews)
        rootStackSubviews.append(rightStack)

        // Cancel

        let cancelButton = OWSButton { [weak linkPreviewView] in
            linkPreviewView?.didTapCancel()
        }
        cancelButton.setTemplateImageName("compose-cancel",
                                          tintColor: Theme.secondaryTextAndIconColor)
        let cancelSize = self.cancelSize
        rightStack.addSubview(cancelButton) { view in
            cancelButton.frame = CGRect(x: 0, y: view.bounds.width - cancelSize, width: cancelSize, height: cancelSize)
        }

        // Stroke

        let strokeView = UIView()
        strokeView.backgroundColor = Theme.secondaryTextAndIconColor
        rightStack.addSubviewAsBottomStroke(strokeView)

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: LinkPreviewView.measurementKey_rootStack,
                                  subviews: rootStackSubviews)
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        let activityIndicatorSize = CGSize.square(25)
        let strokeSize = CGSize(width: 0, height: CGHairlineWidth())

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: LinkPreviewView.measurementKey_rootStack,
                                                           subviewInfos: [
                                                            activityIndicatorSize.asManualSubviewInfo(hasFixedSize: true),
                                                            strokeSize.asManualSubviewInfo(hasFixedHeight: true)
                                                           ])
        var rootStackSize = rootStackMeasurement.measuredSize
        rootStackSize.height = (LinkPreviewViewAdapterDraft.draftHeight +
                                    LinkPreviewViewAdapterDraft.draftMarginTop)
        return rootStackSize
    }
}

// MARK: -

private class LinkPreviewViewAdapterDraftLoading: LinkPreviewViewAdapter {

    let activityIndicatorSize = CGSize.square(25)

    let state: LinkPreviewState

    init(state: LinkPreviewState) {
        self.state = state
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .vertical,
                               alignment: .fill,
                               spacing: 0,
                               layoutMargins: .zero)
    }

    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement) {

        let activityIndicatorStyle = state.activityIndicatorStyle
        let activityIndicator = UIActivityIndicatorView(style: activityIndicatorStyle)
        activityIndicator.startAnimating()
        linkPreviewView.addSubviewToCenterOnSuperview(activityIndicator,
                                                      size: activityIndicatorSize)

        let strokeView = UIView()
        strokeView.backgroundColor = Theme.secondaryTextAndIconColor
        linkPreviewView.addSubviewAsBottomStroke(strokeView,
                                                 layoutMargins: UIEdgeInsets(hMargin: 12,
                                                                             vMargin: 0))

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: LinkPreviewView.measurementKey_rootStack,
                                  subviews: [
                                    activityIndicator,
                                    strokeView
                                  ])
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                  measurementBuilder: measurementBuilder,
                                                  measurementKey: LinkPreviewView.measurementKey_rootStack,
                                                  subviewInfos: [
                                                  ])
        var rootStackSize = rootStackMeasurement.measuredSize
        rootStackSize.height = (LinkPreviewViewAdapterDraft.draftHeight +
                                    LinkPreviewViewAdapterDraft.draftMarginTop)
        return rootStackSize
    }
}

// MARK: -

private class LinkPreviewViewAdapterGroupLink: LinkPreviewViewAdapter {

    let state: LinkPreviewState

    init(state: LinkPreviewState) {
        self.state = state
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .horizontal,
                               alignment: .fill,
                               spacing: LinkPreviewView.sentNonHeroHSpacing,
                               layoutMargins: LinkPreviewView.sentNonHeroLayoutMargins)
    }

    var textStackConfig: ManualStackView.Config {
        return ManualStackView.Config(axis: .vertical,
                                      alignment: .leading,
                                      spacing: LinkPreviewView.sentVSpacing,
                                      layoutMargins: .zero)
    }

    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement) {

        linkPreviewView.backgroundColor = Theme.secondaryBackgroundColor

        var rootStackSubviews = [UIView]()

        let linkPreviewImageView = linkPreviewView.linkPreviewImageView
        if state.hasLoadedImage {
            if let imageView = linkPreviewImageView.configure(state: state, rounding: .circular) {
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                rootStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                rootStackSubviews.append(UIView.transparentSpacer())
            }
        }

        let textStack = linkPreviewView.textStack
        var textStackSubviews = [UIView]()
        if let titleLabel = sentTitleLabel(state: state) {
            textStackSubviews.append(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(state: state) {
            textStackSubviews.append(descriptionLabel)
        }
        textStack.configure(config: textStackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: LinkPreviewView.measurementKey_textStack,
                            subviews: textStackSubviews)
        rootStackSubviews.append(textStack)

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: LinkPreviewView.measurementKey_rootStack,
                                  subviews: rootStackSubviews)
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        var maxLabelWidth = (maxWidth -
                                (textStackConfig.layoutMargins.totalWidth +
                                    rootStackConfig.layoutMargins.totalWidth))

        var rootStackSubviewInfos = [ManualStackSubviewInfo]()
        if state.hasLoadedImage {
            let imageSize = LinkPreviewView.sentNonHeroImageSize
            rootStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxLabelWidth -= imageSize + rootStackConfig.spacing
        }

        maxLabelWidth = max(0, maxLabelWidth)

        var textStackSubviewInfos = [ManualStackSubviewInfo]()
        if let labelConfig = sentTitleLabelConfig(state: state) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            textStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        }
        if let labelConfig = sentDescriptionLabelConfig(state: state) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            textStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        }

        let textStackMeasurement = ManualStackView.measure(config: textStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: LinkPreviewView.measurementKey_textStack,
                                                           subviewInfos: textStackSubviewInfos)
        rootStackSubviewInfos.append(textStackMeasurement.measuredSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: LinkPreviewView.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos)
        return rootStackMeasurement.measuredSize
    }
}

// MARK: -

private class LinkPreviewViewAdapterSentHero: LinkPreviewViewAdapter {

    let state: LinkPreviewState

    init(state: LinkPreviewState) {
        self.state = state
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .vertical,
                               alignment: .fill,
                               spacing: 0,
                               layoutMargins: .zero)
    }

    var textStackConfig: ManualStackView.Config {
        return ManualStackView.Config(axis: .vertical,
                                      alignment: .center,
                                      spacing: LinkPreviewView.sentVSpacing,
                                      layoutMargins: .zero)
    }

    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement) {

        linkPreviewView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray02

        var rootStackSubviews = [UIView]()

        let linkPreviewImageView = linkPreviewView.linkPreviewImageView
        if let imageView = linkPreviewImageView.configure(state: state) {
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            rootStackSubviews.append(imageView)
        } else {
            owsFailDebug("Could not load image.")
            rootStackSubviews.append(UIView.transparentSpacer())
        }

        let textStack = linkPreviewView.textStack
        configureSentTextStack(linkPreviewView: linkPreviewView,
                               state: state,
                               textStack: textStack,
                               textStackConfig: textStackConfig,
                               cellMeasurement: cellMeasurement)
        rootStackSubviews.append(textStack)

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: LinkPreviewView.measurementKey_rootStack,
                                  subviews: rootStackSubviews)
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        guard let conversationStyle = state.conversationStyle else {
            owsFailDebug("Missing conversationStyle.")
            return .zero
        }

        var rootStackSubviewInfos = [ManualStackSubviewInfo]()

        let heroImageSize = sentHeroImageSize(state: state,
                                              conversationStyle: conversationStyle)
        rootStackSubviewInfos.append(heroImageSize.asManualSubviewInfo)

        var maxLabelWidth = (maxWidth -
                                (textStackConfig.layoutMargins.totalWidth +
                                    rootStackConfig.layoutMargins.totalWidth))
        maxLabelWidth = max(0, maxLabelWidth)

        let textStackSize = measureSentTextStack(state: state,
                                                 textStackConfig: textStackConfig,
                                                 measurementBuilder: measurementBuilder,
                                                 maxLabelWidth: maxLabelWidth)
        rootStackSubviewInfos.append(textStackSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: LinkPreviewView.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos)
        return rootStackMeasurement.measuredSize
    }

    func sentHeroImageSize(state: LinkPreviewState,
                           conversationStyle: ConversationStyle) -> CGSize {

        let imageHeightWidthRatio = (state.imagePixelSize.height / state.imagePixelSize.width)
        let maxMessageWidth = conversationStyle.maxMessageWidth

        let minImageHeight: CGFloat = maxMessageWidth * 0.5
        let maxImageHeight: CGFloat = maxMessageWidth
        let rawImageHeight = maxMessageWidth * imageHeightWidthRatio

        let normalizedHeight: CGFloat = min(maxImageHeight, max(minImageHeight, rawImageHeight))
        return CGSizeCeil(CGSize(width: maxMessageWidth, height: normalizedHeight))
    }
}

// MARK: -

private class LinkPreviewViewAdapterSent: LinkPreviewViewAdapter {

    let state: LinkPreviewState

    init(state: LinkPreviewState) {
        self.state = state
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .horizontal,
                               alignment: .center,
                               spacing: LinkPreviewView.sentNonHeroHSpacing,
                               layoutMargins: LinkPreviewView.sentNonHeroLayoutMargins)
    }

    var textStackConfig: ManualStackView.Config {
        return ManualStackView.Config(axis: .vertical,
                                      alignment: .center,
                                      spacing: LinkPreviewView.sentVSpacing,
                                      layoutMargins: .zero)
    }

    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement) {

        linkPreviewView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray02

        var rootStackSubviews = [UIView]()

        if state.hasLoadedImage {
            let linkPreviewImageView = linkPreviewView.linkPreviewImageView
            if let imageView = linkPreviewImageView.configure(state: state) {
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                rootStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                rootStackSubviews.append(UIView.transparentSpacer())
            }
        }

        let textStack = linkPreviewView.textStack
        configureSentTextStack(linkPreviewView: linkPreviewView,
                               state: state,
                               textStack: textStack,
                               textStackConfig: textStackConfig,
                               cellMeasurement: cellMeasurement)
        rootStackSubviews.append(textStack)

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: LinkPreviewView.measurementKey_rootStack,
                                  subviews: rootStackSubviews)
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        var maxLabelWidth = (maxWidth -
                                (textStackConfig.layoutMargins.totalWidth +
                                    rootStackConfig.layoutMargins.totalWidth))

        var rootStackSubviewInfos = [ManualStackSubviewInfo]()
        if state.hasLoadedImage {
            let imageSize = LinkPreviewView.sentNonHeroImageSize
            rootStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxLabelWidth -= imageSize + rootStackConfig.spacing
        }

        maxLabelWidth = max(0, maxLabelWidth)

        let textStackSize = measureSentTextStack(state: state,
                                                 textStackConfig: textStackConfig,
                                                 measurementBuilder: measurementBuilder,
                                                 maxLabelWidth: maxLabelWidth)
        rootStackSubviewInfos.append(textStackSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: LinkPreviewView.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos)
        return rootStackMeasurement.measuredSize
    }
}

// MARK: -

private class LinkPreviewViewAdapterSentWithDescription: LinkPreviewViewAdapter {

    let state: LinkPreviewState

    init(state: LinkPreviewState) {
        self.state = state
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(axis: .vertical,
                               alignment: .fill,
                               spacing: LinkPreviewView.sentVSpacing,
                               layoutMargins: LinkPreviewView.sentNonHeroLayoutMargins)
    }

    var titleStackConfig: ManualStackView.Config {
        return ManualStackView.Config(axis: .horizontal,
                                      alignment: .center,
                                      spacing: LinkPreviewView.sentNonHeroHSpacing,
                                      layoutMargins: UIEdgeInsets(top: 0,
                                                                  left: 0,
                                                                  bottom: LinkPreviewView.sentVSpacing,
                                                                  right: 0))
    }

    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement) {

        linkPreviewView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray02

        var titleStackSubviews = [UIView]()

        if state.hasLoadedImage {
            let linkPreviewImageView = linkPreviewView.linkPreviewImageView
            if let imageView = linkPreviewImageView.configure(state: state) {
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                titleStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                titleStackSubviews.append(UIView.transparentSpacer())
            }
        }

        if let titleLabel = sentTitleLabel(state: state) {
            titleStackSubviews.append(titleLabel)
        } else {
            owsFailDebug("Text stack required")
        }

        var rootStackSubviews = [UIView]()

        let titleStack = linkPreviewView.titleStack
        titleStack.configure(config: titleStackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: LinkPreviewView.measurementKey_titleStack,
                            subviews: titleStackSubviews)
        rootStackSubviews.append(titleStack)

        if let descriptionLabel = sentDescriptionLabel(state: state) {
            rootStackSubviews.append(descriptionLabel)
        } else {
            owsFailDebug("Description label required")
        }

        let domainLabel = sentDomainLabel(state: state)
        rootStackSubviews.append(domainLabel)

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: LinkPreviewView.measurementKey_rootStack,
                                  subviews: rootStackSubviews)
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        var maxRootLabelWidth = (maxWidth -
                                    (titleStackConfig.layoutMargins.totalWidth +
                                        rootStackConfig.layoutMargins.totalWidth))
        maxRootLabelWidth = max(0, maxRootLabelWidth)

        var maxTitleLabelWidth = maxRootLabelWidth

        var titleStackSubviewInfos = [ManualStackSubviewInfo]()
        if state.hasLoadedImage {
            let imageSize = LinkPreviewView.sentNonHeroImageSize
            titleStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxTitleLabelWidth -= imageSize + rootStackConfig.spacing
        }

        maxTitleLabelWidth = max(0, maxTitleLabelWidth)

        if let labelConfig = sentTitleLabelConfig(state: state) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxTitleLabelWidth)
            titleStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        } else {
            owsFailDebug("Text stack required")
        }

        var rootStackSubviewInfos = [ManualStackSubviewInfo]()

        let titleStackMeasurement = ManualStackView.measure(config: titleStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: LinkPreviewView.measurementKey_titleStack,
                                                           subviewInfos: titleStackSubviewInfos)
        rootStackSubviewInfos.append(titleStackMeasurement.measuredSize.asManualSubviewInfo)

        if let labelConfig = sentDescriptionLabelConfig(state: state) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxRootLabelWidth)
            rootStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        } else {
            owsFailDebug("Description label required")
        }

        do {
            let labelConfig = sentDomainLabelConfig(state: state)
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxRootLabelWidth)
            rootStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        }

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: LinkPreviewView.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos)
        return rootStackMeasurement.measuredSize
    }
}

// MARK: -

private class LinkPreviewImageView: CVImageView {
    fileprivate enum Rounding: UInt {
        case standard
        case asymmetrical
        case circular
    }

    fileprivate var rounding: Rounding = .standard {
        didSet {
            if rounding == .asymmetrical {
                layer.mask = asymmetricCornerMask
            } else {
                layer.mask = nil
            }
            updateMaskLayer()
        }
    }

    fileprivate var isHero = false {
        didSet {
            updateMaskLayer()
        }
    }

    // We only need to use a more complicated corner mask if we're
    // drawing asymmetric corners. This is an exceptional case to match
    // the input toolbar curve.
    private let asymmetricCornerMask = CAShapeLayer()

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    func reset() {
        rounding = .standard
        isHero = false
    }

    override var bounds: CGRect {
        didSet {
            updateMaskLayer()
        }
    }

    override var frame: CGRect {
        didSet {
            updateMaskLayer()
        }
    }

    override var center: CGPoint {
        didSet {
            updateMaskLayer()
        }
    }

    private func updateMaskLayer() {
        let layerBounds = self.bounds
        let bigRounding: CGFloat = 14
        let smallRounding: CGFloat = 6

        switch rounding {
        case .standard:
            layer.cornerRadius = smallRounding
            layer.maskedCorners = isHero ? .top : .all
        case .circular:
            layer.cornerRadius = bounds.size.smallerAxis / 2
            layer.maskedCorners = .all
        case .asymmetrical:
            // This uses a more expensive layer mask to clip corners
            // with different radii.
            // This should only be used in the input toolbar so perf is
            // less of a concern here.
            owsAssertDebug(!isHero, "Link preview drafts never use hero images")

            let upperLeft = CGPoint(x: 0, y: 0)
            let upperRight = CGPoint(x: layerBounds.size.width, y: 0)
            let lowerRight = CGPoint(x: layerBounds.size.width, y: layerBounds.size.height)
            let lowerLeft = CGPoint(x: 0, y: layerBounds.size.height)

            let upperLeftRounding: CGFloat = CurrentAppContext().isRTL ? smallRounding : bigRounding
            let upperRightRounding: CGFloat = CurrentAppContext().isRTL ? bigRounding : smallRounding
            let lowerRightRounding = smallRounding
            let lowerLeftRounding = smallRounding

            let path = UIBezierPath()

            // It's sufficient to "draw" the rounded corners and not the edges that connect them.
            path.addArc(withCenter: upperLeft.offsetBy(dx: +upperLeftRounding).offsetBy(dy: +upperLeftRounding),
                        radius: upperLeftRounding,
                        startAngle: CGFloat.pi * 1.0,
                        endAngle: CGFloat.pi * 1.5,
                        clockwise: true)

            path.addArc(withCenter: upperRight.offsetBy(dx: -upperRightRounding).offsetBy(dy: +upperRightRounding),
                        radius: upperRightRounding,
                        startAngle: CGFloat.pi * 1.5,
                        endAngle: CGFloat.pi * 0.0,
                        clockwise: true)

            path.addArc(withCenter: lowerRight.offsetBy(dx: -lowerRightRounding).offsetBy(dy: -lowerRightRounding),
                        radius: lowerRightRounding,
                        startAngle: CGFloat.pi * 0.0,
                        endAngle: CGFloat.pi * 0.5,
                        clockwise: true)

            path.addArc(withCenter: lowerLeft.offsetBy(dx: +lowerLeftRounding).offsetBy(dy: -lowerLeftRounding),
                        radius: lowerLeftRounding,
                        startAngle: CGFloat.pi * 0.5,
                        endAngle: CGFloat.pi * 1.0,
                        clockwise: true)

            asymmetricCornerMask.path = path.cgPath
        }
    }

    // MARK: -

    func configureForDraft(state: LinkPreviewState,
                           hasAsymmetricalRounding: Bool) -> UIImageView? {
        guard state.isLoaded() else {
            owsFailDebug("State not loaded.")
            return nil
        }
        guard state.imageState() == .loaded else {
            return nil
        }
        guard let image = state.image() else {
            owsFailDebug("Could not load image.")
            return nil
        }
        self.rounding = hasAsymmetricalRounding ? .asymmetrical : .standard
        self.image = image
        return self
    }

    func configure(state: LinkPreviewState,
                   rounding roundingParam: LinkPreviewImageView.Rounding? = nil) -> UIImageView? {
        guard state.isLoaded() else {
            owsFailDebug("State not loaded.")
            return nil
        }
        guard state.imageState() == .loaded else {
            return nil
        }
        guard let image = state.image() else {
            owsFailDebug("Could not load image.")
            return nil
        }
        self.rounding = roundingParam ?? .standard
        self.image = image
        self.isHero = LinkPreviewView.sentIsHero(state: state)
        return self
    }
}

// MARK: -

public extension CGPoint {
    func offsetBy(dx: CGFloat) -> CGPoint {
        return CGPoint(x: x + dx, y: y)
    }

    func offsetBy(dy: CGFloat) -> CGPoint {
        return CGPoint(x: x, y: y + dy)
    }
}

// MARK: -

public extension ManualLayoutView {
    func addSubviewAsBottomStroke(_ subview: UIView,
                                  layoutMargins: UIEdgeInsets = .zero) {
        addSubview(subview) { view in
            var subviewFrame = view.bounds.inset(by: layoutMargins)
            subviewFrame.size.height = CGHairlineWidth()
            subviewFrame.y = view.bounds.height - (subviewFrame.height +
                                                    layoutMargins.bottom)
            subview.frame = subviewFrame
        }
    }
}
