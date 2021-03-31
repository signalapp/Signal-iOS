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

        let hStackView = componentView.hStackView
        let contentView = componentView.contentView
        let titleLabel = componentView.titleLabel

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled

        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        componentView.hasWallpaper = hasWallpaper

        let isReusing = componentView.rootView.superview != nil

        if !isReusing {
            hStackView.apply(config: hStackConfig)

            let leadingSpacer = UIView.hStretchingSpacer()
            let trailingSpacer = UIView.hStretchingSpacer()

            hStackView.addArrangedSubview(leadingSpacer)
            hStackView.addArrangedSubview(contentView)
            hStackView.addArrangedSubview(trailingSpacer)

            leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)
        }

        if !isReusing || themeHasChanged || wallpaperModeHasChanged {
            titleLabel.removeFromSuperview()

            componentView.blurView?.removeFromSuperview()
            componentView.blurView = nil

            if hasWallpaper {
                let blurView = buildBlurView(conversationStyle: conversationStyle)
                componentView.blurView = blurView

                contentView.addSubview(blurView)
                blurView.autoPinEdgesToSuperviewEdges()

                blurView.clipsToBounds = true
                blurView.layer.cornerRadius = 8

                blurView.contentView.addSubview(titleLabel)
            } else {
                contentView.addSubview(titleLabel)
            }

            titleLabel.autoPinWidthToSuperview(withMargin: titleHMargin)
            titleLabel.autoPinHeightToSuperview(withMargin: titleVMargin)
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

    private var titleHMargin: CGFloat { 10 }
    private var titleVMargin: CGFloat { 4 }

    private var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        // Full width.
        let width = maxWidth

        let cellLayoutMargins = self.cellLayoutMargins
        var height: CGFloat = cellLayoutMargins.totalHeight

        let availableWidth = max(0, maxWidth - cellLayoutMargins.totalWidth - (titleHMargin * 2))
        let labelSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: availableWidth)

        height += labelSize.height
        height += titleVMargin * 2

        return CGSizeCeil(CGSize(width: width, height: height))
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewDateHeader: NSObject, CVComponentView {

        fileprivate let hStackView = OWSStackView(name: "dateHeader.hStackView")
        fileprivate let contentView = UIView()
        fileprivate let titleLabel = UILabel()

        fileprivate var blurView: UIVisualEffectView?

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hStackView
        }

        // MARK: -

        override required init() {
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            if !isDedicatedCellView {
                hStackView.reset()

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
