//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

        let contentView = componentView.contentView

        if isBorderlessWithWallpaper {
            contentView.layoutMargins = contentViewBorderlessMargins
            contentView.backgroundColor = itemModel.conversationStyle.bubbleColor(isIncoming: isIncoming)
            contentView.layer.cornerRadius = 11
            contentView.clipsToBounds = true
        } else {
            contentView.layoutMargins = .zero
            contentView.backgroundColor = .clear
            contentView.layer.cornerRadius = 0
            contentView.clipsToBounds = false
        }

        labelConfig.applyForRendering(label: componentView.label)
    }

    private var isBorderlessWithWallpaper: Bool {
        return isBorderless && conversationStyle.hasWallpaper
    }

    private var labelConfig: CVLabelConfig {
        CVLabelConfig(attributedText: senderName,
                      font: UIFont.ows_dynamicTypeCaption1.ows_semibold,
                      textColor: bodyTextColor,
                      lineBreakMode: .byTruncatingTail)
    }

    private var contentViewBorderlessMargins: UIEdgeInsets {
        UIEdgeInsets(hMargin: 12, vMargin: 3)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var maxWidth = maxWidth
        if isBorderlessWithWallpaper { maxWidth -= contentViewBorderlessMargins.totalWidth }

        var size = CVText.measureLabel(config: labelConfig, maxWidth: maxWidth)

        if isBorderlessWithWallpaper {
            size.width += contentViewBorderlessMargins.totalWidth
            size.height += contentViewBorderlessMargins.totalHeight
        }

        return size
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewSenderName: NSObject, CVComponentView {

        fileprivate let label = UILabel()
        fileprivate lazy var contentView: UIView = {
            let contentView = UIView()
            contentView.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()
            return contentView
        }()
        fileprivate lazy var outerView: UIView = {
            let leadingSpacer = UIView.hStretchingSpacer()
            let trailingSpacer = UIView.hStretchingSpacer()
            let outerView = UIStackView(arrangedSubviews: [leadingSpacer, contentView, trailingSpacer])
            outerView.axis = .horizontal
            return outerView
        }()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            outerView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            label.text = nil
        }
    }
}
