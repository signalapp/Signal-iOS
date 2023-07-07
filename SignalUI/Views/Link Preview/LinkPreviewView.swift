//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import YYImage
import SignalMessaging

public protocol LinkPreviewViewDraftDelegate: AnyObject {
    func linkPreviewDidCancel()
}

// MARK: -

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
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init(name: String, arrangedSubviews: [UIView] = []) {
        fatalError("init(name:arrangedSubviews:) has not been implemented")
    }

    private var state: LinkPreviewState?
    private var configurationSize: CGSize?
    private var shouldReconfigureForBounds = false

    fileprivate let rightStack = ManualStackView(name: "rightStack")
    fileprivate let textStack = ManualStackView(name: "textStack")
    fileprivate let titleStack = ManualStackView(name: "titleStack")

    fileprivate let titleLabel = CVLabel()
    fileprivate let descriptionLabel = CVLabel()
    fileprivate let displayDomainLabel = CVLabel()

    fileprivate let linkPreviewImageView = LinkPreviewImageView()

    fileprivate var cancelButton: UIView?

    public init(draftDelegate: LinkPreviewViewDraftDelegate?) {
        self.draftDelegate = draftDelegate

        super.init(name: "LinkPreviewView")

        if draftDelegate != nil {
            self.isUserInteractionEnabled = true
            self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))
        }
    }

    private var nonCvcLayoutConstraint: NSLayoutConstraint?

    // This view is used in a number of places to display "drafts"
    // of outgoing link previews.  In these cases, the view will
    // be embedded within views using iOS auto layout and will need
    // to reconfigure its contents whenever the view size changes.
    public func configureForNonCVC(state: LinkPreviewState,
                                   isDraft: Bool,
                                   hasAsymmetricalRounding: Bool = false) {

        self.shouldDeactivateConstraints = false
        self.shouldReconfigureForBounds = true

        applyConfigurationForNonCVC(state: state,
                                    isDraft: isDraft,
                                    hasAsymmetricalRounding: hasAsymmetricalRounding)

        addLayoutBlock { view in
            guard let linkPreviewView = view as? LinkPreviewView else {
                owsFailDebug("Invalid view.")
                return
            }
            if let state = linkPreviewView.state,
               linkPreviewView.shouldReconfigureForBounds,
               linkPreviewView.configurationSize != linkPreviewView.bounds.size {
                linkPreviewView.applyConfigurationForNonCVC(state: state,
                                                            isDraft: isDraft,
                                                            hasAsymmetricalRounding: hasAsymmetricalRounding)
            }
        }
    }

    private func applyConfigurationForNonCVC(state: LinkPreviewState,
                                             isDraft: Bool,
                                             hasAsymmetricalRounding: Bool) {
        self.reset()
        self.configurationSize = bounds.size
        let maxWidth = (self.bounds.width > 0
                            ? self.bounds.width
                            : CGFloat.greatestFiniteMagnitude)

        let measurementBuilder = CVCellMeasurement.Builder()
        let linkPreviewSize = Self.measure(maxWidth: maxWidth,
                                           measurementBuilder: measurementBuilder,
                                           state: state,
                                           isDraft: isDraft)
        let cellMeasurement = measurementBuilder.build()
        configureForRendering(state: state,
                              isDraft: isDraft,
                              hasAsymmetricalRounding: hasAsymmetricalRounding,
                              cellMeasurement: cellMeasurement)

        if let nonCvcLayoutConstraint = self.nonCvcLayoutConstraint {
            nonCvcLayoutConstraint.constant = linkPreviewSize.height
        } else {
            self.nonCvcLayoutConstraint = self.autoSetDimension(.height,
                                                                toSize: linkPreviewSize.height)
        }
    }

    public func configureForRendering(state: LinkPreviewState,
                                      isDraft: Bool,
                                      hasAsymmetricalRounding: Bool,
                                      cellMeasurement: CVCellMeasurement) {
        self.state = state
        let adapter = Self.adapter(forState: state, isDraft: isDraft)
        adapter.configureForRendering(linkPreviewView: self,
                                      hasAsymmetricalRounding: hasAsymmetricalRounding,
                                      cellMeasurement: cellMeasurement)
    }

    private static func adapter(forState state: LinkPreviewState,
                                isDraft: Bool) -> LinkPreviewViewAdapter {
        if !state.isLoaded {
            return LinkPreviewViewAdapterDraftLoading(state: state)
        } else if isDraft {
            return LinkPreviewViewAdapterDraft(state: state)
        } else if state.isGroupInviteLink {
            return LinkPreviewViewAdapterGroupLink(state: state)
        } else {
            if state.hasLoadedImage {
                if Self.sentIsHero(state: state) {
                    return LinkPreviewViewAdapterSentHero(state: state)
                } else if state.previewDescription?.isEmpty == false,
                          state.title?.isEmpty == false {
                    return LinkPreviewViewAdapterSentWithDescription(state: state)
                } else {
                    return LinkPreviewViewAdapterSent(state: state)
                }
            } else {
                return LinkPreviewViewAdapterSent(state: state)
            }
        }
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
        guard let urlString = state.urlString else {
            owsFailDebug("Link preview is missing url.")
            return false
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Could not parse URL.")
            return false
        }
        return StickerPackInfo.isStickerPackShare(url)
    }

    static var defaultActivityIndicatorStyle: UIActivityIndicatorView.Style {
        .medium
    }

    // MARK: Events

    @objc
    private func wasTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        if let cancelButton = cancelButton {
            // Permissive hot area to make it very easy to cancel the link preview.
            if cancelButton.containsGestureLocation(sender, hotAreaInsets: .init(margin: -20)) {
                self.draftDelegate?.linkPreviewDidCancel()
                return
            }
        }
    }

    // MARK: Measurement

    public static func measure(maxWidth: CGFloat,
                               measurementBuilder: CVCellMeasurement.Builder,
                               state: LinkPreviewState,
                               isDraft: Bool) -> CGSize {
        let adapter = Self.adapter(forState: state, isDraft: isDraft)
        let size = adapter.measure(maxWidth: maxWidth,
                                   measurementBuilder: measurementBuilder,
                                   state: state)
        if size.width > maxWidth {
            owsFailDebug("size.width: \(size.width) > maxWidth: \(maxWidth)")
        }
        return size
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

        for subview in [
            rightStack, textStack, titleStack,
            titleLabel, descriptionLabel, displayDomainLabel,
            linkPreviewImageView
        ] {
            subview.removeFromSuperview()
        }

        cancelButton = nil

        nonCvcLayoutConstraint?.autoRemove()
        nonCvcLayoutConstraint = nil
    }
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

    fileprivate static var measurementKey_rootStack: String { "LinkPreviewView.measurementKey_rootStack" }
    fileprivate static var measurementKey_rightStack: String { "LinkPreviewView.measurementKey_rightStack" }
    fileprivate static var measurementKey_textStack: String { "LinkPreviewView.measurementKey_textStack" }
    fileprivate static var measurementKey_titleStack: String { "LinkPreviewView.measurementKey_titleStack" }

    func sentTitleLabel(state: LinkPreviewState) -> UILabel? {
        guard let config = sentTitleLabelConfig(state: state) else {
            return nil
        }
        let label = CVLabel()
        config.applyForRendering(label: label)
        return label
    }

    func sentTitleLabelConfig(state: LinkPreviewState) -> CVLabelConfig? {
        guard let text = state.title else {
            return nil
        }
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeSubheadline.semibold(),
            textColor: Theme.primaryTextColor,
            numberOfLines: LinkPreviewView.sentTitleLineCount,
            lineBreakMode: .byTruncatingTail
        )
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
        guard let text = state.previewDescription else { return nil }
        return CVLabelConfig.unstyledText(
            text,
            font: UIFont.dynamicTypeSubheadline,
            textColor: Theme.primaryTextColor,
            numberOfLines: LinkPreviewView.sentDescriptionLineCount,
            lineBreakMode: .byTruncatingTail
        )
    }

    func sentDomainLabel(state: LinkPreviewState) -> UILabel {
        let label = CVLabel()
        sentDomainLabelConfig(state: state).applyForRendering(label: label)
        return label
    }

    func sentDomainLabelConfig(state: LinkPreviewState) -> CVLabelConfig {
        var labelText: String
        if let displayDomain = state.displayDomain?.nilIfEmpty {
            labelText = displayDomain.lowercased()
        } else {
            labelText = OWSLocalizedString("LINK_PREVIEW_UNKNOWN_DOMAIN", comment: "Label for link previews with an unknown host.").uppercased()
        }
        if let date = state.date {
            labelText.append(" ⋅ \(LinkPreviewView.dateFormatter.string(from: date))")
        }
        return CVLabelConfig.unstyledText(
            labelText,
            font: UIFont.dynamicTypeCaption1,
            textColor: Theme.secondaryTextAndIconColor,
            lineBreakMode: .byTruncatingTail
        )
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
                            measurementKey: Self.measurementKey_textStack,
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
                                                  measurementKey: Self.measurementKey_textStack,
                                                  subviewInfos: subviewInfos)
        return measurement.measuredSize
    }
}

// MARK: -

private class LinkPreviewViewAdapterDraft: LinkPreviewViewAdapter {

    static let draftHeight: CGFloat = 72
    static let draftMarginTop: CGFloat = 6
    var imageSize: CGFloat { Self.draftHeight }
    let cancelSize: CGFloat = 20

    let state: LinkPreviewState

    init(state: LinkPreviewState) {
        self.state = state
    }

    var rootStackConfig: ManualStackView.Config {
        let hMarginLeading: CGFloat = state.hasLoadedImage ? 6 : 12
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
        guard let text = state.title?.nilIfEmpty else {
            return nil
        }
        return CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeBody,
            textColor: Theme.primaryTextColor,
            lineBreakMode: .byTruncatingTail
        )
    }

    var descriptionLabelConfig: CVLabelConfig? {
        guard let text = state.previewDescription?.nilIfEmpty else {
            return nil
        }
        return CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeSubheadline,
            textColor: Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray90,
            lineBreakMode: .byTruncatingTail
        )
    }

    var displayDomainLabelConfig: CVLabelConfig? {
        guard let displayDomain = state.displayDomain?.nilIfEmpty else {
            return nil
        }
        var text = displayDomain.lowercased()
        if let date = state.date {
            text.append(" ⋅ \(LinkPreviewView.dateFormatter.string(from: date))")
        }
        return CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeCaption1,
            textColor: Theme.secondaryTextAndIconColor,
            lineBreakMode: .byTruncatingTail
        )
    }

    func configureForRendering(linkPreviewView: LinkPreviewView,
                               hasAsymmetricalRounding: Bool,
                               cellMeasurement: CVCellMeasurement) {

        var rootStackSubviews = [UIView]()
        var rightStackSubviews = [UIView]()

        // Image

        if state.hasLoadedImage {
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
                            measurementKey: Self.measurementKey_textStack,
                            subviews: textStackSubviews)
        guard let textMeasurement = cellMeasurement.measurement(key: Self.measurementKey_textStack) else {
            owsFailDebug("Missing measurement.")
            return
        }
        let textWrapper = ManualLayoutView(name: "textWrapper")
        textWrapper.addSubview(textStack) { view in
            var textStackFrame = view.bounds
            textStackFrame.size.height = min(textStackFrame.height,
                                             textMeasurement.measuredSize.height)
            textStackFrame.y = (view.bounds.height - textStackFrame.height) * 0.5
            textStack.frame = textStackFrame
        }
        rightStackSubviews.append(textWrapper)

        // Cancel

        let cancelButton = OWSButton { [weak linkPreviewView] in
            linkPreviewView?.didTapCancel()
        }
        cancelButton.accessibilityLabel = MessageStrings.removePreviewButtonLabel
        linkPreviewView.cancelButton = cancelButton
        cancelButton.setTemplateImageName("x-20", tintColor: Theme.secondaryTextAndIconColor)
        let cancelSize = self.cancelSize
        let cancelContainer = ManualLayoutView(name: "cancelContainer")
        cancelContainer.addSubview(cancelButton) { view in
            cancelButton.frame = CGRect(x: 0,
                                        y: view.bounds.width - cancelSize,
                                        width: cancelSize,
                                        height: cancelSize)
        }
        rightStackSubviews.append(cancelContainer)

        // Right

        let rightStack = linkPreviewView.rightStack
        rightStack.configure(config: rightStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_rightStack,
                             subviews: rightStackSubviews)
        rootStackSubviews.append(rightStack)

        // Stroke

        let strokeView = UIView()
        strokeView.backgroundColor = Theme.secondaryTextAndIconColor
        rightStack.addSubviewAsBottomStroke(strokeView)

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: Self.measurementKey_rootStack,
                                  subviews: rootStackSubviews)
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        var maxLabelWidth = (maxWidth -
                                (textStackConfig.layoutMargins.totalWidth +
                                    rootStackConfig.layoutMargins.totalWidth))
        maxLabelWidth -= cancelSize + rightStackConfig.spacing

        var rootStackSubviewInfos = [ManualStackSubviewInfo]()
        var rightStackSubviewInfos = [ManualStackSubviewInfo]()

        // Image

        if state.hasLoadedImage {
            rootStackSubviewInfos.append(CGSize.square(imageSize).asManualSubviewInfo(hasFixedSize: true))
            maxLabelWidth -= imageSize + rootStackConfig.spacing
        }

        // Text

        var textStackSubviewInfos = [ManualStackSubviewInfo]()
        if let labelConfig = titleLabelConfig {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            textStackSubviewInfos.append(labelSize.asManualSubviewInfo)

        }
        if let labelConfig = self.descriptionLabelConfig {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            textStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        }
        if let labelConfig = self.displayDomainLabelConfig {
            let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxLabelWidth)
            textStackSubviewInfos.append(labelSize.asManualSubviewInfo)
        }

        let textStackMeasurement = ManualStackView.measure(config: textStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: Self.measurementKey_textStack,
                                                           subviewInfos: textStackSubviewInfos)
        rightStackSubviewInfos.append(textStackMeasurement.measuredSize.asManualSubviewInfo)

        // Right

        rightStackSubviewInfos.append(CGSize.square(cancelSize).asManualSubviewInfo(hasFixedWidth: true))

        let rightStackMeasurement = ManualStackView.measure(config: rightStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_rightStack,
                                                            subviewInfos: rightStackSubviewInfos)
        rootStackSubviewInfos.append(rightStackMeasurement.measuredSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: Self.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos,
                                                           maxWidth: maxWidth)
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
                                  measurementKey: Self.measurementKey_rootStack,
                                  subviews: [])
    }

    func measure(maxWidth: CGFloat,
                 measurementBuilder: CVCellMeasurement.Builder,
                 state: LinkPreviewState) -> CGSize {

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: Self.measurementKey_rootStack,
                                                           subviewInfos: [],
                                                           maxWidth: maxWidth)
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
                            measurementKey: Self.measurementKey_textStack,
                            subviews: textStackSubviews)
        rootStackSubviews.append(textStack)

        linkPreviewView.configure(config: rootStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: Self.measurementKey_rootStack,
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
                                                           measurementKey: Self.measurementKey_textStack,
                                                           subviewInfos: textStackSubviewInfos)
        rootStackSubviewInfos.append(textStackMeasurement.measuredSize.asManualSubviewInfo)

        let rootStackMeasurement = ManualStackView.measure(config: rootStackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: Self.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos,
                                                           maxWidth: maxWidth)
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
                                      alignment: .leading,
                                      spacing: LinkPreviewView.sentVSpacing,
                                      layoutMargins: LinkPreviewView.sentHeroLayoutMargins)
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
                                  measurementKey: Self.measurementKey_rootStack,
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
                                              conversationStyle: conversationStyle,
                                              maxWidth: maxWidth)
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
                                                           measurementKey: Self.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos,
                                                           maxWidth: maxWidth)
        return rootStackMeasurement.measuredSize
    }

    func sentHeroImageSize(state: LinkPreviewState,
                           conversationStyle: ConversationStyle,
                           maxWidth: CGFloat) -> CGSize {

        let imageHeightWidthRatio = (state.imagePixelSize.height / state.imagePixelSize.width)
        let maxMessageWidth = min(maxWidth, conversationStyle.maxMessageWidth)

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
                                      alignment: .leading,
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
                                  measurementKey: Self.measurementKey_rootStack,
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
                                                           measurementKey: Self.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos,
                                                           maxWidth: maxWidth)
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
                             measurementKey: Self.measurementKey_titleStack,
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
                                  measurementKey: Self.measurementKey_rootStack,
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
            maxTitleLabelWidth -= imageSize + titleStackConfig.spacing
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
                                                            measurementKey: Self.measurementKey_titleStack,
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
                                                           measurementKey: Self.measurementKey_rootStack,
                                                           subviewInfos: rootStackSubviewInfos,
                                                           maxWidth: maxWidth)
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

    private static let configurationIdCounter = AtomicUInt(0)
    private var configurationId: UInt = 0

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func reset() {
        super.reset()

        rounding = .standard
        isHero = false
        configurationId = 0
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
        guard state.isLoaded else {
            owsFailDebug("State not loaded.")
            return nil
        }
        guard state.imageState == .loaded else {
            return nil
        }
        self.rounding = hasAsymmetricalRounding ? .asymmetrical : .standard
        let configurationId = Self.configurationIdCounter.increment()
        self.configurationId = configurationId
        state.imageAsync(thumbnailQuality: .small) { [weak self] image in
            DispatchMainThreadSafe {
                guard let self = self else { return }
                guard self.configurationId == configurationId else { return }
                self.image = image
            }
        }
        return self
    }

    fileprivate static let mediaCache = LRUCache<String, NSObject>(maxSize: 2,
                                                                   shouldEvacuateInBackground: true)

    func configure(state: LinkPreviewState,
                   rounding roundingParam: LinkPreviewImageView.Rounding? = nil) -> UIImageView? {
        guard state.isLoaded else {
            owsFailDebug("State not loaded.")
            return nil
        }
        guard state.imageState == .loaded else {
            return nil
        }
        self.rounding = roundingParam ?? .standard
        let isHero = LinkPreviewView.sentIsHero(state: state)
        self.isHero = isHero
        let configurationId = Self.configurationIdCounter.increment()
        self.configurationId = configurationId
        let thumbnailQuality: AttachmentThumbnailQuality = isHero ? .medium : .small

        if let cacheKey = state.imageCacheKey(thumbnailQuality: thumbnailQuality),
           let image = Self.mediaCache.get(key: cacheKey) as? UIImage {
            self.image = image
        } else {
            state.imageAsync(thumbnailQuality: thumbnailQuality) { [weak self] image in
                DispatchMainThreadSafe {
                    guard let self = self else { return }
                    guard self.configurationId == configurationId else { return }
                    self.image = image
                    if let cacheKey = state.imageCacheKey(thumbnailQuality: thumbnailQuality) {
                        Self.mediaCache.set(key: cacheKey, value: image)
                    }
                }
            }
        }
        return self
    }
}

// MARK: -

public extension CGPoint {
    func offsetBy(dx: CGFloat = 0.0, dy: CGFloat = 0.0) -> CGPoint {
        return offsetBy(CGVector(dx: dx, dy: dy))
    }

    func offsetBy(_ vector: CGVector) -> CGPoint {
        return CGPoint(x: x + vector.dx, y: y + vector.dy)
    }
}

// MARK: -

public extension ManualLayoutView {
    func addSubviewAsBottomStroke(_ subview: UIView,
                                  layoutMargins: UIEdgeInsets = .zero) {
        addSubview(subview) { view in
            var subviewFrame = view.bounds.inset(by: layoutMargins)
            subviewFrame.size.height = .hairlineWidth
            subviewFrame.y = view.bounds.height - (subviewFrame.height +
                                                    layoutMargins.bottom)
            subview.frame = subviewFrame
        }
    }
}
