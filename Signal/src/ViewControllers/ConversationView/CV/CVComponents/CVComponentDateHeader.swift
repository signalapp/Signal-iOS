//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

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
        return componentView.wallpaperBlurView
    }

    public override func apply(layoutAttributes: CVCollectionViewLayoutAttributes,
                               componentView: CVComponentView) {
        guard let componentView = componentView as? CVComponentViewDateHeader else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        guard let doubleBackground = componentView.doubleBackground else {
            return
        }
        doubleBackground.normalView.isHidden = layoutAttributes.isStickyHeader
        doubleBackground.stickyView.isHidden = !layoutAttributes.isStickyHeader
    }

    fileprivate struct DoubleBackground {
        let normalView: UIView
        let stickyView: UIView
    }

    private func buildContentViewWithBlur(backgroundColor: UIColor,
                                          blurStyle: UIBlurEffect.Style,
                                          titleLabel: UIView) -> UIView {

        // blurView replaces innerStack, using the same size, layoutMargins, etc.
        let blurView = buildBlurView(backgroundColor: backgroundColor,
                                     blurStyle: blurStyle)
        blurView.clipsToBounds = true
        blurView.contentView.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewEdges(withInsets: innerStackConfig.layoutMargins)
        titleLabel.setContentHuggingLow()

        let wrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(blurView)
        wrapper.addLayoutBlock { view in
            blurView.layer.cornerRadius = view.frame.size.smallerAxis * 0.5
        }
        return wrapper
    }

    private func buildContentViewDefault(componentView: CVComponentViewDateHeader,
                                         cellMeasurement: CVCellMeasurement,
                                         componentDelegate: CVComponentDelegate,
                                         titleLabel: UIView,
                                         hasWallpaper: Bool) -> UIView {
        let innerStack = componentView.innerStack
        if hasWallpaper {
            let wallpaperBlurView = componentView.ensureWallpaperBlurView()
            configureWallpaperBlurView(wallpaperBlurView: wallpaperBlurView,
                                       maskCornerRadius: 8,
                                       componentDelegate: componentDelegate)
            innerStack.addSubviewToFillSuperviewEdges(wallpaperBlurView)
        }
        innerStack.configure(config: innerStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_innerStack,
                             subviews: [ titleLabel ])
        return innerStack
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewDateHeader else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let outerStack = componentView.outerStack
        let innerStack = componentView.innerStack
        let doubleBackgroundView = componentView.doubleBackgroundView

        let titleLabelNormal = componentView.titleLabelNormal
        titleLabelConfig.applyForRendering(label: titleLabelNormal)
        let titleLabelSticky = componentView.titleLabelSticky
        titleLabelConfig.applyForRendering(label: titleLabelSticky)

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled

        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        componentView.hasWallpaper = hasWallpaper

        let isReusing = (componentView.rootView.superview != nil &&
                            !themeHasChanged &&
                            !wallpaperModeHasChanged)
        if isReusing {
            innerStack.configureForReuse(config: innerStackConfig,
                                          cellMeasurement: cellMeasurement,
                                          measurementKey: Self.measurementKey_innerStack)
            outerStack.configureForReuse(config: outerStackConfig,
                                          cellMeasurement: cellMeasurement,
                                          measurementKey: Self.measurementKey_outerStack)
        } else {
            innerStack.reset()
            outerStack.reset()
            doubleBackgroundView.reset()
            titleLabelNormal.removeFromSuperview()
            titleLabelSticky.removeFromSuperview()
            componentView.wallpaperBlurView?.removeFromSuperview()
            componentView.wallpaperBlurView = nil

            let contentView: UIView = {
                if componentDelegate.isConversationPreview {
                    let blurBackgroundColor: UIColor = conversationStyle.isDarkThemeEnabled ? .ows_blackAlpha40 : .ows_whiteAlpha60
                    let blurStyle: UIBlurEffect.Style = .regular
                    return self.buildContentViewWithBlur(backgroundColor: blurBackgroundColor,
                                                         blurStyle: blurStyle,
                                                         titleLabel: titleLabelNormal)
                } else if hasWallpaper {
                    return self.buildContentViewDefault(componentView: componentView,
                                                            cellMeasurement: cellMeasurement,
                                                            componentDelegate: componentDelegate,
                                                            titleLabel: titleLabelNormal,
                                                            hasWallpaper: true)
                } else {
                    let blurBackgroundColor: UIColor = conversationStyle.isDarkThemeEnabled ? .ows_blackAlpha40 : .ows_whiteAlpha60
                    let blurStyle: UIBlurEffect.Style = .regular
                    let blurContentView = self.buildContentViewWithBlur(backgroundColor: blurBackgroundColor,
                                                                        blurStyle: blurStyle,
                                                                        titleLabel: titleLabelSticky)
                    let defaultContentView = self.buildContentViewDefault(componentView: componentView,
                                                                          cellMeasurement: cellMeasurement,
                                                                          componentDelegate: componentDelegate,
                                                                          titleLabel: titleLabelNormal,
                                                                          hasWallpaper: false)
                    doubleBackgroundView.addSubviewToFillSuperviewEdges(blurContentView)
                    doubleBackgroundView.addSubviewToFillSuperviewEdges(defaultContentView)
                    componentView.doubleBackground = DoubleBackground(normalView: defaultContentView,
                                                                      stickyView: blurContentView)
                    return doubleBackgroundView
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

    private static let measurementKey_outerStack = "CVComponentDateHeader.measurementKey_outerStack"
    private static let measurementKey_innerStack = "CVComponentDateHeader.measurementKey_innerStack"

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
        fileprivate let innerStack = ManualStackView(name: "dateHeader.innerStackView")
        fileprivate let doubleBackgroundView = ManualLayoutView(name: "DoubleBackground")
        fileprivate let titleLabelNormal = CVLabel()
        fileprivate let titleLabelSticky = CVLabel()

        fileprivate var wallpaperBlurView: CVWallpaperBlurView?
        fileprivate func ensureWallpaperBlurView() -> CVWallpaperBlurView {
            if let wallpaperBlurView = self.wallpaperBlurView {
                return wallpaperBlurView
            }
            let wallpaperBlurView = CVWallpaperBlurView()
            self.wallpaperBlurView = wallpaperBlurView
            return wallpaperBlurView
        }

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        public var isDedicatedCellView = false

        fileprivate var doubleBackground: DoubleBackground?

        public var rootView: UIView {
            outerStack
        }

        // MARK: -

        override required init() {
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            if !isDedicatedCellView {
                outerStack.reset()
                innerStack.reset()
                doubleBackgroundView.reset()

                titleLabelNormal.removeFromSuperview()
                titleLabelSticky.removeFromSuperview()

                wallpaperBlurView?.removeFromSuperview()
                wallpaperBlurView?.resetContentAndConfiguration()

                hasWallpaper = false
                isDarkThemeEnabled = false
                doubleBackground = nil
            }

            titleLabelNormal.text = nil
            titleLabelSticky.text = nil
        }
    }
}
