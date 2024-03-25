//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

class ImageEditorBlurRegionsItem: ImageEditorItem {
    // Expressed with "Unit" values. Both origin and size
    // are fractions of min(width, height) of the source
    // image.
    typealias BlurBoundingBox = CGRect

    let unitBoundingBoxes: [BlurBoundingBox]

    init(unitBoundingBoxes: [BlurBoundingBox]) {
        self.unitBoundingBoxes = unitBoundingBoxes

        super.init(itemType: .blurRegions)
    }

    init(itemId: String, unitBoundingBoxes: [BlurBoundingBox]) {
        self.unitBoundingBoxes = unitBoundingBoxes

        super.init(itemId: itemId, itemType: .blurRegions)
    }
}
