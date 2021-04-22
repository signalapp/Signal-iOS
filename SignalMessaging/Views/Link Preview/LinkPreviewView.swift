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

//    @objc
//    public var state: LinkPreviewState? {
//        didSet {
//            AssertIsOnMainThread()
//            updateContents()
//        }
//    }
//
//    @objc
//    public var hasAsymmetricalRounding: Bool = false {
//        didSet {
//            AssertIsOnMainThread()
//            owsAssertDebug(isDraft)
//
//            if hasAsymmetricalRounding != oldValue {
//                updateContents()
//            }
//        }
//    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init(name: String, arrangedSubviews: [UIView] = []) {
        notImplemented()
    }

//    private var cancelButton: UIButton?
//    private weak var heroImageView: UIView?
//    private weak var sentBodyView: UIView?

    fileprivate let rightStack = ManualStackView(name: "rightStack")
    fileprivate let textStack = ManualStackView(name: "textStack")

    fileprivate let titleLabel = CVLabel()
    fileprivate let descriptionLabel = CVLabel()
    fileprivate let displayDomainLabel = CVLabel()

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

    private func createGroupLinkContents() {
        guard let state = state else {
            owsFailDebug("Invalid state")
            return
        }

        self.addBackgroundView(withBackgroundColor: Theme.secondaryBackgroundColor)

        self.layoutMargins = .zero
        self.axis = .horizontal
        self.isLayoutMarginsRelativeArrangement = true
        self.layoutMargins = Self.sentNonHeroLayoutMargins
        self.spacing = Self.sentNonHeroHSpacing

        if let imageView = createImageView(state: state, rounding: .circular) {
            imageView.autoSetDimensions(to: CGSize(square: Self.sentNonHeroImageSize))
            imageView.contentMode = .scaleAspectFill
            imageView.setContentHuggingHigh()
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            addArrangedSubview(imageView)
        }

        let textStack = createGroupLinkTextStack(state: state)
        addArrangedSubview(textStack)

        sentBodyView = self
    }

    private func createGroupLinkTextStack(state: LinkPreviewState) -> UIStackView {
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = Self.sentVSpacing

        if let titleLabel = sentTitleLabel(state: state) {
            textStack.addArrangedSubview(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(state: state) {
            textStack.addArrangedSubview(descriptionLabel)
        }

        return textStack
    }

    private static func sentHeroImageSize(state: LinkPreviewState,
                                          conversationStyle: ConversationStyle) -> CGSize {

        let imageHeightWidthRatio = (state.imagePixelSize.height / state.imagePixelSize.width)
        let maxMessageWidth = conversationStyle.maxMessageWidth

        let minImageHeight: CGFloat = maxMessageWidth * 0.5
        let maxImageHeight: CGFloat = maxMessageWidth
        let rawImageHeight = maxMessageWidth * imageHeightWidthRatio

        let normalizedHeight: CGFloat = min(maxImageHeight, max(minImageHeight, rawImageHeight))
        return CGSizeCeil(CGSize(width: maxMessageWidth, height: normalizedHeight))
    }

    private func createHeroSentContents(state: LinkPreviewState,
                                        conversationStyle: ConversationStyle,
                                        imageView: UIImageView) {
        self.layoutMargins = .zero
        self.axis = .vertical
        self.alignment = .fill

        let heroImageSize = Self.sentHeroImageSize(state: state,
                                                   conversationStyle: conversationStyle)
        imageView.autoSetDimensions(to: heroImageSize)
        imageView.contentMode = .scaleAspectFill
        imageView.setContentHuggingHigh()
        imageView.setCompressionResistanceHigh()
        imageView.clipsToBounds = true
        // TODO: Cropping, stroke.
        addArrangedSubview(imageView)

        let textStack = createSentTextStack(state: state)
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.layoutMargins = Self.sentHeroLayoutMargins
        addArrangedSubview(textStack)

        heroImageView = imageView
        sentBodyView = textStack
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

    private static let sentTitleFontSizePoints: CGFloat = 17
    private static let sentDomainFontSizePoints: CGFloat = 12
    private static let sentVSpacing: CGFloat = 4

    // The "sent message" mode has two submodes: "hero" and "non-hero".
    private static let sentNonHeroHMargin: CGFloat = 12
    private static let sentNonHeroVMargin: CGFloat = 12
    private static var sentNonHeroLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: sentNonHeroVMargin,
                     left: sentNonHeroHMargin,
                     bottom: sentNonHeroVMargin,
                     right: sentNonHeroHMargin)
    }

    private static let sentNonHeroImageSize: CGFloat = 64
    private static let sentNonHeroHSpacing: CGFloat = 8

    private static let sentHeroHMargin: CGFloat = 12
    private static let sentHeroVMargin: CGFloat = 12
    private static var sentHeroLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: sentHeroVMargin,
                     left: sentHeroHMargin,
                     bottom: sentHeroVMargin,
                     right: sentHeroHMargin)
    }

    private static func sentIsHero(state: LinkPreviewState) -> Bool {
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

    private static let sentTitleLineCount: Int = 2
    private static let sentDescriptionLineCount: Int = 3

    private func sentTitleLabel(state: LinkPreviewState) -> UILabel? {
        guard let config = Self.sentTitleLabelConfig(state: state) else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    private static func sentTitleLabelConfig(state: LinkPreviewState) -> CVLabelConfig? {
        guard let text = state.title() else {
            return nil
        }
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeSubheadline.ows_semibold,
                             textColor: Theme.primaryTextColor,
                             numberOfLines: sentTitleLineCount,
                             lineBreakMode: .byTruncatingTail)
    }

    private func sentDescriptionLabel(state: LinkPreviewState) -> UILabel? {
        guard let config = Self.sentDescriptionLabelConfig(state: state) else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
   }

    private static func sentDescriptionLabelConfig(state: LinkPreviewState) -> CVLabelConfig? {
        guard let text = state.previewDescription() else { return nil }
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeSubheadline,
                             textColor: Theme.primaryTextColor,
                             numberOfLines: sentDescriptionLineCount,
                             lineBreakMode: .byTruncatingTail)
    }

    private func sentDomainLabel(state: LinkPreviewState) -> UILabel {
        let label = CVLabel()
        Self.sentDomainLabelConfig(state: state).applyForRendering(label: label)
        return label
    }

    private static func sentDomainLabelConfig(state: LinkPreviewState) -> CVLabelConfig {
        var labelText: String
        if let displayDomain = state.displayDomain(),
           displayDomain.count > 0 {
            labelText = displayDomain.lowercased()
        } else {
            labelText = NSLocalizedString("LINK_PREVIEW_UNKNOWN_DOMAIN", comment: "Label for link previews with an unknown host.").uppercased()
        }
        if let date = state.date() {
            labelText.append(" ⋅ \(Self.dateFormatter.string(from: date))")
        }
        return CVLabelConfig(text: labelText,
                             font: UIFont.ows_dynamicTypeCaption1,
                             textColor: Theme.secondaryTextAndIconColor)
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

        rightStack.reset()
        textStack.reset()

        titleLabel.text = nil
        descriptionLabel.text = nil
        displayDomainLabel.text = nil

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
            if let imageView = buildDraftImageView(hasAsymmetricalRounding: hasAsymmetricalRounding) {
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

    private func buildDraftImageView(hasAsymmetricalRounding: Bool) -> UIImageView? {
        guard state.isLoaded() else {
            owsFailDebug("State not loaded.")
            return nil
        }
        guard state.imageState()  == .loaded else {
            return nil
        }
        guard let image = state.image() else {
            owsFailDebug("Could not load image.")
            return nil
        }
        let rounding: LinkPreviewImageView.Rounding = hasAsymmetricalRounding ? .asymmetrical : .standard
        let imageView = LinkPreviewImageView(rounding: rounding)
        imageView.image = image
        return imageView
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
}

// MARK: -

private class LinkPreviewViewAdapterSentHero: LinkPreviewViewAdapter {
}

// MARK: -

private class LinkPreviewViewAdapterSent: LinkPreviewViewAdapter {
}

// MARK: -

private class LinkPreviewViewAdapterSentWithDescription: LinkPreviewViewAdapter {
}

// MARK: -

private class LinkPreviewImageView: CVImageView {
    fileprivate enum Rounding: UInt {
        case standard
        case asymmetrical
        case circular
    }

    private let rounding: Rounding
    fileprivate var isHero = false

    // We only need to use a more complicated corner mask if we're
    // drawing asymmetric corners. This is an exceptional case to match
    // the input toolbar curve.
    private let asymmetricCornerMask = CAShapeLayer()

    init(rounding: Rounding) {
        self.rounding = rounding
        super.init(frame: .zero)

        if rounding == .asymmetrical {
            layer.mask = asymmetricCornerMask
        }
    }

    required init?(coder aDecoder: NSCoder) {
        self.rounding = .standard
        super.init(coder: aDecoder)
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
