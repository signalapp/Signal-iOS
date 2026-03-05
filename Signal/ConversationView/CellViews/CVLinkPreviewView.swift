//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Component designed to show link preview in a message bubble.
class CVLinkPreviewView: ManualStackViewWithLayer {

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var linkPreview: LinkPreviewState?
    private var configurationSize: CGSize?
    private var shouldReconfigureForBounds = false

    fileprivate let textStack = ManualStackView(name: "textStack")

    fileprivate let linkPreviewImageView = CVLinkPreviewImageView()

    init() {
        super.init(name: "CVLinkPreviewView")

        layer.masksToBounds = true
        layer.cornerRadius = 10
    }

    func configureForRendering(
        linkPreview: LinkPreviewState,
        isIncoming: Bool,
        cellMeasurement: CVCellMeasurement,
    ) {
        self.linkPreview = linkPreview

        guard let conversationStyle = linkPreview.conversationStyle else {
            owsFailDebug("ConversationStyle not set")
            return
        }

        // Background is always the same for all link previews.
        backgroundColor = switch (conversationStyle.hasWallpaper, isIncoming) {
        case (true, true): UIColor.Signal.MaterialBase.fillTertiary
        case (_, true): UIColor.Signal.LightBase.fillTertiary
        case (_, false): UIColor.Signal.ColorBase.fillTertiary
        }

        // Layout varies based on link preview type.
        let adapter = Self.adapter(for: linkPreview, isIncoming: isIncoming)
        adapter.configureForRendering(
            linkPreviewView: self,
            cellMeasurement: cellMeasurement,
        )
    }

    private static func adapter(
        for linkPreview: LinkPreviewState,
        isIncoming: Bool,
    ) -> CVLinkPreviewViewAdapter {
        if linkPreview.isGroupInviteLink || linkPreview.isCallLink {
            return CVLinkPreviewViewAdapterSignalLink(linkPreview: linkPreview, isIncoming: isIncoming)
        }
        if linkPreview.hasLoadedImageOrBlurHash, sentIsHero(linkPreview: linkPreview) {
            return CVLinkPreviewViewAdapterLarge(linkPreview: linkPreview, isIncoming: isIncoming)
        }
        return CVLinkPreviewViewAdapterCompact(linkPreview: linkPreview, isIncoming: isIncoming)
    }

    fileprivate static func sentIsHero(linkPreview: LinkPreviewState) -> Bool {
        if isSticker(linkPreview: linkPreview) || linkPreview.isGroupInviteLink {
            return false
        }
        guard let heroWidthPoints = linkPreview.conversationStyle?.maxMessageWidth else {
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
            3.0: 2.3333,
        ]
        let scalingFactor = heroScalingFactors[UIScreen.main.scale] ?? {
            // Oh neat a new device! Might want to add it.
            owsFailDebug("Unrecognized device scale")
            return 2.0
        }()
        let minimumHeroWidth = heroWidthPoints * scalingFactor
        let minimumHeroHeight = minimumHeroWidth * 0.33

        let widthSatisfied = linkPreview.imagePixelSize.width >= minimumHeroWidth
        let heightSatisfied = linkPreview.imagePixelSize.height >= minimumHeroHeight
        return widthSatisfied && heightSatisfied
    }

    private static func isSticker(linkPreview: LinkPreviewState) -> Bool {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Link preview is missing url.")
            return false
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Could not parse URL.")
            return false
        }
        return StickerPackInfo.isStickerPackShare(url)
    }

    // MARK: Measurement

    static func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        linkPreview: LinkPreviewState,
    ) -> CGSize {
        // `isIncoming` doesn't matter for size measurement
        let adapter = Self.adapter(for: linkPreview, isIncoming: false)
        let size = adapter.measure(
            maxWidth: maxWidth,
            measurementBuilder: measurementBuilder,
        )
        if size.width > maxWidth {
            owsFailDebug("size.width: \(size.width) > maxWidth: \(maxWidth)")
        }
        return size
    }

    override func reset() {
        super.reset()

        textStack.reset()
        textStack.removeFromSuperview()

        linkPreviewImageView.reset()
        linkPreviewImageView.removeFromSuperview()
    }
}

// MARK: -

private class CVLinkPreviewViewAdapter {

    let linkPreview: LinkPreviewState
    let isIncoming: Bool

    init(linkPreview: LinkPreviewState, isIncoming: Bool) {
        self.linkPreview = linkPreview
        self.isIncoming = isIncoming
    }

    // MARK: Root Stack

    private static var measurementKey_rootStack: String { "LinkPreviewView.measurementKey_rootStack" }

    final func configureForRendering(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) {
        let rootStackSubviews = rootStackSubviews(
            linkPreviewView: linkPreviewView,
            cellMeasurement: cellMeasurement,
        )
        linkPreviewView.configure(
            config: rootStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_rootStack,
            subviews: rootStackSubviews,
        )
    }

    final func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> CGSize {
        ManualStackView.measure(
            config: rootStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_rootStack,
            subviewInfos: rootStackSubviewInfos(maxWidth: maxWidth, measurementBuilder: measurementBuilder),
            maxWidth: maxWidth,
        ).measuredSize
    }

    fileprivate static let sentNonHeroImageSize: CGFloat = 64

    // Default config is a horizontal stack designed to show a small image followed by vertical stack of text.
    //
    // Subclasses can override for different link layout.
    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .horizontal,
            alignment: .top,
            spacing: 12,
            layoutMargins: UIEdgeInsets(margin: 10),
        )
    }

    // Subclasses must override to return measured size for root stack's subviews.
    func rootStackSubviewInfos(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> [ManualStackSubviewInfo] { [] }

    // Subclasses must override to return configured root stack's subviews.
    func rootStackSubviews(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) -> [UIView] { [] }

    // MARK: Text stack

    private static var measurementKey_textStack: String { "LinkPreviewView.measurementKey_textStack" }

    // Default is a simple vertical text stack.
    //
    // Subclasses can override for a different text stack layout.
    var textStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .leading,
            spacing: 4,
            layoutMargins: .zero,
        )
    }

    // Measures total size of text stack in the link preview
    // based on measurements provided by subclasses via `textStackSubviewInfos(maxWidth:)`.
    final func measureTextStack(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> CGSize {
        let subviewInfos = textStackSubviewInfos(maxWidth: maxWidth)
        let measurement = ManualStackView.measure(
            config: textStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_textStack,
            subviewInfos: subviewInfos,
        )
        return measurement.measuredSize
    }

    // Configures text stack using configured subviews (text labels)
    // provided by subclasses via `textStackSubviews()`.
    final func configureTextStack(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) -> UIView {
        let textStack = linkPreviewView.textStack
        textStack.configure(
            config: textStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_textStack,
            subviews: textStackSubviews(),
        )
        return textStack
    }

    // Customization point for subclasses.
    //
    // Default implementation measures for all three possible labels:
    // Title, Description, Domain name.
    func textStackSubviewInfos(maxWidth: CGFloat) -> [ManualStackSubviewInfo] {
        var subviewInfos = [ManualStackSubviewInfo]()

        if let labelConfig = sentTitleLabelConfig() {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxWidth)
            subviewInfos.append(labelSize.asManualSubviewInfo)
        }
        if let labelConfig = sentDescriptionLabelConfig() {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxWidth)
            subviewInfos.append(labelSize.asManualSubviewInfo)
        }
        let labelConfig = sentDomainLabelConfig()
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxWidth)
        subviewInfos.append(labelSize.asManualSubviewInfo)

        return subviewInfos
    }

    // Customization point for subclasses.
    //
    // Default implementation returns all three possible labels:
    // Title, Description, Domain name.
    func textStackSubviews() -> [CVLabel] {
        var subviews = [CVLabel]()

        if let titleLabel = sentTitleLabel() {
            subviews.append(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel() {
            subviews.append(descriptionLabel)
        }
        let domainLabel = sentDomainLabel()
        subviews.append(domainLabel)

        return subviews
    }

    // MARK: Text styling

    final func sentTitleLabel() -> CVLabel? {
        guard let config = sentTitleLabelConfig() else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    final func sentTitleLabelConfig() -> CVLabelConfig? {
        guard let text = linkPreview.title else {
            return nil
        }
        let textColor: UIColor = isIncoming ? .Signal.label : .Signal.ColorBase.labelInverted
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeSubheadline.semibold(),
            textColor: textColor,
            numberOfLines: 2,
            lineBreakMode: .byTruncatingTail,
        )
    }

    final func sentDescriptionLabel() -> CVLabel? {
        guard let config = sentDescriptionLabelConfig() else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    final func sentDescriptionLabelConfig() -> CVLabelConfig? {
        guard let text = linkPreview.previewDescription else { return nil }
        let textColor: UIColor = isIncoming ? .Signal.secondaryLabel : .Signal.ColorBase.labelInvertedSecondary
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeFootnote,
            textColor: textColor,
            numberOfLines: 3,
            lineBreakMode: .byTruncatingTail,
        )
    }

    final func sentDomainLabel() -> CVLabel {
        let config = sentDomainLabelConfig()
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    final func sentDomainLabelConfig() -> CVLabelConfig {
        var labelText: String
        if let displayDomain = linkPreview.displayDomain?.nilIfEmpty {
            labelText = displayDomain.lowercased()
        } else {
            labelText = OWSLocalizedString(
                "LINK_PREVIEW_UNKNOWN_DOMAIN",
                comment: "Label for link previews with an unknown host.",
            ).uppercased()
        }
        if let date = linkPreview.date {
            labelText.append(" ⋅ \(CVLinkPreviewView.dateFormatter.string(from: date))")
        }
        let textColor: UIColor = isIncoming ? .Signal.secondaryLabel : .Signal.ColorBase.labelInvertedSecondary
        return CVLabelConfig.unstyledText(
            labelText,
            font: UIFont.dynamicTypeCaption1,
            textColor: textColor,
            lineBreakMode: .byTruncatingTail,
        )
    }
}

// MARK: -

// Does not have domain name. Image is round.
private class CVLinkPreviewViewAdapterSignalLink: CVLinkPreviewViewAdapter {

    override func rootStackSubviewInfos(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> [ManualStackSubviewInfo] {
        var rootStackSubviewInfos = [ManualStackSubviewInfo]()

        var maxLabelWidth = (maxWidth - (
            textStackConfig.layoutMargins.totalWidth + rootStackConfig.layoutMargins.totalWidth
        ))

        if linkPreview.hasLoadedImageOrBlurHash {
            let imageSize = Self.sentNonHeroImageSize
            rootStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxLabelWidth -= imageSize + rootStackConfig.spacing
        }

        maxLabelWidth = max(0, maxLabelWidth)

        let textStackSize = measureTextStack(
            maxWidth: maxLabelWidth,
            measurementBuilder: measurementBuilder,
        )
        rootStackSubviewInfos.append(textStackSize.asManualSubviewInfo)

        return rootStackSubviewInfos
    }

    override func rootStackSubviews(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) -> [UIView] {
        var rootStackSubviews = [UIView]()

        if linkPreview.hasLoadedImageOrBlurHash {
            let linkPreviewImageView = linkPreviewView.linkPreviewImageView
            if let imageView = linkPreviewImageView.configure(linkPreview: linkPreview, cornerStyle: .capsule) {
                imageView.clipsToBounds = true
                rootStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                rootStackSubviews.append(UIView.transparentSpacer())
            }
        }

        let textStack = configureTextStack(
            linkPreviewView: linkPreviewView,
            cellMeasurement: cellMeasurement,
        )
        rootStackSubviews.append(textStack)

        return rootStackSubviews
    }
}

// MARK: -

// Large full-width image with vertical text stack below.
private class CVLinkPreviewViewAdapterLarge: CVLinkPreviewViewAdapter {

    // Vertical stack.
    override var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .fill,
            spacing: 0,
            layoutMargins: .zero,
        )
    }

    // Increased margins around text over default implementation.
    override var textStackConfig: ManualStackView.Config {
        let config = super.textStackConfig
        let insets = UIEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 4)
        return ManualStackView.Config(
            axis: config.axis,
            alignment: config.alignment,
            spacing: config.spacing,
            layoutMargins: insets,
        )
    }

    override func rootStackSubviewInfos(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> [ManualStackSubviewInfo] {
        var rootStackSubviewInfos = [ManualStackSubviewInfo]()

        let heroImageSize = sentHeroImageSize(maxWidth: maxWidth)
        rootStackSubviewInfos.append(heroImageSize.asManualSubviewInfo)

        var maxLabelWidth = (maxWidth - (
            textStackConfig.layoutMargins.totalWidth + rootStackConfig.layoutMargins.totalWidth
        ))
        maxLabelWidth = max(0, maxLabelWidth)

        let textStackSize = measureTextStack(
            maxWidth: maxLabelWidth,
            measurementBuilder: measurementBuilder,
        )
        rootStackSubviewInfos.append(textStackSize.asManualSubviewInfo)

        return rootStackSubviewInfos
    }

    override func rootStackSubviews(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) -> [UIView] {
        var rootStackSubviews = [UIView]()

        let linkPreviewImageView = linkPreviewView.linkPreviewImageView
        if let imageView = linkPreviewImageView.configure(linkPreview: linkPreview, cornerStyle: .square) {
            imageView.clipsToBounds = true
            rootStackSubviews.append(imageView)
        } else {
            owsFailDebug("Could not load image.")
            rootStackSubviews.append(UIView.transparentSpacer())
        }

        let textStack = configureTextStack(
            linkPreviewView: linkPreviewView,
            cellMeasurement: cellMeasurement,
        )
        rootStackSubviews.append(textStack)

        return rootStackSubviews
    }

    private func sentHeroImageSize(maxWidth: CGFloat) -> CGSize {
        guard let conversationStyle = linkPreview.conversationStyle else {
            owsFailDebug("Missing conversationStyle.")
            return .zero
        }

        let imageHeightWidthRatio = (linkPreview.imagePixelSize.height / linkPreview.imagePixelSize.width)
        let maxMessageWidth = min(maxWidth, conversationStyle.maxMessageWidth)

        let minImageHeight: CGFloat = maxMessageWidth * 0.5
        let maxImageHeight: CGFloat = maxMessageWidth
        let rawImageHeight = maxMessageWidth * imageHeightWidthRatio

        let normalizedHeight: CGFloat = min(maxImageHeight, max(minImageHeight, rawImageHeight))
        return CGSize.ceil(CGSize(width: maxMessageWidth, height: normalizedHeight))
    }
}

// MARK: -

// Compact thumbnail along the leading edge followed by default vertical text stack.
private class CVLinkPreviewViewAdapterCompact: CVLinkPreviewViewAdapter {

    override func rootStackSubviewInfos(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> [ManualStackSubviewInfo] {
        var rootStackSubviewInfos = [ManualStackSubviewInfo]()

        var maxLabelWidth = (maxWidth - (
            textStackConfig.layoutMargins.totalWidth + rootStackConfig.layoutMargins.totalWidth
        ))

        if linkPreview.hasLoadedImageOrBlurHash {
            let imageSize = Self.sentNonHeroImageSize
            rootStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxLabelWidth -= imageSize + rootStackConfig.spacing
        }

        maxLabelWidth = max(0, maxLabelWidth)

        let textStackSize = measureTextStack(
            maxWidth: maxLabelWidth,
            measurementBuilder: measurementBuilder,
        )
        rootStackSubviewInfos.append(textStackSize.asManualSubviewInfo)

        return rootStackSubviewInfos
    }

    override func rootStackSubviews(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) -> [UIView] {
        var rootStackSubviews = [UIView]()

        if linkPreview.hasLoadedImageOrBlurHash {
            let linkPreviewImageView = linkPreviewView.linkPreviewImageView
            if let imageView = linkPreviewImageView.configure(linkPreview: linkPreview, cornerStyle: .rounded(radius: 6)) {
                imageView.clipsToBounds = true
                rootStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                rootStackSubviews.append(UIView.transparentSpacer())
            }
        }

        let textStack = configureTextStack(
            linkPreviewView: linkPreviewView,
            cellMeasurement: cellMeasurement,
        )
        rootStackSubviews.append(textStack)

        return rootStackSubviews
    }
}

// MARK: -

private class CVLinkPreviewImageView: ManualLayoutViewWithLayer {

    enum CornerStyle {
        case square
        case rounded(radius: CGFloat)
        case capsule
    }

    var cornerStyle: CornerStyle = .square {
        didSet {
            updateCornerRounding()
        }
    }

    var isHero = false

    private let imageView = CVImageView()
    private let iconView = CVImageView()

    private static let configurationIdCounter = AtomicUInt(0, lock: .sharedGlobal)
    private var configurationId: UInt = 0

    init() {
        super.init(name: "LinkPreviewImageView")

        addSubviewToFillSuperviewEdges(imageView)
        addSubviewToCenterOnSuperview(iconView, size: .square(36))
        addDefaultLayoutBlock()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addDefaultLayoutBlock() {
        addLayoutBlock { view in
            guard let view = view as? CVLinkPreviewImageView else { return }
            view.updateCornerRounding()
        }
    }

    override func reset() {
        super.reset()

        imageView.reset()
        iconView.reset()

        cornerStyle = .square
        isHero = false
        configurationId = 0
    }

    private func updateCornerRounding() {
        switch cornerStyle {
        case .square:
            layer.cornerRadius = 0

        case .rounded(let radius):
            layer.cornerRadius = radius

        case .capsule:
            layer.cornerRadius = bounds.size.smallerAxis / 2
        }
    }

    static let mediaCache = LRUCache<LinkPreviewImageCacheKey, UIImage>(
        maxSize: 2,
        shouldEvacuateInBackground: true,
    )

    func configure(linkPreview: LinkPreviewState, cornerStyle: CornerStyle) -> UIView? {
        switch linkPreview.imageState {
        case .loaded:
            break
        case let .loading(blurHash) where blurHash != nil:
            break
        case let .failed(blurHash) where blurHash != nil:
            if let icon = UIImage(named: "photo-slash-36") {
                iconView.tintColor = Theme.primaryTextColor.withAlphaComponent(0.6)
                iconView.image = icon
            }
        default:
            return nil
        }
        imageView.contentMode = .scaleAspectFill
        if imageView.superview == nil {
            addSubviewToFillSuperviewEdges(imageView)
            addSubviewToCenterOnSuperview(iconView, size: .square(36))
        }
        self.cornerStyle = cornerStyle
        isHero = CVLinkPreviewView.sentIsHero(linkPreview: linkPreview)
        let configurationId = Self.configurationIdCounter.increment()
        self.configurationId = configurationId
        let thumbnailQuality: AttachmentThumbnailQuality = isHero ? .medium : .small

        if
            let cacheKey = linkPreview.imageCacheKey(thumbnailQuality: thumbnailQuality),
            let image = Self.mediaCache.get(key: cacheKey)
        {
            imageView.image = image
        } else {
            linkPreview.imageAsync(thumbnailQuality: thumbnailQuality) { [weak self] image in
                DispatchMainThreadSafe {
                    guard let self else { return }
                    guard self.configurationId == configurationId else { return }
                    self.imageView.image = image
                    if let cacheKey = linkPreview.imageCacheKey(thumbnailQuality: thumbnailQuality) {
                        Self.mediaCache.set(key: cacheKey, value: image)
                    }
                }
            }
        }
        return self
    }
}
