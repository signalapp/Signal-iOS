//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

final class ImageEditorStickerItem: ImageEditorItem, ImageEditorTransformable {
    let stickerInfo: StickerInfo
    let referenceImageWidth: CGFloat
    let unitCenter: ImageEditorSample
    let rotationRadians: CGFloat
    let scaling: CGFloat

    init(
        stickerInfo: StickerInfo,
        referenceImageWidth: CGFloat,
        unitCenter: ImageEditorSample = .unitMidpoint,
        rotationRadians: CGFloat,
        scaling: CGFloat
    ) {
        self.stickerInfo = stickerInfo
        self.referenceImageWidth = referenceImageWidth
        self.unitCenter = unitCenter
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        super.init(itemType: .sticker)
    }

    private init(
        itemId: String,
        stickerInfo: StickerInfo,
        referenceImageWidth: CGFloat,
        unitCenter: ImageEditorSample,
        rotationRadians: CGFloat,
        scaling: CGFloat
    ) {
        self.stickerInfo = stickerInfo
        self.referenceImageWidth = referenceImageWidth
        self.unitCenter = unitCenter
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        super.init(itemId: itemId, itemType: .sticker)
    }

    func copy(unitCenter: ImageEditorSample) -> ImageEditorStickerItem {
        ImageEditorStickerItem(
            itemId: self.itemId,
            stickerInfo: self.stickerInfo,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: unitCenter,
            rotationRadians: self.rotationRadians,
            scaling: self.scaling
        )
    }

    func copy(scaling: CGFloat, rotationRadians: CGFloat) -> ImageEditorStickerItem {
        ImageEditorStickerItem(
            itemId: self.itemId,
            stickerInfo: self.stickerInfo,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: self.unitCenter,
            rotationRadians: rotationRadians,
            scaling: scaling
        )
    }

    override func outputScale() -> CGFloat {
        return scaling
    }
}
