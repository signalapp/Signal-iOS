//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

enum ImageEditorError: Int, Error {
    case assertionError
    case invalidInput
}

enum ImageEditorItemType: Int {
    case test
    case stroke
    case text
    case blurRegions
}

// MARK: -

// Represented in a "ULO unit" coordinate system
// for source image.
//
// "ULO" coordinate system is "upper-left-origin".
//
// "Unit" coordinate system means values are expressed
// in terms of some other values, in this case the
// width and height of the source image.
//
// * 0.0 = left edge
// * 1.0 = right edge
// * 0.0 = top edge
// * 1.0 = bottom edge
typealias ImageEditorSample = CGPoint

// MARK: -

// Instances of ImageEditorItem should be treated
// as immutable, once configured.

class ImageEditorItem: NSObject {

    let itemId: String

    let itemType: ImageEditorItemType

    init(itemType: ImageEditorItemType) {
        self.itemId = UUID().uuidString
        self.itemType = itemType

        super.init()
    }

    init(itemId: String, itemType: ImageEditorItemType) {
        self.itemId = itemId
        self.itemType = itemType

        super.init()
    }

    // The scale with which to render this item's content
    // when rendering the "output" image for sending.
    func outputScale() -> CGFloat {
        return 1.0
    }
}
