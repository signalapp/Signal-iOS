//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class CVComponentLinkPreview: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .linkPreview }

    private let linkPreviewState: CVComponentState.LinkPreview

    init(
        itemModel: CVItemModel,
        linkPreviewState: CVComponentState.LinkPreview,
    ) {
        self.linkPreviewState = linkPreviewState

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewLinkPreview()
    }

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewLinkPreview else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let linkPreviewWrapper = componentView.linkPreviewWrapper
        let linkPreviewView = componentView.linkPreviewView

        linkPreviewView.backgroundColor = switch (conversationStyle.hasWallpaper, isIncoming) {
        case (true, true): UIColor.Signal.MaterialBase.fillSecondary
        case (_, true): UIColor.Signal.LightBase.fillSecondary
        case (_, false): UIColor.Signal.ColorBase.fillSecondary
        }
        linkPreviewView.layer.masksToBounds = true
        linkPreviewView.layer.cornerRadius = 10

        linkPreviewView.configureForRendering(
            state: linkPreviewState.state,
            isIncoming: isIncoming,
            cellMeasurement: cellMeasurement,
        )

        linkPreviewWrapper.configure(
            config: stackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_linkPreviewWrapper,
            subviews: [linkPreviewView],
        )
    }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: 0,
            layoutMargins: UIEdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 8),
        )
    }

    private static let measurementKey_linkPreviewWrapper = "CVComponentLinkPreview.measurementKey_linkPreviewWrapper"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let maxWidth = min(maxWidth, conversationStyle.maxMediaMessageWidth)
        let maxContentWidth = maxWidth - stackConfig.layoutMargins.totalWidth

        let linkPreviewSize = LinkPreviewView.measure(
            maxWidth: maxContentWidth,
            measurementBuilder: measurementBuilder,
            state: linkPreviewState.state,
            isDraft: false,
        )
        let subviewInfos = [linkPreviewSize.asManualSubviewInfo]
        let stackMeasurement = ManualStackView.measure(
            config: stackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_linkPreviewWrapper,
            subviewInfos: subviewInfos,
            maxWidth: maxWidth,
        )
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    override public func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        componentDelegate.didTapLinkPreview(linkPreviewState.linkPreview)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewLinkPreview: NSObject, CVComponentView {

        fileprivate let linkPreviewView = LinkPreviewView(draftDelegate: nil)
        fileprivate let linkPreviewWrapper = ManualStackView(name: "Link Preview Wrapper")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            linkPreviewWrapper
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            linkPreviewWrapper.reset()
            linkPreviewView.reset()
        }
    }
}
