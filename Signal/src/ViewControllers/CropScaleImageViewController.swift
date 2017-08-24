//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer

class OWSLayerView: UIView {
    var layoutCallback : (() -> Void)?

    required init(frame: CGRect, layoutCallback : @escaping () -> Void) {
        self.layoutCallback = layoutCallback
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        self.layoutCallback = {
        }
        super.init(coder: aDecoder)
    }

    override var bounds: CGRect {
        didSet {
            guard let layoutCallback = self.layoutCallback else {
                return
            }
            layoutCallback()
        }
    }

    override var frame: CGRect {
        didSet {
            guard let layoutCallback = self.layoutCallback else {
                return
            }
            layoutCallback()
        }
    }
}

class CropScaleImageViewController: OWSViewController {

    let TAG = "[CropScaleImageViewController]"

    // MARK: Properties

    let srcImage: UIImage

    var successCompletion: ((UIImage) -> Void)?

    var imageView: UIView?

    // We use a CALayer to render the image for performance reasons.
    var imageLayer: CALayer?

    var dashedBorderLayer: CAShapeLayer?

    // In width/height.
    let dstAspectRatio: CGFloat = 1.0

    // The size of the src image in points.
    var srcImageSizePoints: CGSize = CGSize.zero
    // The size of the default crop region, which is the
    // largest crop region with the correct dst aspect ratio
    // that fits in the src image's aspect ratio,
    // in src image point coordinates.
    var srcDefaultCropSizePoints: CGSize = CGSize.zero

    // N = Scaled, zoomed in.
    let kMaxImageScale: CGFloat = 4.0
    // 1.0 = Unscaled, cropped to fill crop rect.
    let kMinImageScale: CGFloat = 1.0
    // This represents the current scaling of the src image.
    var imageScale: CGFloat = 1.0

    // This represents the current translation from the
    // upper-left corner of the src image to the upper-left
    // corner of the crop region in src image point coordinates.
    var srcTranslation: CGPoint = CGPoint.zero

    // MARK: Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        self.srcImage = UIImage(named:"fail")!
        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")

        configureCropAndScale()
    }

    required init(srcImage: UIImage, successCompletion : @escaping (UIImage) -> Void) {
        self.srcImage = srcImage
        self.successCompletion = successCompletion
        super.init(nibName: nil, bundle: nil)

        configureCropAndScale()
    }

    // MARK: Cropping and Scaling

    private func configureCropAndScale() {
        // Size of bounding box that reflects the target aspect ratio, whose longer side = 1.
        let unitSquareHeight: CGFloat = (dstAspectRatio >= 1.0 ? 1.0 : 1.0 / dstAspectRatio)
        let unitSquareWidth: CGFloat = (dstAspectRatio >= 1.0 ? dstAspectRatio * unitSquareHeight : 1.0)
        let unitSquareSize = CGSize(width: unitSquareWidth, height: unitSquareHeight)

        srcImageSizePoints = srcImage.size
        guard
            (srcImageSizePoints.width > 0 && srcImageSizePoints.height > 0) else {
                return
        }

        // Default

        // The "default" (no scaling, no translation) crop frame, expressed in
        // srcImage's coordinate system.
        srcDefaultCropSizePoints = defaultCropSizePoints(dstSizePoints:unitSquareSize)
        assert(srcImageSizePoints.width >= srcDefaultCropSizePoints.width)
        assert(srcImageSizePoints.height >= srcDefaultCropSizePoints.height)

        // By default, center the crop region in the src image.
        srcTranslation = CGPoint(x:(srcImageSizePoints.width - srcDefaultCropSizePoints.width) * 0.5,
                                 y:(srcImageSizePoints.height - srcDefaultCropSizePoints.height) * 0.5)
    }

    // Given a dst size, find the size of the largest crop region
    // that fits in the src image.
    private func defaultCropSizePoints(dstSizePoints: CGSize) -> (CGSize) {
        assert(srcImageSizePoints.width > 0)
        assert(srcImageSizePoints.height > 0)

        let imageAspectRatio = srcImageSizePoints.width / srcImageSizePoints.height
        let dstAspectRatio = dstSizePoints.width / dstSizePoints.height

        var dstCropSizePoints = CGSize.zero
        if imageAspectRatio > dstAspectRatio {
            dstCropSizePoints = CGSize(width: dstSizePoints.width / dstSizePoints.height * srcImageSizePoints.height, height: srcImageSizePoints.height)
        } else {
            dstCropSizePoints = CGSize(width: srcImageSizePoints.width, height: dstSizePoints.height / dstSizePoints.width * srcImageSizePoints.width)
        }
        return dstCropSizePoints
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.white

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem:.stop,
                                                                target:self,
                                                                action:#selector(cancelPressed))
        self.navigationItem.title = NSLocalizedString("CROP_SCALE_IMAGE_VIEW_TITLE",
                                                      comment: "Title for the 'crop/scale image' dialog.")

        createViews()
    }

    // MARK: - Create Views

    private func createViews() {
        let previewTopMargin: CGFloat = 30
        let previewHMargin: CGFloat = 20

        let contentView = UIView()
        self.view.addSubview(contentView)
        contentView.autoPinWidthToSuperview(withMargin:previewHMargin)
        contentView.autoPin(toTopLayoutGuideOf: self, withInset:previewTopMargin)

        createButtonRow(contentView:contentView)

        let imageHMargin: CGFloat = 0
        let imageView = OWSLayerView(frame:CGRect.zero, layoutCallback: {[weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.updateImageLayout()
        })
        imageView.clipsToBounds = true
        self.imageView = imageView
        contentView.addSubview(imageView)
        imageView.autoPinWidthToSuperview(withMargin:imageHMargin)
        imageView.autoVCenterInSuperview()
        imageView.autoPinToSquareAspectRatio()

        let imageLayer = CALayer()
        self.imageLayer = imageLayer
        imageLayer.contents = srcImage.cgImage
        imageView.layer.addSublayer(imageLayer)

        let dashedBorderLayer = CAShapeLayer()
        self.dashedBorderLayer = dashedBorderLayer
        dashedBorderLayer.strokeColor = UIColor.ows_materialBlue().cgColor
        dashedBorderLayer.lineDashPattern = [10, 10]
        dashedBorderLayer.lineWidth = 4
        dashedBorderLayer.fillColor = nil
        imageView.layer.addSublayer(dashedBorderLayer)

        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(sender:))))
        contentView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(sender:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(sender:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        contentView.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateImageLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.view.layoutSubviews()
        updateImageLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateImageLayout()
    }

    private func defaultCropFramePoints(imageSizePoints: CGSize, viewSizePoints: CGSize) -> (CGRect) {
        let imageAspectRatio = imageSizePoints.width / imageSizePoints.height
        let viewAspectRatio = viewSizePoints.width / viewSizePoints.height

        var defaultCropSizePoints = CGSize.zero
        if imageAspectRatio > viewAspectRatio {
            defaultCropSizePoints = CGSize(width: viewSizePoints.width / viewSizePoints.height * imageSizePoints.height, height: imageSizePoints.height)
        } else {
            defaultCropSizePoints = CGSize(width: imageSizePoints.width, height: viewSizePoints.height / viewSizePoints.width * imageSizePoints.width)
        }

        let defaultCropOriginPoints = CGPoint(x: (imageSizePoints.width - defaultCropSizePoints.width) * 0.5,
                                              y: (imageSizePoints.height - defaultCropSizePoints.height) * 0.5)
        assert(defaultCropOriginPoints.x >= 0)
        assert(defaultCropOriginPoints.y >= 0)
        assert(defaultCropOriginPoints.x <= imageSizePoints.width - defaultCropSizePoints.width)
        assert(defaultCropOriginPoints.y <= imageSizePoints.height - defaultCropSizePoints.height)
        return CGRect(origin:defaultCropOriginPoints, size:defaultCropSizePoints)
    }

    // Updates the image view _AND_ normalizes the current scale/translate state.
    private func updateImageLayout() {
        guard let imageView = self.imageView else {
            return
        }
        guard let imageLayer = self.imageLayer else {
            return
        }
        guard let dashedBorderLayer = self.dashedBorderLayer else {
            return
        }
        guard srcImageSizePoints.width > 0 && srcImageSizePoints.height > 0 else {
            return
        }
        guard srcDefaultCropSizePoints.width > 0 && srcDefaultCropSizePoints.height > 0 else {
            return
        }

        let viewSizePoints = imageView.frame.size
        guard
            (viewSizePoints.width > 0 && viewSizePoints.height > 0) else {
                return
        }

        // Normalize the scaling property.
        imageScale = max(kMinImageScale, min(kMaxImageScale, imageScale))

        let srcCropSizePoints = CGSize(width:srcDefaultCropSizePoints.width / imageScale,
                                       height:srcDefaultCropSizePoints.height / imageScale)

        let minSrcTranslationPoints = CGPoint.zero
        let maxSrcTranslationPoints = CGPoint(x:srcImageSizePoints.width - srcCropSizePoints.width,
                                              y:srcImageSizePoints.height - srcCropSizePoints.height
        )

        // Normalize the translation property.
        srcTranslation = CGPoint(x: max(minSrcTranslationPoints.x, min(maxSrcTranslationPoints.x, srcTranslation.x)),
                                 y: max(minSrcTranslationPoints.y, min(maxSrcTranslationPoints.y, srcTranslation.y)))

        let srcToViewRatio = viewSizePoints.width / srcCropSizePoints.width

        let imageViewFrame = CGRect(origin: CGPoint(x:srcTranslation.x * -srcToViewRatio,
                                                    y:srcTranslation.y * -srcToViewRatio),
                                    size: CGSize(width:srcImageSizePoints.width * +srcToViewRatio,
                                                 height:srcImageSizePoints.height * +srcToViewRatio
        ))

        // Disable implicit animations.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = imageViewFrame
        CATransaction.commit()

        dashedBorderLayer.frame = imageView.bounds
        dashedBorderLayer.path = UIBezierPath(rect: imageView.bounds).cgPath
    }

    var srcTranslationAtPinchStart: CGPoint = CGPoint.zero
    var imageScaleAtPinchStart: CGFloat = 0
    var lastPinchLocation: CGPoint = CGPoint.zero
    var lastPinchScale: CGFloat = 1.0

    func handlePinch(sender: UIPinchGestureRecognizer) {
        switch (sender.state) {
        case .possible:
            break
        case .began:
            srcTranslationAtPinchStart = srcTranslation
            imageScaleAtPinchStart = imageScale

            lastPinchLocation =
                sender.location(in: sender.view)
            lastPinchScale = sender.scale
            break
        case .changed, .ended:
            guard let imageView = self.imageView else {
                return
            }

            if sender.numberOfTouches > 1 {
                let location =
                    sender.location(in: sender.view)
                let scaleDiff = sender.scale / lastPinchScale

                // Update scaling.
                let srcCropSizeBeforeScalePoints = CGSize(width:srcDefaultCropSizePoints.width / imageScale,
                                                          height:srcDefaultCropSizePoints.height / imageScale)
                imageScale = max(kMinImageScale, min(kMaxImageScale, imageScale * scaleDiff))
                let srcCropSizeAfterScalePoints = CGSize(width:srcDefaultCropSizePoints.width / imageScale,
                                                         height:srcDefaultCropSizePoints.height / imageScale)
                // Since the translation state reflects the "upper left" corner of the crop region, we need to
                // adjust the translation when scaling.
                srcTranslation.x += (srcCropSizeBeforeScalePoints.width - srcCropSizeAfterScalePoints.width) * 0.5
                srcTranslation.y += (srcCropSizeBeforeScalePoints.height - srcCropSizeAfterScalePoints.height) * 0.5

                // Update translation.
                let viewSizePoints = imageView.frame.size
                let srcCropSizePoints = CGSize(width:srcDefaultCropSizePoints.width / imageScale,
                                               height:srcDefaultCropSizePoints.height / imageScale)

                let viewToSrcRatio = srcCropSizePoints.width / viewSizePoints.width

                let gestureTranslation = CGPoint(x:location.x - lastPinchLocation.x,
                                                 y:location.y - lastPinchLocation.y)

                srcTranslation = CGPoint(x:srcTranslation.x + gestureTranslation.x * -viewToSrcRatio,
                                         y:srcTranslation.y + gestureTranslation.y * -viewToSrcRatio)

                lastPinchLocation = location
                lastPinchScale = sender.scale
            }
            break
        case .cancelled, .failed:
            srcTranslation = srcTranslationAtPinchStart
            imageScale = imageScaleAtPinchStart
            break
        }

        updateImageLayout()
    }

    var srcTranslationAtPanStart: CGPoint = CGPoint.zero

    func handlePan(sender: UIPanGestureRecognizer) {
        switch (sender.state) {
        case .possible:
            break
        case .began:
            srcTranslationAtPanStart = srcTranslation
            break
        case .changed, .ended:
            guard let imageView = self.imageView else {
                return
            }
            let viewSizePoints = imageView.frame.size
            let srcCropSizePoints = CGSize(width:srcDefaultCropSizePoints.width / imageScale,
                                           height:srcDefaultCropSizePoints.height / imageScale)

            let viewToSrcRatio = srcCropSizePoints.width / viewSizePoints.width

            let gestureTranslation =
                sender.translation(in: sender.view)

            // Update translation.
            srcTranslation = CGPoint(x:srcTranslationAtPanStart.x + gestureTranslation.x * -viewToSrcRatio,
                                     y:srcTranslationAtPanStart.y + gestureTranslation.y * -viewToSrcRatio)
            break
        case .cancelled, .failed:
            srcTranslation
                = srcTranslationAtPanStart
            break
        }

        updateImageLayout()
    }

    func handleDoubleTap(sender: UIPanGestureRecognizer) {
        if (sender.state == .recognized) {
            if imageScale > 1.5 {
                imageScale = kMinImageScale
            }
        }

        updateImageLayout()
    }

    private func createButtonRow(contentView: UIView) {
        let buttonTopMargin = ScaleFromIPhone5To7Plus(30, 40)
        let buttonBottomMargin = ScaleFromIPhone5To7Plus(25, 40)

        let buttonRow = UIView()
        self.view.addSubview(buttonRow)
        buttonRow.autoPinWidthToSuperview()
        buttonRow.autoPinEdge(toSuperviewEdge:.bottom, withInset:buttonBottomMargin)
        buttonRow.autoPinEdge(.top, to:.bottom, of:contentView, withOffset:buttonTopMargin)

        let doneButton = createButton(title: NSLocalizedString("BUTTON_DONE",
                                                               comment: "Label for generic done button."),
                                      color : UIColor.ows_materialBlue(),
                                      action: #selector(donePressed))
        buttonRow.addSubview(doneButton)
        doneButton.autoPinEdge(toSuperviewEdge:.top)
        doneButton.autoPinEdge(toSuperviewEdge:.bottom)
        doneButton.autoHCenterInSuperview()
    }

    private func createButton(title: String, color: UIColor, action: Selector) -> UIButton {
        let buttonFont = UIFont.ows_mediumFont(withSize:ScaleFromIPhone5To7Plus(18, 22))
        let buttonCornerRadius = ScaleFromIPhone5To7Plus(4, 5)
        let buttonWidth = ScaleFromIPhone5To7Plus(110, 140)
        let buttonHeight = ScaleFromIPhone5To7Plus(35, 45)

        let button = UIButton()
        button.setTitle(title, for:.normal)
        button.setTitleColor(UIColor.white, for:.normal)
        button.titleLabel!.font = buttonFont
        button.backgroundColor = color
        button.layer.cornerRadius = buttonCornerRadius
        button.clipsToBounds = true
        button.addTarget(self, action:action, for:.touchUpInside)
        button.autoSetDimension(.width, toSize:buttonWidth)
        button.autoSetDimension(.height, toSize:buttonHeight)
        return button
    }

    // MARK: - Event Handlers

    func cancelPressed(sender: UIButton) {
        dismiss(animated: true, completion:nil)
    }

    func donePressed(sender: UIButton) {
        let successCompletion = self.successCompletion
        dismiss(animated: true, completion: {
            // TODO:
            let dstImage = self.srcImage
            successCompletion?(dstImage)
        })
    }
}
