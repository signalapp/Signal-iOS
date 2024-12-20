//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class CVComponentQuotedReply: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .quotedReply }

    private let quotedReply: CVComponentState.QuotedReply
    private var quotedReplyModel: QuotedReplyModel {
        quotedReply.quotedReplyModel
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

    public override func updateScrollingContent(componentView: CVComponentView) {
        super.updateScrollingContent(componentView: componentView)

        guard let componentView = componentView as? CVComponentViewQuotedReply else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        componentView.quotedMessageView.updateAppearance()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewQuotedReply else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let quotedMessageView = componentView.quotedMessageView
        let adapter = QuotedMessageViewAdapter(interactionUniqueId: interaction.uniqueId)
        quotedMessageView.configureForRendering(state: quotedReply.viewState,
                                                delegate: adapter,
                                                componentDelegate: componentDelegate,
                                                sharpCorners: sharpCornersForQuotedMessage,
                                                cellMeasurement: cellMeasurement)
    }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return QuotedMessageView.measure(state: quotedReply.viewState,
                                         maxWidth: maxWidth,
                                         measurementBuilder: measurementBuilder)
    }

    // MARK: - Events

    public override func handleTap(sender: UIGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        componentDelegate.didTapQuotedReply(quotedReplyModel)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewQuotedReply: NSObject, CVComponentView {

        fileprivate let quotedMessageView = QuotedMessageView(name: "quotedMessageView")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            quotedMessageView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {
            quotedMessageView.setIsCellVisible(isCellVisible)
        }

        public func reset() {
            quotedMessageView.reset()
        }

    }
}

extension CVComponentQuotedReply: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        let format = OWSLocalizedString(
            "QUOTED_REPLY_ACCESSIBILITY_LABEL_FORMAT",
            comment: "Accessibility label stating the author of the message to which you are replying. Embeds: {{ the author of the message to which you are replying }}."
        )

        if quotedReply.quotedReplyModel.isOriginalMessageAuthorLocalUser {
            return String(format: format, CommonStrings.you)
        } else {
            return String(
                format: format,
                self.quotedReply.viewState.quotedAuthorName
            )
        }
    }
}

// MARK: -

private class QuotedMessageViewAdapter: QuotedMessageViewDelegate {

    private let interactionUniqueId: String

    init(interactionUniqueId: String) {
        self.interactionUniqueId = interactionUniqueId
    }

    func didTapDownloadQuotedReplyAttachment(_ quotedReply: QuotedReplyModel) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            guard let message = TSMessage.anyFetchMessage(uniqueId: interactionUniqueId, transaction: tx) else {
                return
            }
            DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(
                message,
                priority: .userInitiated,
                tx: tx.asV2Write
            )
        }
    }

    func didCancelQuotedReply() {
        owsFailDebug("Unexpected method invocation.")
    }
}
