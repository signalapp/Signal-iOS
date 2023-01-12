//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

class EditorTextLayer: CATextLayer {

    let itemId: String

    init(itemId: String) {
        self.itemId = itemId
        super.init()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class TextFrameLayer: CAShapeLayer {

    override init() {
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        commonInit()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var bounds: CGRect {
        didSet {
            updatePath()
        }
    }

    override var frame: CGRect {
        didSet {
            updatePath()
        }
    }

    private static let circleRadius: CGFloat = 5

    // Visible frame is a little smaller than layer's bounds in order
    // to make room for little circles in the middle of left and right frame sides.
    private var frameRect: CGRect {
        bounds.insetBy(dx: TextFrameLayer.circleRadius, dy: 0)
    }
    private lazy var leftCircleLayer = TextFrameLayer.createCircleLayer()
    private lazy var rightCircleLayer = TextFrameLayer.createCircleLayer()
    private static func createCircleLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(origin: .zero, size: CGSize(square: circleRadius * 2))
        layer.fillColor = UIColor.white.cgColor
        layer.path = UIBezierPath(ovalIn: layer.bounds).cgPath
        return layer
    }

    private func commonInit() {
        fillColor = UIColor.clear.cgColor
        lineWidth = 3 * CGHairlineWidth()
        strokeColor = UIColor.white.cgColor

        addSublayer(leftCircleLayer)
        addSublayer(rightCircleLayer)
    }

    private func updatePath() {
        path = UIBezierPath(rect: frameRect).cgPath
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        let frameRect = frameRect
        leftCircleLayer.position = CGPoint(x: frameRect.minX, y: frameRect.midY)
        rightCircleLayer.position = CGPoint(x: frameRect.maxX, y: frameRect.midY)
    }
}

// MARK: -

// A view for previewing an image editor model.
class ImageEditorCanvasView: UIView {

    private let model: ImageEditorModel

    var hiddenItemId: String? {
        didSet {
            if let itemId = oldValue, let layer = contentLayerMap[itemId] {
                layer.isHidden = false
                // Show text object's frame if current text object is selected.
                if itemId == selectedTextItemId {
                    selectedTextFrameLayer?.isHidden = false
                }
            }
            if let hiddenItemId = hiddenItemId, let layer = contentLayerMap[hiddenItemId] {
                layer.isHidden = true
                // Hide text object's frame when hiding selected text object.
                if hiddenItemId == selectedTextItemId {
                    selectedTextFrameLayer?.isHidden = true
                }
            }
        }
    }

    var selectedTextItemId: String? {
        didSet {
            updateSelectedTextFrame()
        }
    }

    // We want blurs to be rendered above the image and behind strokes and text.
    private static let blurLayerZ: CGFloat = +1
    // We want strokes to be rendered above the image and blurs and behind text.
    private static let brushLayerZ: CGFloat = +2
    // We want text to be rendered above the image, blurs, and strokes.
    private static let textLayerZ: CGFloat = +3
    // Selection frame is rendered above all content.
    private static let selectionFrameLayerZ: CGFloat = +4
    // We leave space for 10k items/layers of each type.
    private static let zPositionSpacing: CGFloat = 0.0001

    required init(model: ImageEditorModel, hiddenItemId: String? = nil) {
        self.model = model
        self.hiddenItemId = hiddenItemId

        super.init(frame: .zero)

        model.add(observer: self)

        prepareBlurredImage()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Views

    // contentView is used to host the layers used to render the content.
    //
    // The transform for the content is applied to it.
    let contentView = OWSLayerView()

    // clipView is used to clip the content.  It reflects the actual
    // visible bounds of the "canvas" content.
    private let clipView = OWSLayerView()

    private var contentViewConstraints = [NSLayoutConstraint]()

    private var imageLayer = CALayer()

    func setCornerRadius(_ cornerRadius: CGFloat, animationDuration: TimeInterval = 0) {
        guard cornerRadius != clipView.layer.cornerRadius else { return }

        if animationDuration > 0 {
            let animation = CABasicAnimation(keyPath: #keyPath(CALayer.cornerRadius))
            animation.fromValue = clipView.layer.cornerRadius
            animation.toValue = cornerRadius
            animation.duration = animationDuration
            clipView.layer.add(animation, forKey: "cornerRadius")
        }
        clipView.layer.cornerRadius = cornerRadius
    }

    func configureSubviews() {
        self.backgroundColor = .clear
        self.isOpaque = false

        clipView.clipsToBounds = true
        clipView.isOpaque = false
        clipView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateLayout()
        }
        addSubview(clipView)

        if let srcImage = loadSrcImage() {
            imageLayer.contents = srcImage.cgImage
            imageLayer.contentsScale = srcImage.scale
        }

        contentView.isOpaque = false
        contentView.layer.addSublayer(imageLayer)
        contentView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateAllContent()
        }
        clipView.addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()

        updateLayout()
    }

    var gestureReferenceView: UIView {
        return clipView
    }

    private func updateLayout() {
        NSLayoutConstraint.deactivate(contentViewConstraints)
        contentViewConstraints = ImageEditorCanvasView.updateContentLayout(transform: model.currentTransform(),
                                                                           contentView: clipView)
    }

    class func updateContentLayout(transform: ImageEditorTransform,
                                   contentView: UIView) -> [NSLayoutConstraint] {
        guard let superview = contentView.superview else {
            owsFailDebug("Content view has no superview.")
            return []
        }

        let aspectRatio = transform.outputSizePixels

        // This emulates the behavior of contentMode = .scaleAspectFit using iOS auto layout constraints.
        var constraints = [NSLayoutConstraint]()
        NSLayoutConstraint.autoSetPriority(.defaultHigh + 100) {
            constraints.append(contentView.autoAlignAxis(.vertical, toSameAxisOf: superview))
            constraints.append(contentView.autoAlignAxis(.horizontal, toSameAxisOf: superview))
        }
        constraints.append(contentView.autoPinEdge(.top, to: .top, of: superview, withOffset: 0, relation: .greaterThanOrEqual))
        constraints.append(contentView.autoPinEdge(.bottom, to: .bottom, of: superview, withOffset: 0, relation: .lessThanOrEqual))
        constraints.append(contentView.autoPin(toAspectRatio: aspectRatio.width / aspectRatio.height))
        constraints.append(contentView.autoMatch(.width, to: .width, of: superview, withMultiplier: 1.0, relation: .lessThanOrEqual))
        constraints.append(contentView.autoMatch(.height, to: .height, of: superview, withMultiplier: 1.0, relation: .lessThanOrEqual))
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            constraints.append(contentView.autoMatch(.width, to: .width, of: superview, withMultiplier: 1.0, relation: .equal))
            constraints.append(contentView.autoMatch(.height, to: .height, of: superview, withMultiplier: 1.0, relation: .equal))
        }

        let superviewSize = superview.frame.size
        let maxSuperviewDimension = max(superviewSize.width, superviewSize.height)
        let outputSizePoints = CGSize(square: maxSuperviewDimension)
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            constraints.append(contentsOf: contentView.autoSetDimensions(to: outputSizePoints))
        }
        return constraints
    }

    private func loadSrcImage() -> UIImage? {
        return ImageEditorCanvasView.loadSrcImage(model: model)
    }

    class func loadSrcImage(model: ImageEditorModel) -> UIImage? {
        let srcImageData: Data
        do {
            let srcImagePath = model.srcImagePath
            let srcImageUrl = URL(fileURLWithPath: srcImagePath)
            srcImageData = try Data(contentsOf: srcImageUrl)
        } catch {
            owsFailDebug("Couldn't parse srcImageUrl")
            return nil
        }
        // We use this constructor so that we can specify the scale.
        //
        // UIImage(contentsOfFile:) will sometimes use device scale.
        guard let srcImage = UIImage(data: srcImageData, scale: 1.0) else {
            owsFailDebug("Couldn't load background image.")
            return nil
        }
        // We normalize the image orientation here for the sake
        // of code simplicity.  We could modify the image layer's
        // transform to handle the normalization, which would
        // have perf benefits.
        return srcImage.normalized()
    }

    // MARK: - Text Selection Frame

    private var selectedTextFrameLayer: TextFrameLayer?

    // Negative insets because text object frame is larger than object itself.
    private static let textFrameInsets = UIEdgeInsets(hMargin: -16, vMargin: -4)

    private func updateSelectedTextFrame() {
        guard let selectedTextItemId = selectedTextItemId,
              let textLayer = contentLayerMap[selectedTextItemId] as? EditorTextLayer else {
            selectedTextFrameLayer?.removeFromSuperlayer()
            selectedTextFrameLayer = nil
            return
        }

        let selectedTextFrameLayer = selectedTextFrameLayer ?? TextFrameLayer()
        if selectedTextFrameLayer.superlayer == nil {
            contentView.layer.addSublayer(selectedTextFrameLayer)
            selectedTextFrameLayer.zPosition = ImageEditorCanvasView.selectionFrameLayerZ
            self.selectedTextFrameLayer = selectedTextFrameLayer
        }

        // Disable implicit animations that make little circles not move smoothly with the frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let transform = textLayer.affineTransform()
        let rotationAngle = atan2(transform.b, transform.a)
        let scaleX = sqrt(pow(transform.a, 2) + pow(transform.c, 2))
        let scaleY = sqrt(pow(transform.b, 2) + pow(transform.d, 2))

        selectedTextFrameLayer.bounds = textLayer.bounds
            .inset(by: ImageEditorCanvasView.textFrameInsets)
            .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
        selectedTextFrameLayer.position = textLayer.position
        selectedTextFrameLayer.setAffineTransform(CGAffineTransform(rotationAngle: rotationAngle))
        selectedTextFrameLayer.layoutSublayers()

        CATransaction.commit()
    }

    // MARK: - Content

    private var contentLayerMap = [String: CALayer]()

    private func updateAllContent() {
        AssertIsOnMainThread()

        // Don't animate changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for layer in contentLayerMap.values {
            layer.removeFromSuperlayer()
        }
        contentLayerMap.removeAll()

        let viewSize = clipView.bounds.size
        let transform = model.currentTransform()
        if viewSize.width > 0,
            viewSize.height > 0 {

            applyTransform()

            updateImageLayer()

            for item in model.items() {
                guard let layer = ImageEditorCanvasView.layerForItem(item: item,
                                                                     model: model,
                                                                     transform: transform,
                                                                     viewSize: viewSize) else {
                                                                        continue
                }

                if item.itemId == hiddenItemId {
                    layer.isHidden = true
                }
                contentView.layer.addSublayer(layer)
                contentLayerMap[item.itemId] = layer
            }
        }

        updateLayout()
        updateSelectedTextFrame()

        // Force layout now.
        setNeedsLayout()
        layoutIfNeeded()

        CATransaction.commit()
    }

    private func updateContent(changedItemIds: [String]) {
        AssertIsOnMainThread()

        // Don't animate changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Remove all changed items.
        for itemId in changedItemIds {
            if let layer = contentLayerMap[itemId] {
                layer.removeFromSuperlayer()
            }
            contentLayerMap.removeValue(forKey: itemId)
        }

        let viewSize = clipView.bounds.size
        let transform = model.currentTransform()
        if viewSize.width > 0,
            viewSize.height > 0 {

            applyTransform()

            updateImageLayer()

            // Create layers for inserted and updated items.
            for itemId in changedItemIds {
                guard let item = model.item(forId: itemId) else {
                    // Item was deleted.
                    continue
                }

                // Item was inserted or updated.
                guard let layer = ImageEditorCanvasView.layerForItem(item: item,
                                                                     model: model,
                                                                     transform: transform,
                                                                     viewSize: viewSize) else {
                                                                        continue
                }

                if item.itemId == hiddenItemId {
                    layer.isHidden = true
                }
                contentView.layer.addSublayer(layer)
                contentLayerMap[item.itemId] = layer
            }
        }

        updateSelectedTextFrame()

        CATransaction.commit()
    }

    private func applyTransform() {
        let viewSize = clipView.bounds.size
        contentView.layer.setAffineTransform(model.currentTransform().affineTransform(viewSize: viewSize))
    }

    private func updateImageLayer() {
        let viewSize = clipView.bounds.size
        ImageEditorCanvasView.updateImageLayer(imageLayer: imageLayer,
                                               viewSize: viewSize,
                                               imageSize: model.srcImageSizePixels,
                                               transform: model.currentTransform())
    }

    class func updateImageLayer(imageLayer: CALayer, viewSize: CGSize, imageSize: CGSize, transform: ImageEditorTransform) {
        imageLayer.frame = imageFrame(forViewSize: viewSize, imageSize: imageSize, transform: transform)

        // This is the only place the isFlipped flag is consulted.
        // We deliberately do _not_ use it in the affine transforms, etc.
        // so that:
        //
        // * It doesn't affect text content & brush strokes.
        // * To not complicate the other "coordinate system math".
        let transform = CGAffineTransform.identity.scaledBy(x: transform.isFlipped ? -1 : +1, y: 1)
        imageLayer.setAffineTransform(transform)
    }

    class func imageFrame(forViewSize viewSize: CGSize, imageSize: CGSize, transform: ImageEditorTransform) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else {
            owsFailDebug("Invalid viewSize")
            return .zero
        }
        guard imageSize.width > 0, imageSize.height > 0 else {
            owsFailDebug("Invalid imageSize")
            return .zero
        }

        // The image content's default size (at scaling = 1) is to fill the output/canvas bounds.
        // This makes it easier to clamp the scaling to safe values.
        // The downside is that rotation has the side effect of changing the render size of the
        // image, which complicates the crop view logic.
        //
        // Find the smallest possible image size that will completely fill the output size.
        //
        // NOTE: The "bounding box" of the output size that we need to fill needs to
        //       reflect the rotation.
        let sinValue = abs(sin(transform.rotationRadians))
        let cosValue = abs(cos(transform.rotationRadians))
        let outputSize = CGSize(width: viewSize.width * cosValue + viewSize.height * sinValue,
                                height: viewSize.width * sinValue + viewSize.height * cosValue)

        var width = outputSize.width
        var height = outputSize.width * imageSize.height / imageSize.width
        if height < outputSize.height {
            width = outputSize.height * imageSize.width / imageSize.height
            height = outputSize.height
        }
        let imageFrame = CGRect(x: (width - viewSize.width) * -0.5,
                                y: (height - viewSize.height) * -0.5,
                                width: width,
                                height: height)

        return imageFrame
    }

    private class func imageLayerForItem(model: ImageEditorModel,
                                         transform: ImageEditorTransform,
                                         viewSize: CGSize) -> CALayer? {
        guard let srcImage = loadSrcImage(model: model) else {
            owsFailDebug("Could not load src image.")
            return nil
        }
        let imageLayer = CALayer()
        imageLayer.contents = srcImage.cgImage
        imageLayer.contentsScale = srcImage.scale
        updateImageLayer(imageLayer: imageLayer,
                         viewSize: viewSize,
                         imageSize: model.srcImageSizePixels,
                         transform: transform)
        return imageLayer
    }

    private class func layerForItem(item: ImageEditorItem,
                                    model: ImageEditorModel,
                                    transform: ImageEditorTransform,
                                    viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        switch item.itemType {
        case .test:
            owsFailDebug("Unexpected test item.")
            return nil
        case .stroke:
            guard let strokeItem = item as? ImageEditorStrokeItem else {
                owsFailDebug("Item has unexpected type: \(type(of: item)).")
                return nil
            }
            return strokeLayerForItem(item: strokeItem,
                                      model: model,
                                      transform: transform,
                                      viewSize: viewSize)
        case .text:
            guard let textItem = item as? ImageEditorTextItem else {
                owsFailDebug("Item has unexpected type: \(type(of: item)).")
                return nil
            }
            return textLayerForItem(item: textItem,
                                    model: model,
                                    transform: transform,
                                    viewSize: viewSize)
        case .blurRegions:
            guard let blurRegionsItem = item as? ImageEditorBlurRegionsItem else {
                owsFailDebug("Item has unexpected type: \(type(of: item)).")
                return nil
            }
            return blurRegionsLayerForItem(item: blurRegionsItem,
                                           model: model,
                                           transform: transform,
                                           viewSize: viewSize)
        }
    }

    private class func strokeLayerForItem(item: ImageEditorStrokeItem,
                                          model: ImageEditorModel,
                                          transform: ImageEditorTransform,
                                          viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        let optionalBlurredImageLayer: CALayer?
        if item.strokeType == .blur {
            guard let blurredImageLayer = blurredImageLayerForItem(model: model, transform: transform, viewSize: viewSize) else {
                owsFailDebug("Failed to retrieve blurredImageLayer")
                return nil
            }

            blurredImageLayer.zPosition = zPositionForItem(item: item, model: model, zPositionBase: blurLayerZ)
            optionalBlurredImageLayer = blurredImageLayer
        } else {
            optionalBlurredImageLayer = nil
        }

        let strokeWidth = item.strokeWidth(forDstSize: viewSize)
        let unitSamples = item.unitSamples
        guard unitSamples.count > 0 else {
            // Not an error; the stroke doesn't have enough samples to render yet.
            return nil
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.lineWidth = strokeWidth
        shapeLayer.strokeColor = item.color?.cgColor
        shapeLayer.frame = CGRect(origin: .zero, size: viewSize)

        // Blur region origins are specified in "image unit" coordinates,
        // but need to be rendered in "canvas" coordinates. The imageFrame
        // is the bounds of the image specified in "canvas" coordinates,
        // so to transform we can simply convert from image frame units.
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: model.srcImageSizePixels, transform: transform)
        let transformSampleToPoint = { (unitSample: CGPoint) -> CGPoint in
            return unitSample.fromUnitCoordinates(viewBounds: imageFrame)
        }

        // Use bezier curves to smooth stroke.
        let bezierPath = UIBezierPath()

        let points = applySmoothing(to: unitSamples.map { (unitSample) in
            transformSampleToPoint(unitSample)
        })
        var previousForwardVector = CGPoint.zero
        for index in 0..<points.count {
            let point = points[index]

            let forwardVector: CGPoint
            if points.count <= 1 {
                // Skip forward vectors.
                forwardVector = .zero
            } else if index == 0 {
                // First sample.
                let nextPoint = points[index + 1]
                forwardVector = CGPointSubtract(nextPoint, point)
            } else if index == points.count - 1 {
                // Last sample.
                let previousPoint = points[index - 1]
                forwardVector = CGPointSubtract(point, previousPoint)
            } else {
                // Middle samples.
                let previousPoint = points[index - 1]
                let previousPointForwardVector = CGPointSubtract(point, previousPoint)
                let nextPoint = points[index + 1]
                let nextPointForwardVector = CGPointSubtract(nextPoint, point)
                forwardVector = CGPointScale(CGPointAdd(previousPointForwardVector, nextPointForwardVector), 0.5)
            }

            if index == 0 {
                // First sample.
                bezierPath.move(to: point)

                if points.count == 1 {
                    bezierPath.addLine(to: point)
                }
            } else {
                let previousPoint = points[index - 1]
                // We apply more than one kind of smoothing.
                // This smoothing avoids rendering "angled segments"
                // by drawing the stroke as a series of curves.
                // We use bezier curves and infer the control points
                // from the "next" and "prev" points.
                //
                // This factor controls how much we're smoothing.
                //
                // * 0.0 = No smoothing.
                //
                // TODO: Tune this variable once we have stroke input.
                let controlPointFactor: CGFloat = 0.25
                let controlPoint1 = CGPointAdd(previousPoint, CGPointScale(previousForwardVector, +controlPointFactor))
                let controlPoint2 = CGPointAdd(point, CGPointScale(forwardVector, -controlPointFactor))
                // We're using Cubic curves.
                bezierPath.addCurve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            }
            previousForwardVector = forwardVector
        }

        shapeLayer.path = bezierPath.cgPath
        shapeLayer.fillColor = nil

        if item.strokeType == .highlighter {
            shapeLayer.lineCap = CAShapeLayerLineCap.square
            shapeLayer.lineJoin = CAShapeLayerLineJoin.bevel
        } else {
            shapeLayer.lineCap = CAShapeLayerLineCap.round
            shapeLayer.lineJoin = CAShapeLayerLineJoin.round
        }

        if item.strokeType == .blur {
            guard let blurredImageLayer = optionalBlurredImageLayer else {
                owsFailDebug("Unexpectedly missing blurredImageLayer")
                return nil
            }

            shapeLayer.strokeColor = UIColor.black.cgColor
            blurredImageLayer.mask = shapeLayer

            return blurredImageLayer
        } else {
            shapeLayer.zPosition = zPositionForItem(item: item, model: model, zPositionBase: brushLayerZ)

            return shapeLayer
        }
    }

    private class func blurRegionsLayerForItem(item: ImageEditorBlurRegionsItem,
                                               model: ImageEditorModel,
                                               transform: ImageEditorTransform,
                                               viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        guard !item.unitBoundingBoxes.isEmpty else { return nil }

        guard let blurredImageLayer = blurredImageLayerForItem(model: model, transform: transform, viewSize: viewSize) else {
            owsFailDebug("Failed to retrieve blurredImageLayer")
            return nil
        }

        blurredImageLayer.zPosition = zPositionForItem(item: item, model: model, zPositionBase: blurLayerZ)

        // Stroke samples are specified in "image unit" coordinates, but
        // need to be rendered in "canvas" coordinates.  The imageFrame
        // is the bounds of the image specified in "canvas" coordinates,
        // so to transform we can simply convert from image frame units.
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: model.srcImageSizePixels, transform: transform)
        func transformSampleToPoint(_ unitSample: CGPoint) -> CGPoint {
            return unitSample.fromUnitCoordinates(viewBounds: imageFrame)
        }

        let maskingShapeLayer = CAShapeLayer()
        maskingShapeLayer.frame = CGRect(origin: .zero, size: viewSize)

        let maskingPath = UIBezierPath()

        for unitRect in item.unitBoundingBoxes {
            var rect = unitRect

            rect.origin = transformSampleToPoint(rect.origin)

            // Rescale normalized coordinates.
            rect.size.width *= imageFrame.width
            rect.size.height *= imageFrame.height

            let bezierPath = UIBezierPath(rect: rect)
            maskingPath.append(bezierPath)
        }

        maskingShapeLayer.path = maskingPath.cgPath
        blurredImageLayer.mask = maskingShapeLayer

        return blurredImageLayer
    }

    private class func zPositionForItem(item: ImageEditorItem,
                                        model: ImageEditorModel,
                                        zPositionBase: CGFloat) -> CGFloat {
        let itemIds = model.itemIds()
        guard let itemIndex = itemIds.firstIndex(of: item.itemId) else {
            owsFailDebug("Couldn't find index of item.")
            return zPositionBase
        }
        return zPositionBase + CGFloat(itemIndex) * zPositionSpacing
    }

    private class func textLayerForItem(item: ImageEditorTextItem,
                                        model: ImageEditorModel,
                                        transform: ImageEditorTransform,
                                        viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: model.srcImageSizePixels, transform: transform)

        // We need to adjust the font size to reflect the current output scale,
        // using the image width as reference.
        let fontSize = item.fontSize * imageFrame.size.width / item.fontReferenceImageWidth
        let font = MediaTextView.font(for: item.textStyle, withPointSize: fontSize)

        let text = item.text.filterForDisplay ?? ""
        let textStorage = NSTextStorage(
            string: text,
            attributes: [ .font: font, .foregroundColor: item.textForegroundColor ]
        )

        if let textDecorationColor = item.textDecorationColor {
            switch item.decorationStyle {
            case .underline:
                textStorage.addAttributes([ .underlineStyle: NSUnderlineStyle.single.rawValue,
                                            .underlineColor: textDecorationColor],
                                          range: textStorage.entireRange)
            case .outline:
                textStorage.addAttributes([ .strokeWidth: -3,
                                            .strokeColor: textDecorationColor ],
                                          range: textStorage.entireRange)

            default:
                break
            }
        }

        let textLayer = EditorTextLayer(itemId: item.itemId)
        textLayer.string = textStorage.attributedString()
        textLayer.isWrapped = true
        textLayer.alignmentMode = .center
        // I don't think we need to enable allowsFontSubpixelQuantization
        // or set truncationMode.

        // This text needs to be rendered at a scale that reflects:
        //
        // * The screen scaling (so that text looks sharp on Retina devices.
        // * The item's scaling (so that text doesn't become blurry as you make it larger).
        // * Model transform (so that text doesn't become blurry as you zoom the content).
        textLayer.contentsScale = UIScreen.main.scale * item.scaling * transform.scaling

        let maxWidth = imageFrame.size.width * item.unitWidth
        let textSize = textStorage.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                                options: [ .usesLineFragmentOrigin ],
                                                context: nil).size.ceil

        // The text item's center is specified in "image unit" coordinates, but
        // needs to be rendered in "canvas" coordinates.  The imageFrame
        // is the bounds of the image specified in "canvas" coordinates,
        // so to transform we can simply convert from image frame units.
        let centerInCanvas = item.unitCenter.fromUnitCoordinates(viewBounds: imageFrame)
        textLayer.frame = CGRect(origin: CGPoint(x: centerInCanvas.x - textSize.width * 0.5,
                                                 y: centerInCanvas.y - textSize.height * 0.5),
                                 size: textSize)

        // Enlarge the layer slightly when setting the background color to add some horizontal padding around the text.
        let layer: EditorTextLayer
        if let textBackgroundColor = item.textBackgroundColor {
            layer = EditorTextLayer(itemId: item.itemId)
            layer.frame = textLayer.frame.inset(by: UIEdgeInsets(hMargin: -6, vMargin: -2))
            layer.backgroundColor = textBackgroundColor.cgColor
            layer.cornerRadius = 8
            layer.addSublayer(textLayer)
            textLayer.position = layer.bounds.center
        } else {
            layer = textLayer
        }

        let transform = CGAffineTransform.scale(item.scaling).rotated(by: item.rotationRadians)
        layer.setAffineTransform(transform)
        layer.zPosition = zPositionForItem(item: item, model: model, zPositionBase: textLayerZ)

        return layer
    }

    // We apply more than one kind of smoothing.
    //
    // This (simple) smoothing reduces jitter from the touch sensor.
    private class func applySmoothing(to points: [CGPoint]) -> [CGPoint] {
        AssertIsOnMainThread()

        var result = [CGPoint]()

        for index in 0..<points.count {
            let point = points[index]

            if index == 0 {
                // First sample.
                result.append(point)
            } else if index == points.count - 1 {
                // Last sample.
                result.append(point)
            } else {
                // Middle samples.
                let lastPoint = points[index - 1]
                let nextPoint = points[index + 1]
                let alpha: CGFloat = 0.1
                let smoothedPoint = CGPointAdd(CGPointScale(point, 1.0 - 2.0 * alpha),
                                               CGPointAdd(CGPointScale(lastPoint, alpha),
                                                          CGPointScale(nextPoint, alpha)))
                result.append(smoothedPoint)
            }
        }

        return result
    }

    // MARK: - Blur

    private func prepareBlurredImage() {
        guard let srcImage = loadSrcImage() else {
            return owsFailDebug("Could not load src image.")
        }

        // we use a very strong blur radius to ensure adequate coverage of large and small faces
        srcImage.cgImageWithGaussianBlurPromise(
            radius: 25,
            resizeToMaxPixelDimension: 300
        ).done(on: .main) { [weak self] blurredImage in
            guard let self = self else { return }
            self.model.blurredSourceImage = blurredImage

            // Once the blur is ready, update any content in case the user already blurred
            if self.window != nil {
                self.updateAllContent()
            }
        }.catch { _ in
            owsFailDebug("Failed to blur src image")
        }
    }

    private class func blurredImageLayerForItem(model: ImageEditorModel,
                                                transform: ImageEditorTransform,
                                                viewSize: CGSize) -> CALayer? {
        guard let blurredSourceImage = model.blurredSourceImage else {
            // If we fail to generate the blur image, or it's not ready yet, use a black mask
            let layer = CALayer()
            layer.frame = imageFrame(forViewSize: viewSize, imageSize: model.srcImageSizePixels, transform: transform)
            layer.backgroundColor = UIColor.black.cgColor
            return layer
        }

        // The image layer renders the blurred image in canvas coordinates
        let blurredImageLayer = CALayer()
        blurredImageLayer.contents = blurredSourceImage
        updateImageLayer(imageLayer: blurredImageLayer,
                         viewSize: viewSize,
                         imageSize: model.srcImageSizePixels,
                         transform: transform)

        // The container holds the blurred image, and can be masked using canvas
        // coordinates to partially blur the image.
        let blurredImageContainer = CALayer()
        blurredImageContainer.addSublayer(blurredImageLayer)
        blurredImageContainer.frame = CGRect(origin: .zero, size: viewSize)

        return blurredImageContainer
    }

    // MARK: - Actions

    // Returns nil on error.
    //
    // We render using the transform parameter, not the transform from the model.
    // This allows this same method to be used for rendering "previews" for the
    // crop tool and the final output.
    class func renderForOutput(model: ImageEditorModel, transform: ImageEditorTransform) -> UIImage? {
        // TODO: Do we want to render off the main thread?
        AssertIsOnMainThread()

        // Render output at same size as source image.
        let dstSizePixels = transform.outputSizePixels
        let dstScale: CGFloat = 1.0 // The size is specified in pixels, not in points.
        let viewSize = dstSizePixels

        let hasAlpha = NSData.hasAlpha(forValidImageFilePath: model.srcImagePath)

        // We use an UIImageView + UIView.renderAsImage() instead of a CGGraphicsContext
        // Because CALayer.renderInContext() doesn't honor CALayer properties like frame,
        // transform, etc.
        let view = UIView()
        view.backgroundColor = UIColor.clear
        view.isOpaque = false
        view.frame = CGRect(origin: .zero, size: viewSize)

        // Rendering a UIView to an image will not honor the root image's layer transform.
        // We therefore use a subview.
        let contentView = UIView()
        contentView.backgroundColor = UIColor.clear
        contentView.isOpaque = false
        contentView.frame = CGRect(origin: .zero, size: viewSize)
        view.addSubview(contentView)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        contentView.layer.setAffineTransform(transform.affineTransform(viewSize: viewSize))

        guard let imageLayer = imageLayerForItem(model: model,
                                                 transform: transform,
                                                 viewSize: viewSize) else {
                                                    owsFailDebug("Could not load src image.")
                                                    return nil
        }
        imageLayer.contentsScale = dstScale * transform.scaling
        contentView.layer.addSublayer(imageLayer)

        var layers = [CALayer]()
        for item in model.items() {
            guard let layer = layerForItem(item: item,
                                           model: model,
                                           transform: transform,
                                           viewSize: viewSize) else {
                                            owsFailDebug("Couldn't create layer for item.")
                                            continue
            }
            layer.contentsScale = dstScale * transform.scaling * item.outputScale()
            layers.append(layer)
        }
        // UIView.renderAsImage() doesn't honor zPosition of layers,
        // so sort the item layers to ensure they are added in the
        // correct order.
        let sortedLayers = layers.sorted(by: { (left, right) -> Bool in
            return left.zPosition < right.zPosition
        })
        for layer in sortedLayers {
            contentView.layer.addSublayer(layer)
        }

        CATransaction.commit()

        let image = view.renderAsImage(opaque: !hasAlpha, scale: dstScale)
        return image
    }

    // MARK: -

    func textLayer(forLocation point: CGPoint) -> EditorTextLayer? {
        guard let sublayers = contentView.layer.sublayers else {
            return nil
        }

        // Allow to interact with selected text layer when user taps within
        // selection frame (which is larger than text itself).
        if let selectedTextFrameLayer = selectedTextFrameLayer,
           let selectedTextItemId = selectedTextItemId,
           let selectedTextLayer = contentLayerMap[selectedTextItemId] as? EditorTextLayer,
           selectedTextFrameLayer.hitTest(point) != nil {
            return selectedTextLayer
        }

        // First we build a map of all text layers.
        var layerMap = [String: EditorTextLayer]()
        for layer in sublayers {
            guard let textLayer = layer as? EditorTextLayer else {
                continue
            }
            layerMap[textLayer.itemId] = textLayer
        }

        // The layer ordering in the model is authoritative.
        // Iterate over the layers in _reverse_ order of which they appear
        // in the model, so that layers "on top" are hit first.
        for item in model.items().reversed() {
            guard let textLayer = layerMap[item.itemId] else {
                // Not a text layer.
                continue
            }
            if textLayer.hitTest(point) != nil {
                return textLayer
            }
        }
        return nil
    }

    // MARK: - Coordinates

    class func locationImageUnit(forLocationInView locationInView: CGPoint,
                                 viewBounds: CGRect,
                                 model: ImageEditorModel,
                                 transform: ImageEditorTransform) -> CGPoint {
        let imageFrame = self.imageFrame(forViewSize: viewBounds.size, imageSize: model.srcImageSizePixels, transform: transform)
        let affineTransformStart = transform.affineTransform(viewSize: viewBounds.size)
        let locationInContent = locationInView.minus(viewBounds.center).applyingInverse(affineTransformStart).plus(viewBounds.center)
        let locationImageUnit = locationInContent.toUnitCoordinates(viewBounds: imageFrame, shouldClamp: false)
        return locationImageUnit
    }
}

// MARK: -

extension ImageEditorCanvasView: ImageEditorModelObserver {

    func imageEditorModelDidChange(before: ImageEditorContents, after: ImageEditorContents) {
        updateAllContent()
    }

    func imageEditorModelDidChange(changedItemIds: [String]) {
        updateContent(changedItemIds: changedItemIds)
    }
}
