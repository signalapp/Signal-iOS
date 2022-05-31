//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI

class GiftBadgeView: ManualStackView {

    struct State {
        // TODO: (GB)
    }

    private static let measurementKey_outerStack = "GiftBadgeView.measurementKey_outerStack"
    private static var outerStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical, alignment: .leading, spacing: 4, layoutMargins: .zero)
    }

    func configureForRendering(state: State, cellMeasurement: CVCellMeasurement) {
        self.configure(
            config: Self.outerStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_outerStack,
            subviews: []
        )
    }

    static func measurement(for state: State, maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let outerStackMeasurement = ManualStackView.measure(
            config: self.outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: [CGSize(square: min(200, maxWidth)).asManualSubviewInfo]
        )

        return outerStackMeasurement.measuredSize
    }

}
