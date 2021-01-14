//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentSenderName: CVComponentBase, CVComponent {

    private let senderName: NSAttributedString

    init(itemModel: CVItemModel, senderName: NSAttributedString) {
        self.senderName = senderName

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewSenderName()
    }

    private var bodyTextColor: UIColor {
        guard let message = interaction as? TSMessage else {
            return .black
        }
        return conversationStyle.bubbleTextColor(message: message)
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewSenderName else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        labelConfig.applyForRendering(label: componentView.label)
    }

    private var labelConfig: CVLabelConfig {
        CVLabelConfig(attributedText: senderName,
                      font: UIFont.ows_dynamicTypeCaption1.ows_semibold,
                      textColor: bodyTextColor,
                      lineBreakMode: .byTruncatingTail)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return CVText.measureLabel(config: labelConfig, maxWidth: maxWidth)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewSenderName: NSObject, CVComponentView {

        fileprivate let label = UILabel()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            label
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            label.text = nil
        }
    }
}
