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

    private var linkPreview: LinkPreviewSent?
    private var configurationSize: CGSize?
    private var shouldReconfigureForBounds = false

    fileprivate let textStack = ManualStackView(name: "textStack")

    fileprivate let titleLabel = CVLabel()
    fileprivate let descriptionLabel = CVLabel()
    fileprivate let displayDomainLabel = CVLabel()

    fileprivate let linkPreviewImageView = CVLinkPreviewImageView()

    init() {
        super.init(name: "CVLinkPreviewView")
    }

    func configureForRendering(
        linkPreview: LinkPreviewSent,
        cellMeasurement: CVCellMeasurement,
    ) {
        self.linkPreview = linkPreview
        let adapter = Self.adapter(for: linkPreview)
        adapter.configureForRendering(
            linkPreviewView: self,
            cellMeasurement: cellMeasurement,
        )
    }

    private static func adapter(for linkPreview: LinkPreviewSent) -> CVLinkPreviewViewAdapter {
        if linkPreview.isGroupInviteLink {
            return CVLinkPreviewViewAdapterGroupLink(linkPreview: linkPreview)
        }
        if linkPreview.hasLoadedImageOrBlurHash, Self.sentIsHero(linkPreview: linkPreview) {
            return CVLinkPreviewViewAdapterLarge(linkPreview: linkPreview)
        }
        return CVLinkPreviewViewAdapterCompact(linkPreview: linkPreview)
    }

    // Vertical specing between title, description and domain name.
    fileprivate static let textVSpacing: CGFloat = 4

    // The "sent message" mode has two submodes: "hero" and "non-hero".
    fileprivate static let sentNonHeroHMargin: CGFloat = 12
    fileprivate static let sentNonHeroVMargin: CGFloat = 12
    fileprivate static var sentNonHeroLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(
            top: sentNonHeroVMargin,
            left: sentNonHeroHMargin,
            bottom: sentNonHeroVMargin,
            right: sentNonHeroHMargin,
        )
    }

    fileprivate static let sentNonHeroImageSize: CGFloat = 64
    fileprivate static let sentNonHeroHSpacing: CGFloat = 8

    fileprivate static let sentTitleLineCount: Int = 2
    fileprivate static let sentDescriptionLineCount: Int = 3

    fileprivate static func sentIsHero(linkPreview: LinkPreviewSent) -> Bool {
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

    private static func isSticker(linkPreview: LinkPreviewSent) -> Bool {
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
        linkPreview: LinkPreviewSent,
        isDraft: Bool,
    ) -> CGSize {
        let adapter = Self.adapter(for: linkPreview)
        let size = adapter.measure(
            maxWidth: maxWidth,
            measurementBuilder: measurementBuilder,
            linkPreview: linkPreview,
        )
        if size.width > maxWidth {
            owsFailDebug("size.width: \(size.width) > maxWidth: \(maxWidth)")
        }
        return size
    }

    override func reset() {
        super.reset()

        textStack.reset()

        titleLabel.text = nil
        descriptionLabel.text = nil
        displayDomainLabel.text = nil

        linkPreviewImageView.reset()

        for subview in [
            textStack,
            titleLabel,
            descriptionLabel,
            displayDomainLabel,
            linkPreviewImageView,
        ] {
            subview.removeFromSuperview()
        }
    }
}

// MARK: -

private protocol CVLinkPreviewViewAdapter {

    func configureForRendering(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    )

    func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        linkPreview: LinkPreviewSent,
    ) -> CGSize
}

// MARK: -

extension CVLinkPreviewViewAdapter {

    fileprivate static var measurementKey_rootStack: String { "LinkPreviewView.measurementKey_rootStack" }
    fileprivate static var measurementKey_rightStack: String { "LinkPreviewView.measurementKey_rightStack" }
    fileprivate static var measurementKey_textStack: String { "LinkPreviewView.measurementKey_textStack" }
    fileprivate static var measurementKey_titleStack: String { "LinkPreviewView.measurementKey_titleStack" }

    func sentTitleLabel(linkPreview: LinkPreviewSent) -> UILabel? {
        guard let config = sentTitleLabelConfig(linkPreview: linkPreview) else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    func sentTitleLabelConfig(linkPreview: LinkPreviewSent) -> CVLabelConfig? {
        guard let text = linkPreview.title else {
            return nil
        }
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeSubheadline.semibold(),
            textColor: Theme.primaryTextColor,
            numberOfLines: CVLinkPreviewView.sentTitleLineCount,
            lineBreakMode: .byTruncatingTail,
        )
    }

    func sentDescriptionLabel(linkPreview: LinkPreviewSent) -> UILabel? {
        guard let config = sentDescriptionLabelConfig(linkPreview: linkPreview) else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    func sentDescriptionLabelConfig(linkPreview: LinkPreviewSent) -> CVLabelConfig? {
        guard let text = linkPreview.previewDescription else { return nil }
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeFootnote,
            textColor: Theme.secondaryTextAndIconColor,
            numberOfLines: CVLinkPreviewView.sentDescriptionLineCount,
            lineBreakMode: .byTruncatingTail,
        )
    }

    func sentDomainLabel(linkPreview: LinkPreviewSent) -> UILabel {
        let label = CVLabel()
        sentDomainLabelConfig(linkPreview: linkPreview).applyForRendering(label: label)
        return label
    }

    func sentDomainLabelConfig(linkPreview: LinkPreviewSent) -> CVLabelConfig {
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
        return CVLabelConfig.unstyledText(
            labelText,
            font: UIFont.dynamicTypeCaption1,
            textColor: Theme.secondaryTextAndIconColor,
            lineBreakMode: .byTruncatingTail,
        )
    }

    // Default text configuration:
    // Title
    // Description
    // Domain name
    func configureSentTextStack(
        linkPreviewView: CVLinkPreviewView,
        linkPreview: LinkPreviewSent,
        textStack: ManualStackView,
        textStackConfig: ManualStackView.Config,
        cellMeasurement: CVCellMeasurement,
    ) {
        var subviews = [UIView]()

        if let titleLabel = sentTitleLabel(linkPreview: linkPreview) {
            subviews.append(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(linkPreview: linkPreview) {
            subviews.append(descriptionLabel)
        }
        let domainLabel = sentDomainLabel(linkPreview: linkPreview)
        subviews.append(domainLabel)

        textStack.configure(
            config: textStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_textStack,
            subviews: subviews,
        )
    }

    func measureSentTextStack(
        linkPreview: LinkPreviewSent,
        textStackConfig: ManualStackView.Config,
        measurementBuilder: CVCellMeasurement.Builder,
        maxLabelWidth: CGFloat,
    ) -> CGSize {
        var subviewInfos = [ManualStackSubviewInfo]()

        if let labelConfig = sentTitleLabelConfig(linkPreview: linkPreview) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            subviewInfos.append(labelSize.asManualSubviewInfo)
        }
        if let labelConfig = sentDescriptionLabelConfig(linkPreview: linkPreview) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            subviewInfos.append(labelSize.asManualSubviewInfo)
        }
        let labelConfig = sentDomainLabelConfig(linkPreview: linkPreview)
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
        subviewInfos.append(labelSize.asManualSubviewInfo)

        let measurement = ManualStackView.measure(
            config: textStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_textStack,
            subviewInfos: subviewInfos,
        )
        return measurement.measuredSize
    }
}

// MARK: -

// Does not have domain name. Image is round.
private class CVLinkPreviewViewAdapterGroupLink: CVLinkPreviewViewAdapter {

    let linkPreview: LinkPreviewSent

    init(linkPreview: LinkPreviewSent) {
        self.linkPreview = linkPreview
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .horizontal,
            alignment: .fill,
            spacing: CVLinkPreviewView.sentNonHeroHSpacing,
            layoutMargins: CVLinkPreviewView.sentNonHeroLayoutMargins,
        )
    }

    var textStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .leading,
            spacing: CVLinkPreviewView.textVSpacing,
            layoutMargins: .zero,
        )
    }

    func configureForRendering(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) {
        var rootStackSubviews = [UIView]()

        if linkPreview.hasLoadedImageOrBlurHash {
            let linkPreviewImageView = linkPreviewView.linkPreviewImageView
            if let imageView = linkPreviewImageView.configure(linkPreview: linkPreview, rounding: .circular) {
                imageView.clipsToBounds = true
                rootStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                rootStackSubviews.append(UIView.transparentSpacer())
            }
        }

        let textStack = linkPreviewView.textStack
        var textStackSubviews = [UIView]()
        if let titleLabel = sentTitleLabel(linkPreview: linkPreview) {
            textStackSubviews.append(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(linkPreview: linkPreview) {
            textStackSubviews.append(descriptionLabel)
        }
        textStack.configure(
            config: textStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_textStack,
            subviews: textStackSubviews,
        )
        rootStackSubviews.append(textStack)

        linkPreviewView.configure(
            config: rootStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_rootStack,
            subviews: rootStackSubviews,
        )
    }

    func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        linkPreview: LinkPreviewSent,
    ) -> CGSize {
        var maxLabelWidth = (maxWidth - (
            textStackConfig.layoutMargins.totalWidth + rootStackConfig.layoutMargins.totalWidth
        ))

        var rootStackSubviewInfos = [ManualStackSubviewInfo]()
        if linkPreview.hasLoadedImageOrBlurHash {
            let imageSize = CVLinkPreviewView.sentNonHeroImageSize
            rootStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxLabelWidth -= imageSize + rootStackConfig.spacing
        }

        maxLabelWidth = max(0, maxLabelWidth)

        var textStackSubviewInfos = [ManualStackSubviewInfo]()
        if let labelConfig = sentTitleLabelConfig(linkPreview: linkPreview) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            textStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        }
        if let labelConfig = sentDescriptionLabelConfig(linkPreview: linkPreview) {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            textStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        }

        let textStackMeasurement = ManualStackView.measure(
            config: textStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_textStack,
            subviewInfos: textStackSubviewInfos,
        )
        rootStackSubviewInfos.append(textStackMeasurement.measuredSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(
            config: rootStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_rootStack,
            subviewInfos: rootStackSubviewInfos,
            maxWidth: maxWidth,
        )
        return rootStackMeasurement.measuredSize
    }
}

// MARK: -

// Large full-width image above text.
private class CVLinkPreviewViewAdapterLarge: CVLinkPreviewViewAdapter {

    let linkPreview: LinkPreviewSent

    init(linkPreview: LinkPreviewSent) {
        self.linkPreview = linkPreview
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .fill,
            spacing: 0,
            layoutMargins: .zero,
        )
    }

    var textStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .leading,
            spacing: CVLinkPreviewView.textVSpacing,
            layoutMargins: UIEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 4),
        )
    }

    func configureForRendering(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) {
        var rootStackSubviews = [UIView]()

        let linkPreviewImageView = linkPreviewView.linkPreviewImageView
        if let imageView = linkPreviewImageView.configure(linkPreview: linkPreview) {
            imageView.clipsToBounds = true
            rootStackSubviews.append(imageView)
        } else {
            owsFailDebug("Could not load image.")
            rootStackSubviews.append(UIView.transparentSpacer())
        }

        let textStack = linkPreviewView.textStack
        configureSentTextStack(
            linkPreviewView: linkPreviewView,
            linkPreview: linkPreview,
            textStack: textStack,
            textStackConfig: textStackConfig,
            cellMeasurement: cellMeasurement,
        )
        rootStackSubviews.append(textStack)

        linkPreviewView.configure(
            config: rootStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_rootStack,
            subviews: rootStackSubviews,
        )
    }

    func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        linkPreview: LinkPreviewSent,
    ) -> CGSize {
        var rootStackSubviewInfos = [ManualStackSubviewInfo]()

        let heroImageSize = sentHeroImageSize(
            linkPreview: linkPreview,
            maxWidth: maxWidth,
        )
        rootStackSubviewInfos.append(heroImageSize.asManualSubviewInfo)

        var maxLabelWidth = (maxWidth - (
            textStackConfig.layoutMargins.totalWidth + rootStackConfig.layoutMargins.totalWidth
        ))
        maxLabelWidth = max(0, maxLabelWidth)

        let textStackSize = measureSentTextStack(
            linkPreview: linkPreview,
            textStackConfig: textStackConfig,
            measurementBuilder: measurementBuilder,
            maxLabelWidth: maxLabelWidth,
        )
        rootStackSubviewInfos.append(textStackSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(
            config: rootStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_rootStack,
            subviewInfos: rootStackSubviewInfos,
            maxWidth: maxWidth,
        )
        return rootStackMeasurement.measuredSize
    }

    func sentHeroImageSize(
        linkPreview: LinkPreviewSent,
        maxWidth: CGFloat,
    ) -> CGSize {
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

// Compact thumbnail along the leading edges. Text goes to the right of the image.
private class CVLinkPreviewViewAdapterCompact: CVLinkPreviewViewAdapter {

    let linkPreview: LinkPreviewSent

    init(linkPreview: LinkPreviewSent) {
        self.linkPreview = linkPreview
    }

    var rootStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .horizontal,
            alignment: .center,
            spacing: CVLinkPreviewView.sentNonHeroHSpacing,
            layoutMargins: CVLinkPreviewView.sentNonHeroLayoutMargins,
        )
    }

    var textStackConfig: ManualStackView.Config {
        ManualStackView.Config(
            axis: .vertical,
            alignment: .leading,
            spacing: CVLinkPreviewView.textVSpacing,
            layoutMargins: .zero,
        )
    }

    func configureForRendering(
        linkPreviewView: CVLinkPreviewView,
        cellMeasurement: CVCellMeasurement,
    ) {
        var rootStackSubviews = [UIView]()

        if linkPreview.hasLoadedImageOrBlurHash {
            let linkPreviewImageView = linkPreviewView.linkPreviewImageView
            if let imageView = linkPreviewImageView.configure(linkPreview: linkPreview) {
                imageView.clipsToBounds = true
                rootStackSubviews.append(imageView)
            } else {
                owsFailDebug("Could not load image.")
                rootStackSubviews.append(UIView.transparentSpacer())
            }
        }

        let textStack = linkPreviewView.textStack
        configureSentTextStack(
            linkPreviewView: linkPreviewView,
            linkPreview: linkPreview,
            textStack: textStack,
            textStackConfig: textStackConfig,
            cellMeasurement: cellMeasurement,
        )
        rootStackSubviews.append(textStack)

        linkPreviewView.configure(
            config: rootStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_rootStack,
            subviews: rootStackSubviews,
        )
    }

    func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        linkPreview: LinkPreviewSent,
    ) -> CGSize {
        var maxLabelWidth = (maxWidth - (
            textStackConfig.layoutMargins.totalWidth + rootStackConfig.layoutMargins.totalWidth
        ))

        var rootStackSubviewInfos = [ManualStackSubviewInfo]()
        if linkPreview.hasLoadedImageOrBlurHash {
            let imageSize = CVLinkPreviewView.sentNonHeroImageSize
            rootStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxLabelWidth -= imageSize + rootStackConfig.spacing
        }

        maxLabelWidth = max(0, maxLabelWidth)

        let textStackSize = measureSentTextStack(
            linkPreview: linkPreview,
            textStackConfig: textStackConfig,
            measurementBuilder: measurementBuilder,
            maxLabelWidth: maxLabelWidth,
        )
        rootStackSubviewInfos.append(textStackSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(
            config: rootStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_rootStack,
            subviewInfos: rootStackSubviewInfos,
            maxWidth: maxWidth,
        )
        return rootStackMeasurement.measuredSize
    }
}

// MARK: -

private class CVLinkPreviewImageView: ManualLayoutViewWithLayer {

    enum Rounding: UInt {
        case none
        case circular
    }

    var rounding: Rounding = .none {
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

        rounding = .none
        isHero = false
        configurationId = 0
    }

    private func updateCornerRounding() {
        switch rounding {
        case .none:
            layer.cornerRadius = 0

        case .circular:
            layer.cornerRadius = bounds.size.smallerAxis / 2
        }
    }

    static let mediaCache = LRUCache<LinkPreviewImageCacheKey, UIImage>(
        maxSize: 2,
        shouldEvacuateInBackground: true,
    )

    func configure(linkPreview: LinkPreviewSent, rounding: Rounding = .none) -> UIView? {
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
        self.rounding = rounding
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
