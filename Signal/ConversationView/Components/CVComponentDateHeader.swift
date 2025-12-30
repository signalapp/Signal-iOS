//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class CVComponentDateHeader: CVComponentBase, CVRootComponent {

    public var componentKey: CVComponentKey { .dateHeader }

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.dateHeader
    }

    public let isDedicatedCell = true

    struct State: Equatable {
        let text: String
    }

    private let dateHeaderState: State

    init(itemModel: CVItemModel, dateHeaderState: State) {
        self.dateHeaderState = dateHeaderState

        super.init(itemModel: itemModel)
    }

    public func configureCellRootComponent(
        cellView: UIView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
        messageSwipeActionState: CVMessageSwipeActionState,
        componentView: CVComponentView,
    ) {
        Self.configureCellRootComponent(
            rootComponent: self,
            cellView: cellView,
            cellMeasurement: cellMeasurement,
            componentDelegate: componentDelegate,
            componentView: componentView,
        )
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewDateHeader()
    }

    override public func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewDateHeader else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.plainContentView?.wallpaperBlurView
    }

    override public func apply(
        layoutAttributes: CVCollectionViewLayoutAttributes,
        componentView: CVComponentView,
    ) {
        guard let componentView = componentView as? CVComponentViewDateHeader else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        guard let doubleContentView = componentView.doubleContentView else {
            return
        }
        doubleContentView.normalView.isHidden = layoutAttributes.isStickyHeader
        doubleContentView.stickyView.isHidden = !layoutAttributes.isStickyHeader
    }

    fileprivate struct DoubleContentView {
        let normalView: UIView
        let stickyView: UIView
    }

    public func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewDateHeader else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let themeHasChanged = isDarkThemeEnabled != componentView.isDarkThemeEnabled
        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper

        let isReusing = (componentView.rootView.superview != nil &&
            !themeHasChanged &&
            !wallpaperModeHasChanged)
        if !isReusing {
            componentView.reset(resetReusableState: true)
        }

        componentView.isDarkThemeEnabled = isDarkThemeEnabled
        componentView.hasWallpaper = hasWallpaper

        let outerStack = componentView.outerStack
        let doubleContentWrapper = componentView.doubleContentWrapper

        let blurBackgroundColor: UIColor = {
            if componentDelegate.isConversationPreview {
                return isDarkThemeEnabled ? .ows_blackAlpha40 : .ows_whiteAlpha60
            } else {
                return isDarkThemeEnabled ? UIColor(rgbHex: 0x1B1B1B) : UIColor(rgbHex: 0xFAFAFA)
            }
        }()

        if isReusing {
            outerStack.configureForReuse(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
            )

            let plainContentView = componentView.plainContentView
            plainContentView?.configure(
                componentView: componentView,
                cellMeasurement: cellMeasurement,
                componentDelegate: componentDelegate,
                hasWallpaper: hasWallpaper,
                titleLabelConfig: titleLabelConfigForPlainContentView,
                innerStackConfig: innerStackConfig,
                isReusing: true,
            )

            let contentViewVisualEffect = componentView.visualEffectContentView
            contentViewVisualEffect?.configure(
                blurBackgroundColor: blurBackgroundColor,
                titleLabelConfig: titleLabelConfigForVisualEffectContentView,
                innerStackConfig: innerStackConfig,
            )
        } else {
            outerStack.reset()
            doubleContentWrapper.reset()

            let contentView: UIView = {
                func buildPlainContentView() -> UIView {
                    let contentView = componentView.ensurePlainContentView()
                    contentView.configure(
                        componentView: componentView,
                        cellMeasurement: cellMeasurement,
                        componentDelegate: componentDelegate,
                        hasWallpaper: hasWallpaper,
                        titleLabelConfig: titleLabelConfigForPlainContentView,
                        innerStackConfig: innerStackConfig,
                        isReusing: false,
                    )
                    return contentView.rootView
                }
                func buildVisualEffectContentView() -> UIView {
                    let contentView = componentView.ensureVisualEffectContentView()
                    contentView.configure(
                        blurBackgroundColor: blurBackgroundColor,
                        titleLabelConfig: titleLabelConfigForVisualEffectContentView,
                        innerStackConfig: innerStackConfig,
                    )
                    return contentView.rootView
                }

                let isStandaloneRenderItem = conversationStyle.isStandaloneRenderItem

                // On iOS 26 always use `visual effect` content view for the sticky header.
                if componentDelegate.isConversationPreview {
                    return buildVisualEffectContentView()
                } else if hasWallpaper, #unavailable(iOS 26) {
                    return buildPlainContentView()
                } else if isStandaloneRenderItem {
                    return buildPlainContentView()
                } else {
                    let plainContentView = buildPlainContentView()
                    let visualEffectContentView = buildVisualEffectContentView()
                    doubleContentWrapper.addSubviewToFillSuperviewEdges(plainContentView)
                    doubleContentWrapper.addSubviewToFillSuperviewEdges(visualEffectContentView)
                    componentView.doubleContentView = DoubleContentView(
                        normalView: plainContentView,
                        stickyView: visualEffectContentView,
                    )
                    return doubleContentWrapper
                }
            }()

            outerStack.configure(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
                subviews: [contentView],
            )
        }

        componentView.rootView.accessibilityLabel = titleLabelConfigForPlainContentView.text.accessibilityDescription
        componentView.rootView.isAccessibilityElement = true
        componentView.rootView.accessibilityTraits = .header
    }

    static func buildState(interaction: TSInteraction) -> State {
        let date = Date(millisecondsSince1970: interaction.timestamp)
        let text = DateUtil.formatDateHeaderForCVC(date)
        return State(text: text)
    }

    private func titleLabelConfig(textColor: UIColor) -> CVLabelConfig {
        return CVLabelConfig(
            text: .text(dateHeaderState.text),
            displayConfig: .forUnstyledText(font: .dynamicTypeFootnote.semibold(), textColor: textColor),
            font: UIFont.dynamicTypeFootnote.semibold(),
            textColor: textColor,
            lineBreakMode: .byTruncatingTail,
            textAlignment: .center,
        )
    }

    private var titleLabelConfigForPlainContentView: CVLabelConfig {
        return titleLabelConfig(textColor: .Signal.secondaryLabel)
    }

    private var titleLabelConfigForVisualEffectContentView: CVLabelConfig {
        let textColor: UIColor
        if #available(iOS 26.0, *) {
            textColor = .Signal.label
        } else {
            textColor = .Signal.secondaryLabel
        }
        return titleLabelConfig(textColor: textColor)
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: UIEdgeInsets(
                top: 0,
                leading: conversationStyle.headerGutterLeading,
                bottom: 0,
                trailing: conversationStyle.headerGutterTrailing,
            ),
        )
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: UIEdgeInsets(hMargin: 10, vMargin: 4),
        )
    }

    fileprivate static let measurementKey_outerStack = "CVComponentDateHeader.measurementKey_outerStack"
    fileprivate static let measurementKey_innerStack = "CVComponentDateHeader.measurementKey_innerStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let availableWidth = max(
            0,
            maxWidth -
                (innerStackConfig.layoutMargins.totalWidth +
                    outerStackConfig.layoutMargins.totalWidth),
        )
        let labelSize = CVText.measureLabel(config: titleLabelConfigForPlainContentView, maxWidth: availableWidth)

        let labelInfo = labelSize.asManualSubviewInfo
        let innerStackMeasurement = ManualStackView.measure(
            config: innerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerStack,
            subviewInfos: [labelInfo],
        )
        let innerStackInfo = innerStackMeasurement.measuredSize.asManualSubviewInfo
        let outerStackMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: [innerStackInfo],
            maxWidth: maxWidth,
        )
        return outerStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewDateHeader: NSObject, CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "dateHeader.outerStackView")
        fileprivate let doubleContentWrapper = ManualLayoutView(name: "dateHeader.doubleContentWrapper")

        fileprivate var plainContentView: ContentViewNoVisualEffect?
        fileprivate func ensurePlainContentView() -> ContentViewNoVisualEffect {
            if let plainContentView {
                return plainContentView
            }
            let plainContentView = ContentViewNoVisualEffect()
            self.plainContentView = plainContentView
            return plainContentView
        }

        fileprivate var visualEffectContentView: VisualEffectContentView?
        fileprivate func ensureVisualEffectContentView() -> VisualEffectContentView {
            if let visualEffectContentView {
                return visualEffectContentView
            }
#if compiler(>=6.2)
            let visualEffectContentView: VisualEffectContentView
            if #available(iOS 26.0, *) {
                visualEffectContentView = ContentViewWithGlassEffect()
            } else {
                visualEffectContentView = ContentViewWithBlurEffect()
            }
#else
            let visualEffectContentView = ContentViewWithBlurEffect()
#endif
            self.visualEffectContentView = visualEffectContentView
            return visualEffectContentView
        }

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        public var isDedicatedCellView = false

        fileprivate var doubleContentView: DoubleContentView?

        public var rootView: UIView {
            outerStack
        }

        // MARK: -

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            reset(resetReusableState: false)
        }

        public func reset(resetReusableState: Bool) {
            owsAssertDebug(isDedicatedCellView)

            plainContentView?.reset(resetReusableState: resetReusableState)
            visualEffectContentView?.reset()

            if resetReusableState {
                outerStack.reset()
                doubleContentWrapper.reset()

                hasWallpaper = false
                isDarkThemeEnabled = false
                doubleContentView = nil
            }
        }
    }
}

// MARK: -

private protocol VisualEffectContentView {
    var rootView: UIView { get }
    func configure(blurBackgroundColor: UIColor, titleLabelConfig: CVLabelConfig, innerStackConfig: CVStackViewConfig)
    func reset()
}

// MARK: -

private class ContentViewWithBlurEffect: VisualEffectContentView {
    private let titleLabel = CVLabel()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let blurOverlay = UIView()
    private let wrapper: UIView

    var rootView: UIView { wrapper }

    init() {
        blurView.clipsToBounds = true
        blurView.contentView.addSubview(blurOverlay)
        blurOverlay.autoPinEdgesToSuperviewEdges()

        let wrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(blurView)
        let blurView = self.blurView
        wrapper.addLayoutBlock { view in
            blurView.layer.cornerRadius = view.frame.size.smallerAxis * 0.5
        }
        self.wrapper = wrapper
    }

    func configure(blurBackgroundColor: UIColor, titleLabelConfig: CVLabelConfig, innerStackConfig: CVStackViewConfig) {
        titleLabelConfig.applyForRendering(label: titleLabel)
        blurOverlay.backgroundColor = blurBackgroundColor

        if titleLabel.superview == nil {
            titleLabel.setContentHuggingLow()
            blurView.contentView.addSubview(titleLabel)
            titleLabel.autoPinEdgesToSuperviewEdges(with: innerStackConfig.layoutMargins)
        }
    }

    func reset() {
        titleLabel.text = nil
    }
}

// MARK: -

#if compiler(>=6.2)
@available(iOS 26.0, *)
private class ContentViewWithGlassEffect: VisualEffectContentView {
    private let titleLabel = CVLabel()
    private let glassView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let wrapper: UIView

    private var layoutConstraints = [NSLayoutConstraint]()

    var rootView: UIView { wrapper }

    init() {
        glassView.cornerConfiguration = .capsule()

        /// WARNING: Must wrap into a UIView or `titleLabel` won't be properly sized.
        self.wrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(glassView)
    }

    func configure(
        blurBackgroundColor: UIColor,
        titleLabelConfig: CVLabelConfig,
        innerStackConfig: CVStackViewConfig,
    ) {

        titleLabelConfig.applyForRendering(label: titleLabel)

        if titleLabel.superview == nil {
            titleLabel.setContentHuggingLow()
            glassView.contentView.addSubview(titleLabel)
            titleLabel.autoPinEdgesToSuperviewEdges(with: innerStackConfig.layoutMargins)
        }
    }

    func reset() {
        titleLabel.text = nil
    }
}
#endif

// MARK: -

private class ContentViewNoVisualEffect {
    private let titleLabel = CVLabel()
    private let innerStack = ManualStackView(name: "dateHeader.innerStackView")

    var rootView: UIView { innerStack }

    fileprivate var wallpaperBlurView: CVWallpaperBlurView?
    private func ensureWallpaperBlurView() -> CVWallpaperBlurView {
        if let wallpaperBlurView {
            return wallpaperBlurView
        }
        let wallpaperBlurView = CVWallpaperBlurView()
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Will override `cornerRadius` set in `configure...`.
            wallpaperBlurView.cornerConfiguration = .capsule()
        }
#endif
        self.wallpaperBlurView = wallpaperBlurView
        return wallpaperBlurView
    }

    func configure(
        componentView: CVComponentDateHeader.CVComponentViewDateHeader,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
        hasWallpaper: Bool,
        titleLabelConfig: CVLabelConfig,
        innerStackConfig: CVStackViewConfig,
        isReusing: Bool,
    ) {

        if !isReusing {
            reset(resetReusableState: true)
        }

        titleLabelConfig.applyForRendering(label: titleLabel)

        if isReusing {
            innerStack.configureForReuse(
                config: innerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: CVComponentDateHeader.measurementKey_innerStack,
            )
        } else {
            if hasWallpaper {
                let wallpaperBlurView = ensureWallpaperBlurView()
                CVComponentBase.configureWallpaperBlurView(
                    wallpaperBlurView: wallpaperBlurView,
                    maskCornerRadius: 8,
                    componentDelegate: componentDelegate,
                )
                innerStack.addSubviewToFillSuperviewEdges(wallpaperBlurView)
            }
            innerStack.configure(
                config: innerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: CVComponentDateHeader.measurementKey_innerStack,
                subviews: [titleLabel],
            )
        }
    }

    func reset(resetReusableState: Bool) {
        if resetReusableState {
            innerStack.reset()

            titleLabel.removeFromSuperview()

            wallpaperBlurView?.removeFromSuperview()
            wallpaperBlurView?.resetContentAndConfiguration()
        }

        titleLabel.text = nil
    }
}
