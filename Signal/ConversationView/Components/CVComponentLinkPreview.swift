//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentLinkPreview: CVComponentBase, CVComponent {

    var componentKey: CVComponentKey { .linkPreview }

    private let linkPreview: LinkPreviewState

    init(
        itemModel: CVItemModel,
        linkPreview: LinkPreviewState,
    ) {
        self.linkPreview = linkPreview

        super.init(itemModel: itemModel)
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewLinkPreview()
    }

    func configureForRendering(
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

        linkPreviewView.configureForRendering(
            linkPreview: linkPreview,
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

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let maxWidth = min(maxWidth, conversationStyle.maxMediaMessageWidth)
        let maxContentWidth = maxWidth - stackConfig.layoutMargins.totalWidth

        let linkPreviewSize = CVLinkPreviewView.measure(
            maxWidth: maxContentWidth,
            measurementBuilder: measurementBuilder,
            linkPreview: linkPreview,
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

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url.")
            return false
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid url: \(urlString).")
            return false
        }
        componentDelegate.didTapLinkPreview(url: url)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    class CVComponentViewLinkPreview: NSObject, CVComponentView {

        fileprivate let linkPreviewView = CVLinkPreviewView()
        fileprivate let linkPreviewWrapper = ManualStackView(name: "Link Preview Wrapper")

        var isDedicatedCellView = false

        var rootView: UIView {
            linkPreviewWrapper
        }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            linkPreviewWrapper.reset()
            linkPreviewView.reset()
        }
    }
}
