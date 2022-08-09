//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit

class ImageEditorTextItem: ImageEditorItem {

    let text: String

    let color: ImageEditorColor

    enum DecorationStyle: Int {
        case none = 0
        case inverted
        case underline
        case outline
    }
    let decorationStyle: DecorationStyle

    enum TextStyle: Int {
        case regular = 0
        case bold
        case serif
        case script
        case condensed
    }
    let textStyle: TextStyle

    let fontSize: CGFloat
    static let defaultFontSize: CGFloat = 36
    var font: UIFont {
        ImageEditorTextItem.font(forTextStyle: textStyle, pointSize: fontSize)
    }

    class func font(forTextStyle textStyle: TextStyle, pointSize: CGFloat) -> UIFont {
        // TODO: this is a copy-paste code from TextAttachmentView that needs to be consolidated in one place.
        let attributes: [UIFontDescriptor.AttributeName: Any]

        switch textStyle {
        case .regular:
            attributes = [.name: "Inter-Regular_Bold"]
        case .bold:
            attributes = [.name: "Inter-Regular_Black"]
        case .serif:
            attributes = [.name: "EBGaramond-Regular"]
        case .script:
            attributes = [.name: "Parisienne-Regular"]
        case .condensed:
            // TODO: Ideally we could set an attribute to make this font
            // all caps, but iOS deprecated that ability and didn't add
            // a new equivalent function.
            attributes = [.name: "BarlowCondensed-Medium"]
        }

        // TODO: Eventually we'll want to provide a cascadeList here to fallback
        // to different fonts for different scripts rather than just relying on
        // the built in OS fallbacks that don't tend to match the desired style.
        let descriptor = UIFontDescriptor(fontAttributes: attributes)

        return UIFont(descriptor: descriptor, size: pointSize)
    }

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
    let fontReferenceImageWidth: CGFloat

    let unitCenter: ImageEditorSample

    // Leave some margins against the edge of the image.
    static let kDefaultUnitWidth: CGFloat = 0.9

    // The max width of the text as a fraction of the image width.
    //
    // This provides continuity of text layout before/after cropping.
    //
    // NOTE: When you scale the text with with a pinch gesture, that
    // affects _scaling_, not the _unit width_, since we don't want
    // to change how the text wraps when scaling.
    let unitWidth: CGFloat

    // 0 = no rotation.
    // CGFloat.pi * 0.5 = rotation 90 degrees clockwise.
    let rotationRadians: CGFloat

    static let kMaxScaling: CGFloat = 4.0

    static let kMinScaling: CGFloat = 0.5

    let scaling: CGFloat

    init(text: String,
         color: ImageEditorColor,
         fontSize: CGFloat,
         textStyle: TextStyle = .regular,
         decorationStyle: DecorationStyle = .none,
         fontReferenceImageWidth: CGFloat,
         unitCenter: ImageEditorSample = ImageEditorSample(x: 0.5, y: 0.5),
         unitWidth: CGFloat = ImageEditorTextItem.kDefaultUnitWidth,
         rotationRadians: CGFloat = 0.0,
         scaling: CGFloat = 1.0) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.textStyle = textStyle
        self.decorationStyle = decorationStyle
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
                 fontSize: CGFloat,
                 textStyle: TextStyle,
                 decorationStyle: DecorationStyle,
                 fontReferenceImageWidth: CGFloat,
                 unitCenter: ImageEditorSample,
                 unitWidth: CGFloat,
                 rotationRadians: CGFloat,
                 scaling: CGFloat) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.textStyle = textStyle
        self.decorationStyle = decorationStyle
        self.fontReferenceImageWidth = fontReferenceImageWidth
        self.unitCenter = unitCenter
        self.unitWidth = unitWidth
        self.rotationRadians = rotationRadians
        self.scaling = scaling

        super.init(itemId: itemId, itemType: .text)
    }

    class func empty(withColor color: ImageEditorColor,
                     textStyle: TextStyle,
                     decorationStyle: DecorationStyle,
                     unitWidth: CGFloat,
                     fontReferenceImageWidth: CGFloat,
                     scaling: CGFloat,
                     rotationRadians: CGFloat) -> ImageEditorTextItem {
        return ImageEditorTextItem(text: "",
                                   color: color,
                                   fontSize: ImageEditorTextItem.defaultFontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    func copy(withText newText: String, color newColor: ImageEditorColor) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: newText,
                                   color: newColor,
                                   fontSize: fontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    func copy(unitCenter: CGPoint) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   fontSize: fontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    func copy(scaling: CGFloat, rotationRadians: CGFloat) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   fontSize: fontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    func copy(unitWidth: CGFloat) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   fontSize: fontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    func copy(fontSize: CGFloat) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   fontSize: fontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    func copy(color: ImageEditorColor) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   fontSize: fontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    func copy(textStyle: TextStyle, decorationStyle: DecorationStyle) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   text: text,
                                   color: color,
                                   fontSize: fontSize,
                                   textStyle: textStyle,
                                   decorationStyle: decorationStyle,
                                   fontReferenceImageWidth: fontReferenceImageWidth,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling)
    }

    override func outputScale() -> CGFloat {
        return scaling
    }

    static func == (left: ImageEditorTextItem, right: ImageEditorTextItem) -> Bool {
        return (left.text == right.text &&
                left.color == right.color &&
                left.textStyle == right.textStyle &&
                left.decorationStyle == right.decorationStyle &&
                left.fontSize.fuzzyEquals(right.fontSize) &&
                left.fontReferenceImageWidth.fuzzyEquals(right.fontReferenceImageWidth) &&
                left.unitCenter.fuzzyEquals(right.unitCenter) &&
                left.unitWidth.fuzzyEquals(right.unitWidth) &&
                left.rotationRadians.fuzzyEquals(right.rotationRadians) &&
                left.scaling.fuzzyEquals(right.scaling))
    }
}
