//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
                          swipeToReplyState: CVSwipeToReplyState,
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

        let strokeView = componentView.strokeView
        let titleLabel = componentView.titleLabel
        titleLabelConfig.applyForRendering(label: titleLabel)

        let isReusing = titleLabel.superview != nil
        if !isReusing {
            let stackView = componentView.stackView
            stackView.apply(config: stackViewConfig)
            stackView.addArrangedSubview(strokeView)
            stackView.addArrangedSubview(titleLabel)
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

    private var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 12,
                          layoutMargins: cellLayoutMargins)
    }

    private var cellLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        // Full width.
        let width = maxWidth

        let titleHeight = titleLabelConfig.font.lineHeight
        let height = (strokeHeight + stackViewConfig.spacing + titleHeight + cellLayoutMargins.totalHeight)

        return CGSizeCeil(CGSize(width: width, height: height))
    }

    private let strokeHeight: CGFloat = 1

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewUnreadIndicator: NSObject, CVComponentView {

        fileprivate let stackView = OWSStackView(name: "UnreadIndicator")

        fileprivate let titleLabel = UILabel()

        fileprivate let strokeView = UIView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        // MARK: -

        override required init() {
            strokeView.backgroundColor = UIColor.ows_gray45
            strokeView.autoSetDimension(.height, toSize: 1)
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            titleLabel.text = nil

            if !isDedicatedCellView {
                stackView.reset()
            }
        }
    }
}
