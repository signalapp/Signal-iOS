//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

        // TODO:
        let quotedMessageView = QuotedMessageView(state: quotedReply.viewState,
                                                  sharpCorners: sharpCornersForQuotedMessage)
        quotedMessageView.createContents()
        quotedMessageView.layoutMargins = .zero
        quotedMessageView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = componentView.stackView
        stackView.reset()
        stackView.configure(config: stackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_stackView,
                            subviews: [ quotedMessageView ])
    }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private static let measurementKey_stackView = "CVComponentQuotedReply.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let quotedMessageSize = QuotedMessageView.measure(state: quotedReply.viewState, maxWidth: maxWidth).ceil
        let stackMeasurement = ManualStackView.measure(config: stackConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: [ quotedMessageSize.asManualSubviewInfo ])
        return stackMeasurement.measuredSize
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
        fileprivate let stackView = ManualStackView(name: "QuotedReply.stackView")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            stackView.reset()
        }
    }
}
