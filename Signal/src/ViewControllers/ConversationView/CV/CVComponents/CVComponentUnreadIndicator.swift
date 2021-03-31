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
        let hStackView = componentView.hStackView
        let contentView = componentView.contentView
        let strokeView = componentView.strokeView
        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)

        let isReusing = componentView.rootView.superview != nil
        if !isReusing {
            vStackView.apply(config: vStackConfig)
            hStackView.apply(config: hStackConfig)

            vStackView.addArrangedSubview(strokeView)
            vStackView.addArrangedSubview(hStackView)

            let leadingSpacer = UIView.hStretchingSpacer()
            let trailingSpacer = UIView.hStretchingSpacer()

            hStackView.addArrangedSubview(leadingSpacer)
            hStackView.addArrangedSubview(contentView)
            hStackView.addArrangedSubview(trailingSpacer)

            leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)

            contentView.addSubview(titleLabel)
            titleLabel.autoPinWidthToSuperview(withMargin: titleHMargin)
            titleLabel.autoPinHeightToSuperview(withMargin: titleVMargin)
        }

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled

        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        componentView.hasWallpaper = hasWallpaper

        if !isReusing || themeHasChanged || wallpaperModeHasChanged {
            componentView.blurView?.removeFromSuperview()
            componentView.blurView = nil

            if hasWallpaper {
                let blurView = buildBlurView(conversationStyle: conversationStyle)
                componentView.blurView = blurView

                contentView.insertSubview(blurView, at: 0)
                blurView.autoPinEdgesToSuperviewEdges()

                blurView.clipsToBounds = true
                blurView.layer.cornerRadius = 8

                strokeView.backgroundColor = .ows_blackAlpha80
            } else {
                strokeView.backgroundColor = .ows_gray45
            }
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
                          alignment: .fill,
                          spacing: 12,
                          layoutMargins: cellLayoutMargins)
    }

    private var titleHMargin: CGFloat { 10 }
    private var titleVMargin: CGFloat { 4 }

    private var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private var cellLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        // Full width.
        let width = maxWidth

        let titleHeight = titleLabelConfig.font.lineHeight
        let height = (strokeHeight + vStackConfig.spacing + titleHeight + cellLayoutMargins.totalHeight + (titleVMargin * 2))

        return CGSizeCeil(CGSize(width: width, height: height))
    }

    private let strokeHeight: CGFloat = 1

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewUnreadIndicator: NSObject, CVComponentView {

        fileprivate let vStackView = OWSStackView(name: "unreadIndicator.vStackView")
        fileprivate let hStackView = OWSStackView(name: "unreadIndicator.hStackView")

        fileprivate let contentView = UIView()
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

        override required init() {
            strokeView.autoSetDimension(.height, toSize: 1)
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            titleLabel.text = nil

            if !isDedicatedCellView {
                vStackView.reset()
                hStackView.reset()

                blurView?.removeFromSuperview()
                blurView = nil

                hasWallpaper = false
                isDarkThemeEnabled = false
            }
        }
    }
}
