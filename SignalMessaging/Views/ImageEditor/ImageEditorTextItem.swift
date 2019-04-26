//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class ImageEditorTextItem: ImageEditorItem {

    @objc
    public let text: String

    @objc
    public let color: ImageEditorColor

    @objc
    public let font: UIFont

    // In order to render the text at a consistent size
    // in very differently sized contexts (canvas in
    // portrait, landscape, in the crop tool, before and
    // after cropping, while rendering output),
    // we need to scale the font size to reflect the
    // view width.
    //
    // We use the image's rendering width as the reference value,
    // since we want to be consistent with regard to the image's
    // content.
    @objc
    public let fontReferenceImageWidth: CGFloat

    @objc
    public let unitCenter: ImageEditorSample

    // Leave some margins against the edge of the image.
    @objc
    public static let kDefaultUnitWidth: CGFloat = 0.9

    // The max width of the text as a fraction of the image width.
    //
    // This provides continuity of text layout before/after cropping.
    //
    // NOTE: When you scale the text with with a pinch gesture, that
    // affects _scaling_, not the _unit width_, since we don't want
    // to change how the text wraps when scaling.
    @objc
    public let unitWidth: CGFloat

    // 0 = no rotation.
    // CGFloat.pi * 0.5 = rotation 90 degrees clockwise.
    @objc
    public let rotationRadians: CGFloat

    @objc
    public static let kMaxScaling: CGFloat = 4.0
    @objc
    public static let kMinScaling: CGFloat = 0.5
    @objc
    public let scaling: CGFloat

    @objc
    public init(text: String,
                color: ImageEditorColor,
                font: UIFont,
                fontReferenceImageWidth: CGFloat,
                unitCenter: ImageEditorSample = ImageEditorSample(x: 0.5, y: 0.5),
                unitWidth: CGFloat = ImageEditorTextItem.kDefaultUnitWidth,
                rotationRadians: CGFloat = 0.0,
                scaling: CGFloat = 1.0) {
        self.text = text
        self.color = color
        self.font = font
        self.fontReferenceImageWidth = fontReferenceImageWidth
        self.unitCenter = unitCenter
        self.unitWidth = unitWidth
        self.rotationRadians = rotationRadians
        self.scaling = scaling

        super.init(itemType: .text)
    }

    private init(itemId: String,
                 text: String,
                 color: ImageEditorColor,
                 font: UIFont,
                 fontReferenceImageWidth: CGFloat,
                 unitCenter: ImageEditorSample,
                 unitWidth: CGFloat,
                 rotationRadians: CGFloat,
                 scaling: CGFloat) {
        self.text = text
        self.color = color
        self.font = font
        self.fontReferenceImageWidth = fontReferenceImageWidth
        self.unitCenter = unitCenter
        self.unitWidth = unitWidth
        self.rotationRadians = rotationRadians
        self.scaling = scaling

        super.init(itemId: itemId, itemType: .text)
    }

    @objc
    public class func empty(withColor color: ImageEditorColor,
                            unitWidth: CGFloat,
                            fontReferenceImageWidth: CGFloat,
                            scaling: CGFloat,
                            rotationRadians: CGFloat) -> ImageEditorTextItem {
        // TODO: Tune the default font size.
        let font = UIFont.boldSystemFont(ofSize: 30.0)
        return ImageEditorTextItem(text: "",
                                   color: color,
                                   font: font,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    @objc
    public func copy(withText newText: String, color newColor: ImageEditorColor) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: newText,
                                   color: newColor,
                                   font: font,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    @objc
    public func copy(unitCenter: CGPoint) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   font: font,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    @objc
    public func copy(scaling: CGFloat,
                     rotationRadians: CGFloat) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   font: font,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    @objc
    public func copy(unitWidth: CGFloat) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   font: font,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    @objc
    public func copy(font: UIFont) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   font: font,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    public override func outputScale() -> CGFloat {
        return scaling
    }

    static func ==(left: ImageEditorTextItem, right: ImageEditorTextItem) -> Bool {
        return (left.text == right.text &&
            left.color == right.color &&
            left.font.fontName == right.font.fontName &&
            left.font.pointSize.fuzzyEquals(right.font.pointSize) &&
            left.fontReferenceImageWidth.fuzzyEquals(right.fontReferenceImageWidth) &&
            left.unitCenter.fuzzyEquals(right.unitCenter) &&
            left.unitWidth.fuzzyEquals(right.unitWidth) &&
            left.rotationRadians.fuzzyEquals(right.rotationRadians) &&
            left.scaling.fuzzyEquals(right.scaling))
    }
}
