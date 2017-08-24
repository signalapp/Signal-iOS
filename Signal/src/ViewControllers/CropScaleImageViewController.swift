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

    var imageLayer: CALayer?

    var dashedBorderLayer: CAShapeLayer?

//    var defaultCropFramePoints: CGRect?
//    var currentCropFramePoints: CGRect?

    // In width/height.
    let targetAspectRatio: CGFloat = 1.0

    var srcImageSizePoints: CGSize = CGSize.zero
    var unitDefaultCropSizePoints: CGSize = CGSize.zero
//    var unitDefaultCropFramePoints : CGRect = CGRect.zero
//    coordinate
//    var maxUnitTranslation : CGPoint = CGPoint.zero

    // N = Scaled, zoomed in.
    let kMaxImageScale: CGFloat = 4.0
    // 1.0 = Unscaled, cropped to fill crop rect.
    let kMinImageScale: CGFloat = 1.0
    var imageScale: CGFloat = 1.0

    // 0
//    var imageTranslation : CGPoint = CGPoint.zero
    var srcTranslation: CGPoint = CGPoint.zero
//    var maxImageTranslation : CGPoint = CGPoint.zero

//
//    var imageScale : CGFloat = kMinImageScale
//    var imageTranslation : CGPoint = CGPoint.zero

//    var videoPlayer: MPMoviePlayerController?
//
//    var audioPlayer: OWSAudioAttachmentPlayer?
//    var audioStatusLabel: UILabel?
//    var audioPlayButton: UIButton?
//    var isAudioPlayingFlag = false
//    var isAudioPaused = false
//    var audioProgressSeconds: CGFloat = 0
//    var audioDurationSeconds: CGFloat = 0

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
        let unitSquareHeight: CGFloat = (targetAspectRatio >= 1.0 ? 1.0 : 1.0 / targetAspectRatio)
        let unitSquareWidth: CGFloat = (targetAspectRatio >= 1.0 ? targetAspectRatio * unitSquareHeight : 1.0)
        let unitSquareSize = CGSize(width: unitSquareWidth, height: unitSquareHeight)

        let imageSizePoints = srcImage.size
        guard
            (imageSizePoints.width > 0 && imageSizePoints.height > 0) else {
                return
        }
        self.srcImageSizePoints = imageSizePoints

        Logger.error("----")
        Logger.error("imageSizePoints: \(imageSizePoints)")
        Logger.error("unitSquareWidth: \(unitSquareWidth)")
        Logger.error("unitSquareHeight: \(unitSquareHeight)")

        // Default

        // The "default" (no scaling, no translation) crop frame, expressed in 
        // srcImage's coordinate system.
        unitDefaultCropSizePoints = defaultCropSizePoints(dstSizePoints:unitSquareSize)
//        unitDefaultCropFramePoints = defaultCropFramePoints(dstSizePoints:unitSquareSize)
        assert(imageSizePoints.width >= unitDefaultCropSizePoints.width)
        assert(imageSizePoints.height >= unitDefaultCropSizePoints.height)

//        maxUnitTranslation = CGPoint(x:
        Logger.error("unitDefaultCropSizePoints: \(unitDefaultCropSizePoints)")
        srcTranslation = CGPoint(x:(imageSizePoints.width - unitDefaultCropSizePoints.width) * 0.5,
                                        y:(imageSizePoints.height - unitDefaultCropSizePoints.height) * 0.5)
        Logger.error("srcTranslation: \(srcTranslation)")
//        let maxSrcTranslation = CGPoint(x:(imageSizePoints.width - unitDefaultCropSizePoints.width) * 0.5,
//                                        y:(imageSizePoints.height - unitDefaultCropSizePoints.height) * 0.5)
//        srcTranslation =

//        self.defaultCropFramePoints = defaultCropFramePoints
//        let maxCropSizePoints = CGSize(width:defaultCropFramePoints.width,
//                                       height:defaultCropFramePoints.height)
//        let minCropSizePoints = CGSize(width:defaultCropFramePoints.width / CropScaleImageViewController.kMaxImageScale,
//                                       height:defaultCropFramePoints.height / CropScaleImageViewController.kMaxImageScale)
//        Logger.error("defaultCropFramePoints: \(defaultCropFramePoints)")
//        Logger.error("maxCropSizePoints: \(maxCropSizePoints)")
//        Logger.error("minCropSizePoints: \(minCropSizePoints)")
//        
//        if currentCropFramePoints == nil {
//            currentCropFramePoints = defaultCropFramePoints
//        }
//        var cropFramePoints = currentCropFramePoints!
    }

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

//    private func defaultCropFramePoints(dstSizePoints: CGSize) -> (CGRect) {
//        assert(imageSizePoints.width > 0)
//        assert(imageSizePoints.height > 0)
//        
//        let imageAspectRatio = imageSizePoints.width / imageSizePoints.height
//        let dstAspectRatio = dstSizePoints.width / dstSizePoints.height
//        
//        var dstCropSizePoints = CGSize.zero
//        if imageAspectRatio > dstAspectRatio {
//            dstCropSizePoints = CGSize(width: dstSizePoints.width / dstSizePoints.height * imageSizePoints.height, height: imageSizePoints.height)
//        } else {
//            dstCropSizePoints = CGSize(width: imageSizePoints.width, height: dstSizePoints.height / dstSizePoints.width * imageSizePoints.width)
//        }
//        
//        let dstCropOriginPoints = CGPoint.zero
//        assert(dstCropOriginPoints.x >= 0)
//        assert(dstCropOriginPoints.y >= 0)
//        assert(dstCropOriginPoints.x <= dstSizePoints.width - dstCropSizePoints.width)
//        assert(dstCropOriginPoints.y <= dstSizePoints.height - dstCropSizePoints.height)
//        return CGRect(origin:dstCropOriginPoints, size:dstCropSizePoints)
//    }
//    
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

//    override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//
//        ViewControllerUtils.setAudioIgnoresHardwareMuteSwitch(true)
//    }
//
//    override func viewWillDisappear(_ animated: Bool) {
//        super.viewWillDisappear(animated)
//
//        ViewControllerUtils.setAudioIgnoresHardwareMuteSwitch(false)
//    }

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
        dashedBorderLayer.lineDashPattern = [6, 6]
        dashedBorderLayer.lineWidth = 2
        dashedBorderLayer.fillColor = nil
        imageView.layer.addSublayer(dashedBorderLayer)

        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(sender:))))
        contentView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(sender:))))
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

//    private func imageSizeAndViewSizePoints(imageView: UIView) -> (CGSize?, CGSize?) {
//        let imageSizePoints = srcImage.size
//        guard
//            (imageSizePoints.width > 0 && imageSizePoints.height > 0) else {
//                return (nil, nil)
//        }
//
//        let viewSizePoints = imageView.frame.size
//        guard
//            (viewSizePoints.width > 0 && viewSizePoints.height > 0) else {
//                return (nil, nil)
//        }
//
//        return (imageSizePoints, viewSizePoints)
//    }

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

//    private func imageBaseSizeAndOffset(imageSize:CGSize,viewSize:CGSize) -> (CGSize, CGPoint)
//    {
//        let imageAspectRatio = imageSize.width / imageSize.height
//        let viewAspectRatio = viewSize.width / viewSize.height
//        
//        var imageBaseSize = CGSize.zero
//        if imageAspectRatio > viewAspectRatio {
//            imageBaseSize = CGSize(width: imageSize.width / imageSize.height * viewSize.height, height: viewSize.height)
//        } else {
//            imageBaseSize = CGSize(width: viewSize.width, height: imageSize.height / imageSize.width * viewSize.width)
//        }
//        
//        let imageBaseOffset = CGPoint(x: (imageBaseSize.width - viewSize.width) * -0.5,
//                                      y: (imageBaseSize.height - viewSize.height) * -0.5)
//        
//        return (imageBaseSize, imageBaseOffset)
//    }

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
        guard unitDefaultCropSizePoints.width > 0 && unitDefaultCropSizePoints.height > 0 else {
            return
        }

//        var imageSizePoints : CGSize = CGSize.zero
//        var unitDefaultCropSizePoints : CGSize = CGSize.zero

//        let imageSizePoints = srcImage.size
//        guard
//            (imageSizePoints.width > 0 && imageSizePoints.height > 0) else {
//                return
//        }

        let viewSizePoints = imageView.frame.size
        guard
            (viewSizePoints.width > 0 && viewSizePoints.height > 0) else {
                return
        }

//        let (srcSizePointsOptional, viewSizePointsOptional) = imageSizeAndViewSizePoints(imageView:imageView)
//        guard let srcSizePoints = srcSizePointsOptional else {
//            return
//        }
//        guard let viewSizePoints = viewSizePointsOptional else {
//            return
//        }
        Logger.error("----")
        Logger.error("srcImageSizePoints: \(srcImageSizePoints)")
        Logger.error("viewSizePoints: \(viewSizePoints)")

//        let viewDefaultCropSizePoints = defaultCropSizePoints(dstSizePoints:viewSizePoints)
//        assert(viewDefaultCropSizePoints.width >= unitDefaultCropSizePoints.width)
//        assert(viewDefaultCropSizePoints.height >= unitDefaultCropSizePoints.height)
//
//        Logger.error("viewDefaultCropSizePoints: \(viewDefaultCropSizePoints)")

        Logger.error("imageScale: \(imageScale)")
        imageScale = max(kMinImageScale, min(kMaxImageScale, imageScale))
        Logger.error("imageScale (normalized): \(imageScale)")

        let srcCropSizePoints = CGSize(width:unitDefaultCropSizePoints.width / imageScale,
                                       height:unitDefaultCropSizePoints.height / imageScale)

        Logger.error("srcCropSizePoints: \(srcCropSizePoints)")

        let minSrcTranslationPoints = CGPoint.zero
        let maxSrcTranslationPoints = CGPoint(x:srcImageSizePoints.width - srcCropSizePoints.width,
                                              y:srcImageSizePoints.height - srcCropSizePoints.height
                                              )

        Logger.error("minSrcTranslationPoints: \(minSrcTranslationPoints)")
        Logger.error("maxSrcTranslationPoints: \(maxSrcTranslationPoints)")

        Logger.error("srcTranslation: \(srcTranslation)")
        srcTranslation = CGPoint(x: max(minSrcTranslationPoints.x, min(maxSrcTranslationPoints.x, srcTranslation.x)),
                                               y: max(minSrcTranslationPoints.y, min(maxSrcTranslationPoints.y, srcTranslation.y)))
        Logger.error("srcTranslation (normalized): \(srcTranslation)")

        let srcToViewRatio = viewSizePoints.width / srcCropSizePoints.width
        Logger.error("srcToViewRatio: \(srcToViewRatio)")

        let imageViewFrame = CGRect(origin: CGPoint(x:srcTranslation.x * -srcToViewRatio,
                                                    y:srcTranslation.y * -srcToViewRatio),
                                    size: CGSize(width:srcImageSizePoints.width * +srcToViewRatio,
                                                 height:srcImageSizePoints.height * +srcToViewRatio
                                                 ))
        Logger.error("imageViewFrame: \(imageViewFrame)")
        imageLayer.removeAllAnimations()
        imageLayer.frame = imageViewFrame

//        //        maxUnitTranslation = CGPoint(x:
//        Logger.error("unitDefaultCropSizePoints: \(unitDefaultCropSizePoints)")
//        srcTranslation = CGPoint(x:(imageSizePoints.width - unitDefaultCropSizePoints.width) * 0.5,
//                                 y:(imageSizePoints.height - unitDefaultCropSizePoints.height) * 0.5)
//        Logger.error("srcTranslation: \(srcTranslation)")
//
//        
//        // Default
//
//        let defaultCropFramePoints = self.defaultCropFramePoints(imageSizePoints:imageSizePoints, viewSizePoints:viewSizePoints)
//        self.defaultCropFramePoints = defaultCropFramePoints
//        let maxCropSizePoints = CGSize(width:defaultCropFramePoints.width,
//                                 height:defaultCropFramePoints.height)
//        let minCropSizePoints = CGSize(width:defaultCropFramePoints.width / CropScaleImageViewController.kMaxImageScale,
//                                 height:defaultCropFramePoints.height / CropScaleImageViewController.kMaxImageScale)
//        Logger.error("defaultCropFramePoints: \(defaultCropFramePoints)")
//        Logger.error("maxCropSizePoints: \(maxCropSizePoints)")
//        Logger.error("minCropSizePoints: \(minCropSizePoints)")
//
//        if currentCropFramePoints == nil {
//            currentCropFramePoints = defaultCropFramePoints
//        }
//        var cropFramePoints = currentCropFramePoints!
//
//        // Ensure the crop frame has valid origin and size.0
//        cropFramePoints.size.width = max(minCropSizePoints.width, min(maxCropSizePoints.width, cropFramePoints.size.width))
//        cropFramePoints.size.height = max(minCropSizePoints.height, min(maxCropSizePoints.height, cropFramePoints.size.height))
//        let minCropOriginPoints = CGPoint.zero
//        let maxCropOriginPoints = CGPoint(x:imageSizePoints.width - cropFramePoints.size.width,
//                                          y:imageSizePoints.height - cropFramePoints.size.height
//                                          )
//        cropFramePoints.origin.x = max(minCropOriginPoints.x, min(maxCropOriginPoints.x, cropFramePoints.origin.x))
//        cropFramePoints.origin.y = max(minCropOriginPoints.y, min(maxCropOriginPoints.y, cropFramePoints.origin.y))
//
//        // Update the property.
//        currentCropFramePoints = cropFramePoints
//        Logger.error("cropFramePoints: \(cropFramePoints)")
//
//        let displayScaleWidth = viewSizePoints.width / cropFramePoints.width
//        let displayScaleHeight = viewSizePoints.height / cropFramePoints.height
//        let displayScale = (displayScaleWidth + displayScaleHeight) * 0.5
//        let displayFramePoints = CGRect(origin: CGPoint(x:cropFramePoints.origin.x * -displayScale, y:cropFramePoints.origin.y * -displayScale),
//                                        size: CGSize(width:imageSizePoints.width * displayScale,
//                                                     height:imageSizePoints.height * displayScale))
//        Logger.error("displayScaleWidth: \(displayScaleWidth)")
//        Logger.error("displayScaleHeight: \(displayScaleHeight)")
//        Logger.error("displayScale: \(displayScale)")
//        Logger.error("displayFramePoints: \(displayFramePoints)")
//        imageLayer.frame = displayFramePoints
//        Logger.error("imageView: \(imageView.frame)")
//        Logger.error("imageLayer: \(displayFramePoints)")

////        let minCropFramePoints =
////        static let kMaxImageScale : CGFloat = 4.0
////        static let kMinImageScale : CGFloat = 1.0
//
//        let (imageBaseSize, imageBaseOffset) = imageBaseSizeAndOffset(imageSize:imageSize, viewSize:viewSize)
//        
//        if cropFramePoints == nil || defaultCropFramePoints == nil {
//            defaultCropFramePoints =
//                CGRect(origin: imageBaseOffset, size: imageBaseSize)
//            cropFramePoints = defaultCropFramePoints
//        }
//
////        guard let imageView = self.imageView else {
////            return
////        }
////        guard let imageLayer = self.imageLayer else {
////            return
////        }
////        guard let dashedBorderLayer = self.dashedBorderLayer else {
////            return
////        }
//        
////        let imageSize = srcImage.size
////        guard
////            (imageSize.width > 0 && imageSize.height > 0) else {
////                return
////        }
////        
////        let viewSize = imageView.frame.size
////        guard
////            (viewSize.width > 0 && viewSize.height > 0) else {
////                return
////        }
//        
//        // Base
//        
////        let imageAspectRatio = imageSize.width / imageSize.height
////        let viewAspectRatio = viewSize.width / viewSize.height
////        
////        var imageBaseSize = CGSize.zero
////        if imageAspectRatio > viewAspectRatio {
////            imageBaseSize = CGSize(width: imageSize.width / imageSize.height * viewSize.height, height: viewSize.height)
////        } else {
////            imageBaseSize = CGSize(width: viewSize.width, height: imageSize.height / imageSize.width * viewSize.width)
////        }
////
////        let imageBaseOffset = CGPoint(x: (imageBaseSize.width - viewSize.width) * -0.5,
////                                      y: (imageBaseSize.height - viewSize.height) * -0.5)
//        
//        // Display
//        
////        assert(imageScale >= CropScaleImageViewController.kMinImageScale)
////        assert(imageScale <= CropScaleImageViewController.kMaxImageScale)
//        
////        static let kMaxImageScale : CGFloat = 4.0
////        static let kMinImageScale : CGFloat = 1.0
////        
////        var imageScale : CGFloat = kMinImageScale
//
//        let imageDisplaySize = CGSize(width: imageBaseSize.width * imageScale,
//                                      height: imageBaseSize.height * imageScale)
//        let imageDisplayOffset = CGPoint(x: imageBaseOffset.x + imageTranslation.x * imageScale,
//                                         y: imageBaseOffset.y + imageTranslation.y * imageScale)
//        // TODO: Assert that imageDisplayOffset is valid.
////        var imageScale : CGFloat = 1.0
////        var imageTranslation : CGPoint = CGPoint.zero
//
//        imageLayer.frame = CGRect(origin: imageDisplayOffset, size: imageDisplaySize)
//        Logger.error("imageView: \(NSStringFromCGRect(imageView.frame))")
//        Logger.error("imageLayer: \(imageLayer.frame)")

        dashedBorderLayer.frame = imageView.bounds
        dashedBorderLayer.path = UIBezierPath(rect: imageView.bounds).cgPath
    }

    var srcTranslationAtPinchStart: CGPoint = CGPoint.zero
    var imageScaleAtPinchStart: CGFloat = 0

//    var currentCropFramePointsAtPinchStart: CGRect = CGRect.zero
    var lastPinchLocation: CGPoint = CGPoint.zero
    var lastPinchScale: CGFloat = 1.0
//    var isPinching = false

    func handlePinch(sender: UIPinchGestureRecognizer) {
        Logger.error("pinch scale: \(sender.scale)")
        switch (sender.state) {
        case .possible:
            break
        case .began:
            srcTranslationAtPinchStart = srcTranslation
            imageScaleAtPinchStart = imageScale

//            guard let currentCropFramePoints = currentCropFramePoints else {
//                isPinching = false
//                return
//            }
//            currentCropFramePointsAtPinchStart = currentCropFramePoints
//            isPinching = true
            lastPinchLocation =
                sender.location(in: sender.view)
            lastPinchScale = sender.scale
            break
        case .changed, .ended:
            guard let imageView = self.imageView else {
                return
            }
//            guard isPinching else {
//                return
//            }
//            guard let imageView = self.imageView else {
//                return
//            }
//            
//            let (_, viewSizePointsOptional) = imageSizeAndViewSizePoints(imageView:imageView)
//            guard let viewSizePoints = viewSizePointsOptional else {
//                return
//            }

//            guard let imageView = self.imageView else {
//                return
//            }
//            let viewSizePoints = imageView.frame.size
//            Logger.error("viewSizePoints: \(viewSizePoints)")
//            let srcCropSizePoints = CGSize(width:unitDefaultCropSizePoints.width / imageScale,
//                                           height:unitDefaultCropSizePoints.height / imageScale)
//            Logger.error("srcCropSizePoints: \(srcCropSizePoints)")
//            
//            let srcToViewRatio = viewSizePoints.width / srcCropSizePoints.width

            let location =
                sender.location(in: sender.view)
            let scaleDiff = sender.scale / lastPinchScale
            Logger.error("scaling \(lastPinchScale) \(sender.scale) -> \(scaleDiff)")

//            unitDefaultCropSizePoints = defaultCropSizePoints(dstSizePoints:unitSquareSize)
//            //        unitDefaultCropFramePoints = defaultCropFramePoints(dstSizePoints:unitSquareSize)
//            assert(imageSizePoints.width >= unitDefaultCropSizePoints.width)
//            assert(imageSizePoints.height >= unitDefaultCropSizePoints.height)

            //        maxUnitTranslation = CGPoint(x:
//            Logger.error("unitDefaultCropSizePoints: \(unitDefaultCropSizePoints)")
//            srcTranslation = CGPoint(x:(imageSizePoints.width - unitDefaultCropSizePoints.width) * 0.5,
//                                     y:(imageSizePoints.height - unitDefaultCropSizePoints.height) * 0.5)

            // Update the scaling
            let srcCropSizeBeforeScalePoints = CGSize(width:unitDefaultCropSizePoints.width / imageScale,
                                                      height:unitDefaultCropSizePoints.height / imageScale)
            imageScale = max(kMinImageScale, min(kMaxImageScale, imageScale * scaleDiff))
            let srcCropSizeAfterScalePoints = CGSize(width:unitDefaultCropSizePoints.width / imageScale,
                                                      height:unitDefaultCropSizePoints.height / imageScale)
            // Since the translation state reflects the "upper left" corner of the crop region, we need to
            // adjust the translation when scaling.
            srcTranslation.x += (srcCropSizeBeforeScalePoints.width - srcCropSizeAfterScalePoints.width) * 0.5
            srcTranslation.y += (srcCropSizeBeforeScalePoints.height - srcCropSizeAfterScalePoints.height) * 0.5

            // Update translation

            let viewSizePoints = imageView.frame.size
            Logger.error("viewSizePoints: \(viewSizePoints)")
            let srcCropSizePoints = CGSize(width:unitDefaultCropSizePoints.width / imageScale,
                                           height:unitDefaultCropSizePoints.height / imageScale)
            Logger.error("srcCropSizePoints: \(srcCropSizePoints)")

            let srcToViewRatio = viewSizePoints.width / srcCropSizePoints.width
            Logger.error("srcToViewRatio: \(srcToViewRatio)")
            let viewToSrcRatio = 1 / srcToViewRatio
            Logger.error("viewToSrcRatio: \(viewToSrcRatio)")

            let gestureTranslation = CGPoint(x:location.x - lastPinchLocation.x,
                                            y:location.y - lastPinchLocation.y)

            Logger.error("gestureTranslation: \(gestureTranslation)")

            //            var cropFramePoints = currentCropFramePointsAtPanStart
            //            cropFramePoints.origin.x += +gestureTranslation.x / viewSizePoints.width * currentCropFramePointsAtPanStart.width
            //            cropFramePoints.origin.y += -gestureTranslation.y / viewSizePoints.height * currentCropFramePointsAtPanStart.height
            //            self.currentCropFramePoints = cropFramePoints

            srcTranslation = CGPoint(x:srcTranslation.x + gestureTranslation.x * -viewToSrcRatio,
                                     y:srcTranslation.y + gestureTranslation.y * -viewToSrcRatio)

//            let translationOffset = CGPoint(x:location.x - lastPinchLocation.x,
//                                             y:location.y - lastPinchLocation.y)
//            let oldCropFramePoints = self.currentCropFramePoints!
//            var newCropFramePoints = oldCropFramePoints
//            newCropFramePoints.size.width /= scaleDiff
//            newCropFramePoints.size.height /= scaleDiff
//            newCropFramePoints.origin.x += (oldCropFramePoints.size.width - newCropFramePoints.size.width) * 0.5
//            newCropFramePoints.origin.y += (oldCropFramePoints.size.height - newCropFramePoints.size.height) * 0.5
////            cropFramePoints.origin.y += -gestureTranslation.y / viewSizePoints.height * currentCropFramePointsAtPinchStart.height
////            cropFramePoints.origin.x += +gestureTranslation.x / viewSizePoints.width * currentCropFramePointsAtPinchStart.width
////            cropFramePoints.origin.y += -gestureTranslation.y / viewSizePoints.height * currentCropFramePointsAtPinchStart.height
//            self.currentCropFramePoints = newCropFramePoints

            lastPinchLocation = location
            lastPinchScale = sender.scale

//            if sender.state == .ended {
//                isPinching = false
//            }
            break
        case .cancelled, .failed:
            srcTranslation = srcTranslationAtPinchStart
            imageScale = imageScaleAtPinchStart
//            guard isPinching else {
//                return
//            }
//            currentCropFramePoints
//                = currentCropFramePointsAtPinchStart
//            isPinching = false
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
            Logger.error("viewSizePoints: \(viewSizePoints)")
            let srcCropSizePoints = CGSize(width:unitDefaultCropSizePoints.width / imageScale,
                                           height:unitDefaultCropSizePoints.height / imageScale)
            Logger.error("srcCropSizePoints: \(srcCropSizePoints)")

            let srcToViewRatio = viewSizePoints.width / srcCropSizePoints.width
            Logger.error("srcToViewRatio: \(srcToViewRatio)")
            let viewToSrcRatio = 1 / srcToViewRatio
            Logger.error("viewToSrcRatio: \(viewToSrcRatio)")

            let gestureTranslation =
                sender.translation(in: sender.view)

            Logger.error("gestureTranslation: \(gestureTranslation)")

//            var cropFramePoints = currentCropFramePointsAtPanStart
//            cropFramePoints.origin.x += +gestureTranslation.x / viewSizePoints.width * currentCropFramePointsAtPanStart.width
//            cropFramePoints.origin.y += -gestureTranslation.y / viewSizePoints.height * currentCropFramePointsAtPanStart.height
//            self.currentCropFramePoints = cropFramePoints

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
            // TODO
            let dstImage = self.srcImage
            successCompletion?(dstImage)
        })
    }
}
