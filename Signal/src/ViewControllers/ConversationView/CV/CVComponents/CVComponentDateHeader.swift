//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

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

    required init(itemModel: CVItemModel, dateHeaderState: State) {
        self.dateHeaderState = dateHeaderState

        super.init(itemModel: itemModel)
    }

    public func configureCellRootComponent(cellView: UIView,
                                           cellMeasurement: CVCellMeasurement,
                                           componentDelegate: CVComponentDelegate,
                                           messageSwipeActionState: CVMessageSwipeActionState,
                                           componentView: CVComponentView) {
        Self.configureCellRootComponent(rootComponent: self,
                                        cellView: cellView,
                                        cellMeasurement: cellMeasurement,
                                        componentDelegate: componentDelegate,
                                        componentView: componentView)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewDateHeader()
    }

    public override func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewDateHeader else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.contentViewDefault?.wallpaperBlurView
    }

    public override func apply(layoutAttributes: CVCollectionViewLayoutAttributes,
                               componentView: CVComponentView) {
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

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
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
            outerStack.configureForReuse(config: outerStackConfig,
                                          cellMeasurement: cellMeasurement,
                                          measurementKey: Self.measurementKey_outerStack)

            let contentViewDefault = componentView.contentViewDefault
            let contentViewForBlur = componentView.contentViewForBlur
            contentViewDefault?.configure(componentView: componentView,
                                          cellMeasurement: cellMeasurement,
                                          componentDelegate: componentDelegate,
                                          hasWallpaper: hasWallpaper,
                                          titleLabelConfig: titleLabelConfig,
                                          innerStackConfig: innerStackConfig,
                                          isReusing: true)
            contentViewForBlur?.configure(blurBackgroundColor: blurBackgroundColor,
                                          titleLabelConfig: titleLabelConfig,
                                          innerStackConfig: innerStackConfig,
                                          isReusing: true)
        } else {
            outerStack.reset()
            doubleContentWrapper.reset()

            let contentView: UIView = {
                func buildContentViewWithBlur() -> UIView {
                    let contentView = componentView.ensureContentViewForBlur()
                    contentView.configure(blurBackgroundColor: blurBackgroundColor,
                                          titleLabelConfig: titleLabelConfig,
                                          innerStackConfig: innerStackConfig,
                                          isReusing: false)
                    return contentView.rootView
                }
                func buildContentViewDefault() -> UIView {
                    let contentView = componentView.ensureContentViewDefault()
                    contentView.configure(componentView: componentView,
                                          cellMeasurement: cellMeasurement,
                                          componentDelegate: componentDelegate,
                                          hasWallpaper: hasWallpaper,
                                          titleLabelConfig: titleLabelConfig,
                                          innerStackConfig: innerStackConfig,
                                          isReusing: false)
                    return contentView.rootView
                }

                if componentDelegate.isConversationPreview {
                    return buildContentViewWithBlur()
                } else if hasWallpaper {
                    return buildContentViewDefault()
                } else {
                    let blurContentView = buildContentViewWithBlur()
                    let defaultContentView = buildContentViewDefault()
                    doubleContentWrapper.addSubviewToFillSuperviewEdges(blurContentView)
                    doubleContentWrapper.addSubviewToFillSuperviewEdges(defaultContentView)
                    componentView.doubleContentView = DoubleContentView(normalView: defaultContentView,
                                                                        stickyView: blurContentView)
                    return doubleContentWrapper
                }
            }()

            outerStack.configure(config: outerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_outerStack,
                                 subviews: [ contentView ])
        }

        componentView.rootView.accessibilityLabel = titleLabelConfig.stringValue
        componentView.rootView.isAccessibilityElement = true
        componentView.rootView.accessibilityTraits = .header
    }

    static func buildState(interaction: TSInteraction) -> State {
        let date = Date(millisecondsSince1970: interaction.timestamp)
        let text = DateUtil.formatDateHeaderForCVC(date)
        return State(text: text)
    }

    private var titleLabelConfig: CVLabelConfig {
        return CVLabelConfig(text: dateHeaderState.text,
                             font: UIFont.ows_dynamicTypeFootnote.ows_semibold,
                             textColor: Theme.secondaryTextAndIconColor,
                             lineBreakMode: .byTruncatingTail,
                             textAlignment: .center)
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: UIEdgeInsets(top: 0,
                                                      leading: conversationStyle.headerGutterLeading,
                                                      bottom: 0,
                                                      trailing: conversationStyle.headerGutterTrailing))
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: UIEdgeInsets(hMargin: 10, vMargin: 4))
    }

    fileprivate static let measurementKey_outerStack = "CVComponentDateHeader.measurementKey_outerStack"
    fileprivate static let measurementKey_innerStack = "CVComponentDateHeader.measurementKey_innerStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let availableWidth = max(0, maxWidth -
                                    (innerStackConfig.layoutMargins.totalWidth +
                                        outerStackConfig.layoutMargins.totalWidth))
        let labelSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: availableWidth)

        let labelInfo = labelSize.asManualSubviewInfo
        let innerStackMeasurement = ManualStackView.measure(config: innerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_innerStack,
                                                            subviewInfos: [ labelInfo ])
        let innerStackInfo = innerStackMeasurement.measuredSize.asManualSubviewInfo
        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_outerStack,
                                                        subviewInfos: [ innerStackInfo ],
                                                        maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewDateHeader: NSObject, CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "dateHeader.outerStackView")
        fileprivate let doubleContentWrapper = ManualLayoutView(name: "dateHeader.doubleContentWrapper")

        fileprivate var contentViewDefault: ContentViewDefault?
        fileprivate func ensureContentViewDefault() -> ContentViewDefault {
            if let contentViewDefault = self.contentViewDefault {
                return contentViewDefault
            }
            let contentViewDefault = ContentViewDefault()
            self.contentViewDefault = contentViewDefault
            return contentViewDefault
        }

        fileprivate var contentViewForBlur: ContentViewForBlur?
        fileprivate func ensureContentViewForBlur() -> ContentViewForBlur {
            if let contentViewForBlur = self.contentViewForBlur {
                return contentViewForBlur
            }
            let contentViewForBlur = ContentViewForBlur()
            self.contentViewForBlur = contentViewForBlur
            return contentViewForBlur
        }

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        public var isDedicatedCellView = false

        fileprivate var doubleContentView: DoubleContentView?

        public var rootView: UIView {
            outerStack
        }

        // MARK: -

        override required init() {
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            reset(resetReusableState: false)
        }

        public func reset(resetReusableState: Bool) {
            owsAssertDebug(isDedicatedCellView)

            contentViewDefault?.reset(resetReusableState: resetReusableState)
            contentViewForBlur?.reset(resetReusableState: resetReusableState)

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

private class ContentViewForBlur {
    private let titleLabel = CVLabel()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let blurOverlay = UIView()
    private let wrapper: UIView

    private var layoutConstraints = [NSLayoutConstraint]()

    var rootView: UIView { wrapper }

    init() {
        blurView.contentView.addSubview(blurOverlay)
        blurOverlay.autoPinEdgesToSuperviewEdges()

        blurView.clipsToBounds = true

        let wrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(blurView)
        let blurView = self.blurView
        wrapper.addLayoutBlock { view in
            blurView.layer.cornerRadius = view.frame.size.smallerAxis * 0.5
        }
        self.wrapper = wrapper
    }

    func configure(blurBackgroundColor: UIColor,
                   titleLabelConfig: CVLabelConfig,
                   innerStackConfig: CVStackViewConfig,
                   isReusing: Bool) {

        if !isReusing {
            reset(resetReusableState: true)
        }

        titleLabelConfig.applyForRendering(label: titleLabel)
        blurOverlay.backgroundColor = blurBackgroundColor

        if isReusing {
            // Do nothing.
        } else {
            if titleLabel.superview == nil {
                blurView.contentView.addSubview(titleLabel)
                titleLabel.setContentHuggingLow()
            } else {
                NSLayoutConstraint.deactivate(layoutConstraints)
            }
            layoutConstraints = titleLabel.autoPinEdgesToSuperviewEdges(with: innerStackConfig.layoutMargins)
        }
    }

    public func reset(resetReusableState: Bool) {

        if resetReusableState {
            titleLabel.removeFromSuperview()
        }

        titleLabel.text = nil
        layoutConstraints = []
    }
}

// MARK: -

private class ContentViewDefault {
    private let titleLabel = CVLabel()
    private let innerStack = ManualStackView(name: "dateHeader.innerStackView")

    var rootView: UIView { innerStack }

    fileprivate var wallpaperBlurView: CVWallpaperBlurView?
    private func ensureWallpaperBlurView() -> CVWallpaperBlurView {
        if let wallpaperBlurView = self.wallpaperBlurView {
            return wallpaperBlurView
        }
        let wallpaperBlurView = CVWallpaperBlurView()
        self.wallpaperBlurView = wallpaperBlurView
        return wallpaperBlurView
    }

    func configure(componentView: CVComponentDateHeader.CVComponentViewDateHeader,
                   cellMeasurement: CVCellMeasurement,
                   componentDelegate: CVComponentDelegate,
                   hasWallpaper: Bool,
                   titleLabelConfig: CVLabelConfig,
                   innerStackConfig: CVStackViewConfig,
                   isReusing: Bool) {

        if !isReusing {
            reset(resetReusableState: true)
        }

        titleLabelConfig.applyForRendering(label: titleLabel)

        if isReusing {
            innerStack.configureForReuse(config: innerStackConfig,
                                         cellMeasurement: cellMeasurement,
                                         measurementKey: CVComponentDateHeader.measurementKey_innerStack)
        } else {
            if hasWallpaper {
                let wallpaperBlurView = ensureWallpaperBlurView()
                CVComponentBase.configureWallpaperBlurView(wallpaperBlurView: wallpaperBlurView,
                                                           maskCornerRadius: 8,
                                                           componentDelegate: componentDelegate)
                innerStack.addSubviewToFillSuperviewEdges(wallpaperBlurView)
            }
            innerStack.configure(config: innerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: CVComponentDateHeader.measurementKey_innerStack,
                                 subviews: [ titleLabel ])
        }
    }

    public func reset(resetReusableState: Bool) {

        if resetReusableState {
            innerStack.reset()

            titleLabel.removeFromSuperview()

            wallpaperBlurView?.removeFromSuperview()
            wallpaperBlurView?.resetContentAndConfiguration()
        }

        titleLabel.text = nil
    }
}
