//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentQuotedReply: CVComponentBase, CVComponent {

    private let quotedReply: CVComponentState.QuotedReply
    private var quotedReplyModel: OWSQuotedReplyModel {
        quotedReply.quotedReplyModel
    }
    private var displayableQuotedText: DisplayableText? {
        quotedReply.displayableQuotedText
    }
    private let sharpCornersForQuotedMessage: OWSDirectionalRectCorner

    init(itemModel: CVItemModel,
         quotedReply: CVComponentState.QuotedReply,
         sharpCornersForQuotedMessage: OWSDirectionalRectCorner) {
        self.quotedReply = quotedReply
        self.sharpCornersForQuotedMessage = sharpCornersForQuotedMessage

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewQuotedReply()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewQuotedReply else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let quotedMessageView = QuotedMessageView(state: quotedReply.viewState,
                                                  sharpCorners: sharpCornersForQuotedMessage)
        quotedMessageView.createContents()
        quotedMessageView.layoutMargins = .zero
        quotedMessageView.translatesAutoresizingMaskIntoConstraints = false

        let hostView = componentView.hostView
        hostView.addSubview(quotedMessageView)
        quotedMessageView.autoPinEdgesToSuperviewEdges()
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return QuotedMessageView.measure(state: quotedReply.viewState, maxWidth: maxWidth).ceil
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        componentDelegate.cvc_didTapQuotedReply(quotedReplyModel)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewQuotedReply: NSObject, CVComponentView {

        // For now we simply use this view to host QuotedMessageView.
        //
        // TODO: Reuse QuotedMessageView.
        fileprivate let hostView = UIView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hostView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            hostView.removeAllSubviews()
        }
    }
}
