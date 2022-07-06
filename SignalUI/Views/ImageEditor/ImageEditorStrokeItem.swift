//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit

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

    class func defaultUnitStrokeWidth(forStrokeType strokeType: StrokeType) -> CGFloat {
        switch strokeType {
        case .pen:
            return 0.02
        case .highlighter:
            return 0.04
        case .blur:
            return 0.05
        }
    }

    class func strokeWidth(forUnitStrokeWidth unitStrokeWidth: CGFloat, dstSize: CGSize) -> CGFloat {
        return CGFloatClamp01(unitStrokeWidth) * min(dstSize.width, dstSize.height)
    }
}
