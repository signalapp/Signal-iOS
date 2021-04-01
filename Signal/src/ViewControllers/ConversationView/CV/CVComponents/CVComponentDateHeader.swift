//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentDateHeader: CVComponentBase, CVRootComponent {

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
            cellView.layoutMargins = cellLayoutMargins
            rootView.autoPinEdgesToSuperviewMargins()
        }
    }

    private var cellLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: 0,
                     leading: conversationStyle.headerGutterLeading,
                     bottom: 0,
                     trailing: conversationStyle.headerGutterTrailing)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewDateHeader()
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewDateHeader else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        titleLabelConfig.applyForRendering(label: componentView.titleLabel)

        let vStackView = componentView.vStackView
        let titleLabel = componentView.titleLabel

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
                    let blurView = buildBlurView(conversationStyle: conversationStyle)
                    componentView.blurView = blurView
                    blurView.autoPinEdgesToSuperviewEdges()
                    blurView.clipsToBounds = true
                    blurView.layer.cornerRadius = 8
                    blurView.contentView.addSubview(titleLabel)
                    titleLabel.autoPinEdgesToSuperviewEdges(withInsets: titleMargins)
                    return blurView
                } else {
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
                                 subviews: [ contentView ])
        }

        componentView.rootView.accessibilityLabel = titleLabelConfig.stringValue
        componentView.rootView.isAccessibilityElement = true
        componentView.rootView.accessibilityTraits = .header
    }

    static func buildState(interaction: TSInteraction) -> State {
        let date = Date(millisecondsSince1970: interaction.timestamp)
        let text = DateUtil.formatDate(forConversationDateBreaks: date)
        return State(text: text)
    }

    private var titleLabelConfig: CVLabelConfig {
        return CVLabelConfig(text: dateHeaderState.text,
                             font: UIFont.ows_dynamicTypeFootnote.ows_semibold,
                             textColor: Theme.secondaryTextAndIconColor,
                             lineBreakMode: .byTruncatingTail,
                             textAlignment: .center)
    }

    private var titleMargins: UIEdgeInsets { UIEdgeInsets(hMargin: 10, vMargin: 4) }

    private var vStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private var noBlurConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: titleMargins)
    }

    private static let measurementKey_vStackView = "CVComponentDateHeader.measurementKey_vStackView"
    private static let measurementKey_noBlur = "CVComponentDateHeader.measurementKey_noBlur"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let cellLayoutMargins = self.cellLayoutMargins

        let availableWidth = max(0, maxWidth -
                                    (cellLayoutMargins.totalWidth +
                                        noBlurConfig.layoutMargins.totalWidth +
                                        vStackConfig.layoutMargins.totalWidth))
        let labelSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: availableWidth)

        let labelInfo = ManualStackSubviewInfo(measuredSize: labelSize)
        let noBlurMeasurement = ManualStackView.measure(config: noBlurConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_noBlur,
                                                        subviewInfos: [ labelInfo ])

        let noBlurInfo = ManualStackSubviewInfo(measuredSize: noBlurMeasurement.measuredSize)
        let vStackMeasurement = ManualStackView.measure(config: vStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_vStackView,
                                                        subviewInfos: [ noBlurInfo ])

        return vStackMeasurement.measuredSize + cellLayoutMargins.totalSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewDateHeader: NSObject, CVComponentView {

        fileprivate let vStackView = ManualStackView(name: "dateHeader.vStackView")
        fileprivate let titleLabel = UILabel()

        fileprivate var blurView: UIVisualEffectView?
        fileprivate let noBlurView = ManualStackView(name: "dateHeader.noBlurView")

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        public var isDedicatedCellView = false

        public var rootView: UIView {
            vStackView
        }

        // MARK: -

        override required init() {
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            if !isDedicatedCellView {
                vStackView.reset()

                titleLabel.removeFromSuperview()

                blurView?.removeFromSuperview()
                blurView = nil

                noBlurView.reset()
                noBlurView.removeFromSuperview()

                hasWallpaper = false
                isDarkThemeEnabled = false
            }
            titleLabel.text = nil
        }
    }
}
