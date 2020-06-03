//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class ImageEditorStrokeItem: ImageEditorItem {
    // Until we need to serialize these items,
    // just use UIColor.
    @objc
    public let color: UIColor?

    @objc
    public let isBlur: Bool

    public typealias StrokeSample = ImageEditorSample

    @objc
    public let unitSamples: [StrokeSample]

    // Expressed as a "Unit" value as a fraction of
    // min(width, height) of the destination viewport.
    @objc
    public let unitStrokeWidth: CGFloat

    @objc
    public init(color: UIColor? = nil,
                isBlur: Bool = false,
                unitSamples: [StrokeSample],
                unitStrokeWidth: CGFloat) {
        self.color = color
        self.isBlur = isBlur
        self.unitSamples = unitSamples
        self.unitStrokeWidth = unitStrokeWidth

        super.init(itemType: .stroke)
    }

    @objc
    public init(itemId: String,
                color: UIColor? = nil,
                isBlur: Bool = false,
                unitSamples: [StrokeSample],
                unitStrokeWidth: CGFloat) {
        self.color = color
        self.isBlur = isBlur
        self.unitSamples = unitSamples
        self.unitStrokeWidth = unitStrokeWidth

        super.init(itemId: itemId, itemType: .stroke)
    }

    @objc
    public class func defaultUnitStrokeWidth() -> CGFloat {
        return 0.02
    }

    @objc
    public class func strokeWidth(forUnitStrokeWidth unitStrokeWidth: CGFloat,
                                  dstSize: CGSize) -> CGFloat {
        return CGFloatClamp01(unitStrokeWidth) * min(dstSize.width, dstSize.height)
    }
}
