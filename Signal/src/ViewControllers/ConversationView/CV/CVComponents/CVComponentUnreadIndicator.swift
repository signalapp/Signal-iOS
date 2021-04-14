//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentUnreadIndicator: CVComponentBase, CVRootComponent {

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.unreadIndicator
    }

    public let isDedicatedCell = true

    override init(itemModel: CVItemModel) {
        super.init(itemModel: itemModel)
    }

    public func configure(cellView: UIView,
                          cellMeasurement: CVCellMeasurement,
                          componentDelegate: CVComponentDelegate,
                          cellSelection: CVCellSelection,
                          messageSwipeActionState: CVMessageSwipeActionState,
                          componentView: CVComponentView) {

        configureForRendering(componentView: componentView,
                              cellMeasurement: cellMeasurement,
                              componentDelegate: componentDelegate)

        let rootView = componentView.rootView
        if rootView.superview == nil {
            owsAssertDebug(cellView.layoutMargins == .zero)
            owsAssertDebug(cellView.subviews.isEmpty)

            cellView.addSubview(rootView)
            cellView.layoutMargins = .zero
            rootView.autoPinEdgesToSuperviewEdges()
        }
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewUnreadIndicator()
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewUnreadIndicator else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let outerStack = componentView.outerStack
        let innerStack = componentView.innerStack
        let strokeView = componentView.strokeView
        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)

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
            outerStack.reset()
            titleLabel.removeFromSuperview()
            componentView.blurView?.removeFromSuperview()
            componentView.blurView = nil

            let contentView: UIView = {
                if hasWallpaper {

                    strokeView.backgroundColor = .ows_blackAlpha80

                    // blurView replaces innerStack, using the same size, layoutMargins, etc.
                    let blurView = buildBlurView(conversationStyle: conversationStyle)
                    componentView.blurView = blurView
                    blurView.clipsToBounds = true
                    blurView.layer.cornerRadius = 8
                    blurView.contentView.addSubview(titleLabel)
                    titleLabel.autoPinEdgesToSuperviewEdges(withInsets: innerStackConfig.layoutMargins)
                    titleLabel.setContentHuggingLow()

                    return ManualLayoutView.wrapSubviewUsingIOSAutoLayout(blurView)
                } else {
                    strokeView.backgroundColor = .ows_gray45

                    innerStack.reset()
                    innerStack.configure(config: innerStackConfig,
                                         cellMeasurement: cellMeasurement,
                                         measurementKey: Self.measurementKey_innerStack,
                                         subviews: [ titleLabel ])
                    return innerStack
                }
            }()

            outerStack.configure(config: outerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_outerStack,
                                 subviews: [
                                    strokeView,
                                    contentView
                                 ])
        }
    }

    private var titleLabelConfig: CVLabelConfig {
        CVLabelConfig(text: NSLocalizedString("MESSAGES_VIEW_UNREAD_INDICATOR",
                                              comment: "Indicator that separates read from unread messages."),
                      font: UIFont.ows_dynamicTypeFootnote.ows_semibold,
                      textColor: Theme.primaryTextColor,
                      numberOfLines: 0,
                      lineBreakMode: .byTruncatingTail,
                      textAlignment: .center)
    }

    private var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
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
        let innerStackInfo = innerStackMeasurement.measuredSize.asManualSubviewInfo
        let vStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_outerStack,
        subviewInfos: [
            strokeInfo,
            innerStackInfo
                                                        ])

        return vStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewUnreadIndicator: NSObject, CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "unreadIndicator.outerStack")
        fileprivate let innerStack = ManualStackView(name: "unreadIndicator.innerStack")

        fileprivate let titleLabel = UILabel()

        fileprivate var blurView: UIVisualEffectView?

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
            owsAssertDebug(isDedicatedCellView)

            titleLabel.text = nil

            if !isDedicatedCellView {
                outerStack.reset()
                innerStack.reset()

                blurView?.removeFromSuperview()
                blurView = nil

                hasWallpaper = false
                isDarkThemeEnabled = false
            }
        }
    }
}
