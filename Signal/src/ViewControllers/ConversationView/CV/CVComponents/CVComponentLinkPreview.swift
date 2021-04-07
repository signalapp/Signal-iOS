//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentLinkPreview: CVComponentBase, CVComponent {

    private let linkPreviewState: CVComponentState.LinkPreview

    init(itemModel: CVItemModel,
         linkPreviewState: CVComponentState.LinkPreview) {
        self.linkPreviewState = linkPreviewState

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewLinkPreview()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewLinkPreview else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        // TODO:
        let linkPreviewView = LinkPreviewView(draftDelegate: nil)
        linkPreviewView.state = linkPreviewState.state

        let stackView = componentView.stackView
        stackView.reset()
        stackView.configure(config: stackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_stackView,
                            subviews: [ linkPreviewView ])
    }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private static let measurementKey_stackView = "CVComponentLinkPreview.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let linkPreviewSize = LinkPreviewView.measure(withState: linkPreviewState.state).ceil
        let stackMeasurement = ManualStackView.measure(config: stackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_stackView,
                                                            subviewInfos: [ linkPreviewSize.asManualSubviewInfo ])
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        componentDelegate.cvc_didTapLinkPreview(linkPreviewState.linkPreview)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewLinkPreview: NSObject, CVComponentView {

        // For now we simply use this view to host LinkPreviewView.
        //
        // TODO: Reuse LinkPreviewView.
        fileprivate let stackView = ManualStackView(name: "LinkPreview.stackView")

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
