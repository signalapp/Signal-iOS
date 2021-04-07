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
            rootView.autoPinEdgesToSuperviewMargins()
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

        let vStackView = componentView.vStackView
        let contentView = componentView.contentView
        let strokeView = componentView.strokeView
        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled

        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        componentView.hasWallpaper = hasWallpaper

        let isReusing = componentView.rootView.superview != nil
        if !isReusing || themeHasChanged || wallpaperModeHasChanged {
            titleLabel.removeFromSuperview()
            componentView.blurView?.removeFromSuperview()
            componentView.blurView = nil

            let contentView: UIView = {
                if hasWallpaper {
                    strokeView.backgroundColor = .ows_blackAlpha80

                    let blurView = buildBlurView(conversationStyle: conversationStyle)
                    componentView.blurView = blurView

                    contentView.insertSubview(blurView, at: 0)
                    blurView.autoPinEdgesToSuperviewEdges()

                    blurView.clipsToBounds = true
                    blurView.layer.cornerRadius = 8

                    blurView.contentView.addSubview(titleLabel)
                    titleLabel.autoPinEdgesToSuperviewEdges(withInsets: titleMargins)
                    return blurView
                } else {
                    strokeView.backgroundColor = .ows_gray45

                    let noBlurView = componentView.noBlurView
                    noBlurView.reset()
                    noBlurView.configure(config: noBlurConfig,
                                         cellMeasurement: cellMeasurement,
                                         measurementKey: Self.measurementKey_noBlur,
                                         subviews: [ titleLabel ])
                    return noBlurView
                }
            }()

            vStackView.reset()
            vStackView.configure(config: vStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_vStackView,
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

    private var vStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 12,
                          layoutMargins: UIEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    private var titleMargins: UIEdgeInsets { UIEdgeInsets(hMargin: 10, vMargin: 4) }

    private var noBlurConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: titleMargins)
    }

    private static let measurementKey_vStackView = "CVComponentUnreadIndicator.measurementKey_vStackView"
    private static let measurementKey_noBlur = "CVComponentUnreadIndicator.measurementKey_noBlur"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let availableWidth = max(0, maxWidth -
                                    (noBlurConfig.layoutMargins.totalWidth +
                                        vStackConfig.layoutMargins.totalWidth))
        let labelSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: availableWidth)
        let strokeSize = CGSize(width: 0, height: 1)

        let labelInfo = labelSize.asManualSubviewInfo
        let noBlurMeasurement = ManualStackView.measure(config: noBlurConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_noBlur,
        subviewInfos: [ labelInfo ])

        let strokeInfo = strokeSize.asManualSubviewInfo(hasFixedHeight: true)
        let noBlurInfo = noBlurMeasurement.measuredSize.asManualSubviewInfo
        let vStackMeasurement = ManualStackView.measure(config: vStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_vStackView,
        subviewInfos: [
            strokeInfo,
            noBlurInfo
                                                        ])

        return vStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewUnreadIndicator: NSObject, CVComponentView {

        fileprivate let vStackView = ManualStackView(name: "unreadIndicator.vStackView")
        fileprivate let noBlurView = ManualStackView(name: "unreadIndicator.noBlurView")

        fileprivate let contentView = UIView.container()
        fileprivate let titleLabel = UILabel()

        fileprivate var blurView: UIVisualEffectView?

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        fileprivate let strokeView = UIView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            vStackView
        }

        // MARK: -

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            titleLabel.text = nil

            if !isDedicatedCellView {
                vStackView.reset()
                noBlurView.reset()

                blurView?.removeFromSuperview()
                blurView = nil

                hasWallpaper = false
                isDarkThemeEnabled = false
            }
        }
    }
}
