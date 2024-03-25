//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class ImageEditorStrokeItem: ImageEditorItem {

    enum StrokeType: Equatable {
        case pen
        case highlighter
        case blur
    }

    // Until we need to serialize these items,
    // just use UIColor.
    let color: UIColor?

    let strokeType: StrokeType

    typealias StrokeSample = ImageEditorSample

    let unitSamples: [StrokeSample]

    // Expressed as a "Unit" value as a fraction of
    // min(width, height) of the destination viewport.
    let unitStrokeWidth: CGFloat

    func strokeWidth(forDstSize dstSize: CGSize) -> CGFloat {
        ImageEditorStrokeItem.strokeWidth(forUnitStrokeWidth: unitStrokeWidth, dstSize: dstSize)
    }

    init(color: UIColor? = nil,
         strokeType: StrokeType,
         unitSamples: [StrokeSample],
         unitStrokeWidth: CGFloat) {
        self.color = color
        self.strokeType = strokeType
        self.unitSamples = unitSamples
        self.unitStrokeWidth = unitStrokeWidth

        super.init(itemType: .stroke)
    }

    init(itemId: String,
         color: UIColor? = nil,
         strokeType: StrokeType,
         unitSamples: [StrokeSample],
         unitStrokeWidth: CGFloat) {
        self.color = color
        self.strokeType = strokeType
        self.unitSamples = unitSamples
        self.unitStrokeWidth = unitStrokeWidth

        super.init(itemId: itemId, itemType: .stroke)
    }

    // First value is default unitStrokeWidth for a given stroke type.
    // Second value is the power to raise adjustment factor (slider value) if the factor is greater than 1.
    private class func metrics(forStrokeType strokeType: StrokeType) -> (CGFloat, CGFloat) {
        switch strokeType {
        case .pen:
            return (0.02, 3)
        case .highlighter:
            return (0.04, 3)
        case .blur:
            return (0.05, 2)
        }
    }

    class func unitStrokeWidth(forStrokeType strokeType: StrokeType,
                               widthAdjustmentFactor adjustmentFactor: CGFloat) -> CGFloat {
        let (defaultWidth, power) = metrics(forStrokeType: strokeType)
        let multiplier: CGFloat
        if adjustmentFactor > 1 {
            multiplier = pow(adjustmentFactor, power)
        } else {
            multiplier = adjustmentFactor
        }
        return defaultWidth * multiplier
    }

    class func strokeWidth(forUnitStrokeWidth unitStrokeWidth: CGFloat, dstSize: CGSize) -> CGFloat {
        return CGFloatClamp01(unitStrokeWidth) * min(dstSize.width, dstSize.height)
    }
}
