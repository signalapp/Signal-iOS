//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

final class ImageEditorStickerItem: ImageEditorItem, ImageEditorTransformable {
    let sticker: EditorSticker
    /// The timestamp for when the sticker item was created. Used for displaying clock stickers.
    ///
    /// This timestamp is stored so that the time displayed on a clock sticker
    /// does not change from when it's placed on the image to when it's
    /// rendered in the final image.
    let date: Date
    let referenceImageWidth: CGFloat
    let unitCenter: ImageEditorSample
    let rotationRadians: CGFloat
    let scaling: CGFloat

    init(
        sticker: EditorSticker,
        referenceImageWidth: CGFloat,
        unitCenter: ImageEditorSample = .unitMidpoint,
        rotationRadians: CGFloat,
        scaling: CGFloat
    ) {
        self.sticker = sticker
        self.date = Date()
        self.referenceImageWidth = referenceImageWidth
        self.unitCenter = unitCenter
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        super.init(itemType: .sticker)
    }

    private init(
        itemId: String,
        sticker: EditorSticker,
        date: Date,
        referenceImageWidth: CGFloat,
        unitCenter: ImageEditorSample,
        rotationRadians: CGFloat,
        scaling: CGFloat
    ) {
        self.sticker = sticker
        self.date = date
        self.referenceImageWidth = referenceImageWidth
        self.unitCenter = unitCenter
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        super.init(itemId: itemId, itemType: .sticker)
    }

    func copy(unitCenter: ImageEditorSample) -> ImageEditorStickerItem {
        ImageEditorStickerItem(
            itemId: self.itemId,
            sticker: self.sticker,
            date: self.date,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: unitCenter,
            rotationRadians: self.rotationRadians,
            scaling: self.scaling
        )
    }

    func copy(scaling: CGFloat, rotationRadians: CGFloat) -> ImageEditorStickerItem {
        ImageEditorStickerItem(
            itemId: self.itemId,
            sticker: self.sticker,
            date: self.date,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: self.unitCenter,
            rotationRadians: rotationRadians,
            scaling: scaling
        )
    }

    func copy(sticker: EditorSticker) -> ImageEditorStickerItem {
        ImageEditorStickerItem(
            itemId: self.itemId,
            sticker: sticker,
            date: self.date,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: self.unitCenter,
            rotationRadians: self.rotationRadians,
            scaling: self.scaling
        )
    }

    override func outputScale() -> CGFloat {
        return scaling
    }
}
