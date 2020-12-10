//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
            cellView.layoutMargins = cellLayoutMargins
            rootView.autoPinEdgesToSuperviewMargins()
        }
    }

    private var cellLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: 8,
                     leading: conversationStyle.headerGutterLeading,
                     bottom: 8,
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

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        // Full width.
        let width = maxWidth

        let cellLayoutMargins = self.cellLayoutMargins
        var height: CGFloat = cellLayoutMargins.totalHeight

        let availableWidth = max(0, maxWidth - cellLayoutMargins.totalWidth)
        let labelSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: availableWidth)

        height += labelSize.height

        return CGSizeCeil(CGSize(width: width, height: height))
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewDateHeader: NSObject, CVComponentView {

        fileprivate let titleLabel = UILabel()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            titleLabel
        }

        // MARK: -

        override required init() {
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            if !isDedicatedCellView {
                titleLabel.removeFromSuperview()
            }
            titleLabel.text = nil
        }
    }
}
