//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public class CVComponentUnreadIndicator: CVComponentBase, CVRootComponent {

    public var componentKey: CVComponentKey { .unreadIndicator }

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.unreadIndicator
    }

    public let isDedicatedCell = true

    override init(itemModel: CVItemModel) {
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
        CVComponentViewUnreadIndicator()
    }

    public override func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewUnreadIndicator else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.wallpaperBlurView
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewUnreadIndicator else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper

        let isReusing = (componentView.rootView.superview != nil &&
                            !themeHasChanged &&
                            !wallpaperModeHasChanged)

        if !isReusing {
            componentView.reset(resetReusableState: true)
        }

        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled
        componentView.hasWallpaper = hasWallpaper

        let outerStack = componentView.outerStack
        let innerStack = componentView.innerStack
        let strokeView = componentView.strokeView
        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)

        if isReusing {
            innerStack.configureForReuse(config: innerStackConfig,
                                         cellMeasurement: cellMeasurement,
                                         measurementKey: Self.measurementKey_innerStack)
            outerStack.configureForReuse(config: outerStackConfig,
                                         cellMeasurement: cellMeasurement,
                                         measurementKey: Self.measurementKey_outerStack)
        } else {
            outerStack.reset()
            titleLabel.removeFromSuperview()
            componentView.wallpaperBlurView?.removeFromSuperview()
            componentView.wallpaperBlurView = nil

            innerStack.reset()
            innerStack.configure(config: innerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_innerStack,
                                 subviews: [ titleLabel ])

            if hasWallpaper {
                strokeView.backgroundColor = .ows_blackAlpha80

                let wallpaperBlurView = componentView.ensureWallpaperBlurView()
                configureWallpaperBlurView(wallpaperBlurView: wallpaperBlurView,
                                           maskCornerRadius: 8,
                                           componentDelegate: componentDelegate)
                innerStack.addSubviewToFillSuperviewEdges(wallpaperBlurView)
            } else {
                strokeView.backgroundColor = .ows_gray45
            }

            outerStack.configure(config: outerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_outerStack,
                                 subviews: [
                                    strokeView,
                                    innerStack
                                 ])
        }
    }

    private var titleLabelConfig: CVLabelConfig {
        CVLabelConfig(text: OWSLocalizedString("MESSAGES_VIEW_UNREAD_INDICATOR",
                                              comment: "Indicator that separates read from unread messages."),
                      font: UIFont.dynamicTypeFootnote.semibold(),
                      textColor: Theme.primaryTextColor,
                      numberOfLines: 0,
                      lineBreakMode: .byTruncatingTail,
                      textAlignment: .center)
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 12,
                          layoutMargins: UIEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: UIEdgeInsets(hMargin: 10, vMargin: 4))
    }

    private static let measurementKey_outerStack = "CVComponentUnreadIndicator.measurementKey_outerStack"
    private static let measurementKey_innerStack = "CVComponentUnreadIndicator.measurementKey_innerStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let availableWidth = max(0, maxWidth -
                                    (innerStackConfig.layoutMargins.totalWidth +
                                        outerStackConfig.layoutMargins.totalWidth))
        let labelSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: availableWidth)
        let strokeSize = CGSize(width: 0, height: 1)

        let labelInfo = labelSize.asManualSubviewInfo
        let innerStackMeasurement = ManualStackView.measure(config: innerStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_innerStack,
        subviewInfos: [ labelInfo ])

        let strokeInfo = strokeSize.asManualSubviewInfo(hasFixedHeight: true)
        let innerStackInfo = innerStackMeasurement.measuredSize.asManualSubviewInfo(hasFixedWidth: true)
        let vStackSubviewInfos = [
            strokeInfo,
            innerStackInfo
        ]
        let vStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_outerStack,
                                                        subviewInfos: vStackSubviewInfos,
                                                        maxWidth: maxWidth)
        return vStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewUnreadIndicator: NSObject, CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "unreadIndicator.outerStack")
        fileprivate let innerStack = ManualStackView(name: "unreadIndicator.innerStack")

        fileprivate let titleLabel = CVLabel()

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

        fileprivate let strokeView = UIView()

        public var isDedicatedCellView = false

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

            titleLabel.text = nil

            if resetReusableState {
                outerStack.reset()
                innerStack.reset()

                wallpaperBlurView?.removeFromSuperview()
                wallpaperBlurView?.resetContentAndConfiguration()

                hasWallpaper = false
                isDarkThemeEnabled = false
            }
        }
    }
}
