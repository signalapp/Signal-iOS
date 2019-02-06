//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

public class EditorTextLayer: CATextLayer {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId

        super.init()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
}

// MARK: -

// A view for previewing an image editor model.
@objc
public class ImageEditorCanvasView: UIView {

    private let model: ImageEditorModel

    @objc
    public required init(model: ImageEditorModel) {
        self.model = model

        super.init(frame: .zero)

        model.add(observer: self)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Views

    // TODO: Audit all usage of this view.
    public let contentView = OWSLayerView()

    private let clipView = OWSLayerView()

    private var contentViewConstraints = [NSLayoutConstraint]()

    private var srcImage: UIImage?

    private var imageLayer = CALayer()

    @objc
    public func configureSubviews() -> Bool {
        self.backgroundColor = .clear
        self.isOpaque = false

        self.srcImage = loadSrcImage()

        clipView.clipsToBounds = true
        clipView.backgroundColor = .clear
        clipView.isOpaque = false
        clipView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateLayout()
        }
        addSubview(clipView)

        if let srcImage = srcImage {
            imageLayer.contents = srcImage.cgImage
            imageLayer.contentsScale = srcImage.scale
        }

        contentView.backgroundColor = .clear
        contentView.isOpaque = false
        contentView.layer.addSublayer(imageLayer)
        contentView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateAllContent()
        }
        clipView.addSubview(contentView)
        contentView.ows_autoPinToSuperviewEdges()

        updateLayout()

        return true
    }

    public var gestureReferenceView: UIView {
        return clipView
    }

    private func updateLayout() {
        NSLayoutConstraint.deactivate(contentViewConstraints)
        contentViewConstraints = ImageEditorCanvasView.updateContentLayout(transform: model.currentTransform(),
                                                                           contentView: clipView)
    }

    public class func updateContentLayout(transform: ImageEditorTransform,
                                          contentView: UIView) -> [NSLayoutConstraint] {
        guard let superview = contentView.superview else {
            owsFailDebug("Content view has no superview.")
            return []
        }
        let outputSizePixels = transform.outputSizePixels

        let aspectRatio = outputSizePixels
        var constraints = superview.applyScaleAspectFitLayout(subview: contentView, aspectRatio: aspectRatio.width / aspectRatio.height)

        let screenSize = UIScreen.main.bounds.size
        let maxScreenSize = max(screenSize.width, screenSize.height)
        let outputSizePoints = CGSize(width: maxScreenSize, height: maxScreenSize)
        // TODO: Add a "shouldFill" parameter.
        //        let outputSizePoints = CGSizeScale(outputSizePixels, 1.0 / UIScreen.main.scale)
        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultLow) {
            constraints.append(contentsOf: contentView.autoSetDimensions(to: outputSizePoints))
        }
        return constraints
    }

    @objc
    public func loadSrcImage() -> UIImage? {
        return ImageEditorCanvasView.loadSrcImage(model: model)
    }

    @objc
    public class func loadSrcImage(model: ImageEditorModel) -> UIImage? {
        let srcImageData: Data
        do {
            let srcImagePath = model.srcImagePath
            let srcImageUrl = URL(fileURLWithPath: srcImagePath)
            srcImageData = try Data(contentsOf: srcImageUrl)
        } catch {
            Logger.error("Couldn't parse srcImageUrl")
            return nil
        }
        // We use this constructor so that we can specify the scale.
        guard let srcImage = UIImage(data: srcImageData, scale: 1.0) else {
            owsFailDebug("Couldn't load background image.")
            return nil
        }
        return srcImage
    }

    // MARK: - Content

    var contentLayerMap = [String: CALayer]()

    internal func updateAllContent() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // Don't animate changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for layer in contentLayerMap.values {
            layer.removeFromSuperlayer()
        }
        contentLayerMap.removeAll()

        let viewSize = clipView.bounds.size
        if viewSize.width > 0,
            viewSize.height > 0 {

            applyTransform()

            updateImageLayer()

            for item in model.items() {
                guard let layer = ImageEditorCanvasView.layerForItem(item: item,
                                                                     model: model,
                                                                     viewSize: viewSize) else {
                                                                        continue
                }

                contentView.layer.addSublayer(layer)
                contentLayerMap[item.itemId] = layer
            }
        }

        updateLayout()

        // Force layout now.
        setNeedsLayout()
        layoutIfNeeded()

        CATransaction.commit()
    }

    internal func updateContent(changedItemIds: [String]) {
        AssertIsOnMainThread()

        Logger.verbose("")

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
                                                                     viewSize: viewSize) else {
                                                                        continue
                }

                contentView.layer.addSublayer(layer)
                contentLayerMap[item.itemId] = layer
            }
        }

        CATransaction.commit()
    }

    private func applyTransform() {
        Logger.verbose("")

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

    public class func updateImageLayer(imageLayer: CALayer, viewSize: CGSize, imageSize: CGSize, transform: ImageEditorTransform) {
        imageLayer.frame = imageFrame(forViewSize: viewSize, imageSize: imageSize, transform: transform)
    }

    public class func imageFrame(forViewSize viewSize: CGSize, imageSize: CGSize, transform: ImageEditorTransform) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else {
            owsFailDebug("Invalid viewSize")
            return .zero
        }
        guard imageSize.width > 0, imageSize.height > 0 else {
            owsFailDebug("Invalid imageSize")
            return .zero
        }

        // We want to "fill" the output rect.
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

        Logger.verbose("viewSize: \(viewSize), imageFrame: \(imageFrame), ")
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
            return strokeLayerForItem(item: strokeItem, viewSize: viewSize)
        case .text:
            guard let textItem = item as? ImageEditorTextItem else {
                owsFailDebug("Item has unexpected type: \(type(of: item)).")
                return nil
            }
            return textLayerForItem(item: textItem,
                                    model: model,
                                    viewSize: viewSize)
        }
    }

    private class func strokeLayerForItem(item: ImageEditorStrokeItem,
                                          viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        let strokeWidth = ImageEditorStrokeItem.strokeWidth(forUnitStrokeWidth: item.unitStrokeWidth,
                                                            dstSize: viewSize)
        let unitSamples = item.unitSamples
        guard unitSamples.count > 0 else {
            // Not an error; the stroke doesn't have enough samples to render yet.
            return nil
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.lineWidth = strokeWidth
        shapeLayer.strokeColor = item.color.cgColor
        shapeLayer.frame = CGRect(origin: .zero, size: viewSize)

        let transformSampleToPoint = { (unitSample: CGPoint) -> CGPoint in
            return CGPoint(x: viewSize.width * unitSample.x,
                           y: viewSize.height * unitSample.y)
        }

        // TODO: Use bezier curves to smooth stroke.
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
        shapeLayer.lineCap = kCALineCapRound
        shapeLayer.lineJoin = kCALineJoinRound

        return shapeLayer
    }

    private class func textLayerForItem(item: ImageEditorTextItem,
                                        model: ImageEditorModel,
                                        viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        let imageFrame = self.imageFrame(forViewSize: viewSize, imageSize: model.srcImageSizePixels,
                                         transform: model.currentTransform())

        // We need to adjust the font size to reflect the current output scale,
        // using the image width as reference.
        let fontSize = item.font.pointSize * imageFrame.size.width / item.fontReferenceImageWidth

        let layer = EditorTextLayer(itemId: item.itemId)
        layer.string = item.text
        layer.foregroundColor = item.color.cgColor
        layer.font = CGFont(item.font.fontName as CFString)
        layer.fontSize = fontSize
        layer.isWrapped = true
        layer.alignmentMode = kCAAlignmentCenter
        // I don't think we need to enable allowsFontSubpixelQuantization
        // or set truncationMode.

        // This text needs to be rendered at a scale that reflects the sceen scaling
        // AND the item's scaling.
        layer.contentsScale = UIScreen.main.scale * item.scaling

        // TODO: Min with measured width.
        let maxWidth = imageFrame.size.width * item.unitWidth
//        let maxWidth = viewSize.width * item.unitWidth

        let maxSize = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        // TODO: Is there a more accurate way to measure text in a CATextLayer?
        //       CoreText?
        let textBounds = (item.text as NSString).boundingRect(with: maxSize,
                                                              options: [
                                                                .usesLineFragmentOrigin,
                                                                .usesFontLeading
            ],
                                                              attributes: [
                                                                .font: item.font.withSize(fontSize)
            ],
                                                              context: nil)
        Logger.verbose("---- maxWidth: \(maxWidth), viewSize: \(viewSize), item.unitWidth: \(item.unitWidth), textBounds: \(textBounds)")
        let center = CGPoint(x: viewSize.width * item.unitCenter.x,
                             y: viewSize.height * item.unitCenter.y)
        let layerSize = CGSizeCeil(textBounds.size)
        layer.frame = CGRect(origin: CGPoint(x: center.x - layerSize.width * 0.5,
                                             y: center.y - layerSize.height * 0.5),
                             size: layerSize)

        let transform = CGAffineTransform.identity.scaledBy(x: item.scaling, y: item.scaling).rotated(by: item.rotationRadians)
        layer.setAffineTransform(transform)

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

    // MARK: - Coordinates

    public func locationUnit(forGestureRecognizer gestureRecognizer: UIGestureRecognizer,
                             transform: ImageEditorTransform) -> CGPoint {
        return ImageEditorCanvasView.locationUnit(forGestureRecognizer: gestureRecognizer,
                                                  view: self.clipView,
                                                  transform: transform)
    }

    public class func locationUnit(forGestureRecognizer gestureRecognizer: UIGestureRecognizer,
                                   view: UIView,
                                   transform: ImageEditorTransform) -> CGPoint {
        let locationInView = gestureRecognizer.location(in: view)
        return locationUnit(forLocationInView: locationInView,
                            viewSize: view.bounds.size,
                            transform: transform)
    }

    public func locationUnit(forLocationInView locationInView: CGPoint,
                             transform: ImageEditorTransform) -> CGPoint {
        let viewSize = self.clipView.bounds.size
        return ImageEditorCanvasView.locationUnit(forLocationInView: locationInView,
                                                  viewSize: viewSize,
                                                  transform: transform)
    }

    public class func locationUnit(forLocationInView locationInView: CGPoint,
                                   viewSize: CGSize,
                                   transform: ImageEditorTransform) -> CGPoint {
        let affineTransformStart = transform.affineTransform(viewSize: viewSize)
        let locationInContent = locationInView.applyingInverse(affineTransformStart)
        let locationUnit = locationInContent.toUnitCoordinates(viewSize: viewSize, shouldClamp: false)
        return locationUnit
    }

    // MARK: - Actions

    // Returns nil on error.
    //
    // We render using the transform parameter, not the transform from the model.
    // This allows this same method to be used for rendering "previews" for the
    // crop tool and the final output.
    @objc
    public class func renderForOutput(model: ImageEditorModel, transform: ImageEditorTransform) -> UIImage? {
        // TODO: Do we want to render off the main thread?
        AssertIsOnMainThread()

        // Render output at same size as source image.
        let dstSizePixels = transform.outputSizePixels
        let dstScale: CGFloat = 1.0 // The size is specified in pixels, not in points.
        // TODO: Reflect crop rectangle.
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
        // TODO:
        imageLayer.contentsScale = dstScale * transform.scaling
        contentView.layer.addSublayer(imageLayer)

        for item in model.items() {
            guard let layer = layerForItem(item: item,
                model: model,
                                           viewSize: viewSize) else {
                                            Logger.error("Couldn't create layer for item.")
                                            continue
            }
            // TODO: Should we do this for all layers?
            layer.contentsScale = dstScale * transform.scaling * item.outputScale()
            contentView.layer.addSublayer(layer)
        }

        CATransaction.commit()

        let image = view.renderAsImage(opaque: !hasAlpha, scale: dstScale)
        return image
    }

    // MARK: -

    public func textLayer(forLocation point: CGPoint) -> EditorTextLayer? {
        guard let sublayers = contentView.layer.sublayers else {
            return nil
        }
        for layer in sublayers {
            guard let textLayer = layer as? EditorTextLayer else {
                continue
            }
            if textLayer.hitTest(point) != nil {
                return textLayer
            }
        }
        return nil
    }
}

// MARK: -

extension ImageEditorCanvasView: ImageEditorModelObserver {

    public func imageEditorModelDidChange(before: ImageEditorContents,
                                          after: ImageEditorContents) {
        updateAllContent()
    }

    public func imageEditorModelDidChange(changedItemIds: [String]) {
        updateContent(changedItemIds: changedItemIds)
    }
}
