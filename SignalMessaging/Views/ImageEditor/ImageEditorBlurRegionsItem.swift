//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class ImageEditorBlurRegionsItem: ImageEditorItem {
    // Expressed with "Unit" values. Both origin and size
    // are fractions of min(width, height) of the source
    // image.
    public typealias BlurBoundingBox = CGRect

    @objc
    public let unitBoundingBoxes: [BlurBoundingBox]

    @objc
    public init(unitBoundingBoxes: [BlurBoundingBox]) {
        self.unitBoundingBoxes = unitBoundingBoxes

        super.init(itemType: .blurRegions)
    }

    @objc
    public init(itemId: String, unitBoundingBoxes: [BlurBoundingBox]) {
        self.unitBoundingBoxes = unitBoundingBoxes

        super.init(itemId: itemId, itemType: .blurRegions)
    }
}
