//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public class CVComponentGiftBadge: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .giftBadge }

    private let giftBadgeState: CVComponentState.GiftBadge

    private var viewState: GiftBadgeView.State {
        GiftBadgeView.State()
    }

    init(itemModel: CVItemModel, giftBadgeState: CVComponentState.GiftBadge) {
        self.giftBadgeState = giftBadgeState
        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewGiftBadge()
    }

    public func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate
    ) {
        guard let componentView = componentView as? CVComponentViewGiftBadge else {
            owsFailDebug("unexpected componentView")
            componentView.reset()
            return
        }

        componentView.giftBadgeView.configureForRendering(state: self.viewState, cellMeasurement: cellMeasurement)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        return GiftBadgeView.measurement(for: self.viewState, maxWidth: maxWidth, measurementBuilder: measurementBuilder)
    }

    public class CVComponentViewGiftBadge: NSObject, CVComponentView {
        fileprivate let giftBadgeView = GiftBadgeView(name: "GiftBadgeView")

        // TODO: (GB)
        public var isDedicatedCellView = false

        public var rootView: UIView { giftBadgeView }

        // TODO: (GB)
        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            giftBadgeView.reset()
        }
    }
}
