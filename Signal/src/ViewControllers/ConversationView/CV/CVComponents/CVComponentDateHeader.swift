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
            cellView.layoutMargins = .zero
            rootView.autoPinEdgesToSuperviewEdges()
        }
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

        let outerStack = componentView.outerStack
        let innerStack = componentView.innerStack

        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled

        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        componentView.hasWallpaper = hasWallpaper

        let isReusing = componentView.rootView.superview != nil

        if !isReusing || themeHasChanged || wallpaperModeHasChanged {
            innerStack.reset()
            outerStack.reset()
            titleLabel.removeFromSuperview()
            componentView.blurView?.removeFromSuperview()
            componentView.blurView = nil

            let contentView: UIView = {
                if hasWallpaper,
                   let innerStackSize = cellMeasurement.size(key: Self.measurementKey_innerStackSize) {
                    // blurView replaces innerStack, using the same size, layoutMargins, etc.

                    let blurView = buildBlurView(conversationStyle: conversationStyle)
                    componentView.blurView = blurView
                    blurView.clipsToBounds = true
                    blurView.layer.cornerRadius = 8
                    // blurView will be arranged by manual layout, but if we don't
                    // constrain its width and height, its internal constraints will
                    // be ambiguous.
                    blurView.autoSetDimensions(to: innerStackSize)

                    blurView.contentView.addSubview(titleLabel)
                    titleLabel.autoPinEdgesToSuperviewEdges(withInsets: innerStackConfig.layoutMargins)
                    titleLabel.setContentHuggingLow()

                    return blurView
                } else {
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
    private static let measurementKey_innerStackSize = "CVComponentDateHeader.measurementKey_innerStackSize"

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
        measurementBuilder.setSize(key: Self.measurementKey_innerStackSize,
                                   size: innerStackMeasurement.measuredSize)
        let innerStackInfo = innerStackMeasurement.measuredSize.asManualSubviewInfo
        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_outerStack,
                                                        subviewInfos: [ innerStackInfo ])
        return outerStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewDateHeader: NSObject, CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "dateHeader.outerStackView")
        fileprivate let innerStack = ManualStackView(name: "dateHeader.innerStackView")
        fileprivate let titleLabel = UILabel()

        fileprivate var blurView: UIView?

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        public var isDedicatedCellView = false

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

                titleLabel.removeFromSuperview()

                blurView?.removeFromSuperview()
                blurView = nil

                hasWallpaper = false
                isDarkThemeEnabled = false
            }
            titleLabel.text = nil
        }
    }
}
