//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

        let linkPreviewView = LinkPreviewView(draftDelegate: nil)
        linkPreviewView.state = linkPreviewState.state

        let hostView = componentView.hostView
        hostView.addSubview(linkPreviewView)
        linkPreviewView.autoPinEdgesToSuperviewEdges()
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return LinkPreviewView.measure(withState: linkPreviewState.state).ceil
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
