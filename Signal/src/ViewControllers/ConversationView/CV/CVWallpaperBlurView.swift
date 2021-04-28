//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVWallpaperBlurView: ManualLayoutViewWithLayer {

    private var isPreview = false

    private weak var provider: WallpaperBlurProvider?

    private let imageView = CVImageView()
//    private let imageLayer = CALayer()
    private let maskLayer = CAShapeLayer()

    private var state: WallpaperBlurState?

    required init() {
        super.init(name: "CVWallpaperBlurView")

        self.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.layer.mask = maskLayer
        imageView.layer.masksToBounds = true
        addSubview(imageView)

//        addSubview(imageView) { view in
//            guard let view = view as? CVWallpaperBlurView else {
//                owsFailDebug("Invalid view.")
//                return
//            }
//            view.imageView.frame = view.imageViewFrame
//        }
//        self.layer.addSublayer(imageLayer)
//        self.layer.masksToBounds = true
//        imageLayer.contentsGravity = .resizeAspectFill
//        imageLayer.mask = maskLayer
//        self.layer.mask = maskLayer

        addLayoutBlock { [weak self] _ in
            self?.applyLayout()
        }
//        addLayoutBlock { view in
//            guard let view = view as? CVWallpaperBlurView else {
//                owsFailDebug("Invalid view.")
//                return
//            }
//            view.imageLayer.frame = view.imageViewFrame
//        }
    }

    private func applyLayout() {
        imageView.frame = imageViewFrame
//        imageLayer.frame = imageViewFrame

        maskLayer.frame = imageView.bounds
        let maskPath = UIBezierPath(roundedRect: maskFrame, cornerRadius: layer.cornerRadius)
        maskLayer.path = maskPath.cgPath
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    public func configureForPreview() {
        self.isPreview = true
        imageView.isHidden = true
    }

    public func configure(provider: WallpaperBlurProvider) {
        self.isPreview = false
        imageView.isHidden = false
        self.backgroundColor = nil
        // TODO: Observe provider changes.
        self.provider = provider

        configure()
    }

    private func configure() {
        guard !isPreview else {
            self.backgroundColor = Theme.backgroundColor
            return
        }
        guard let provider = provider else {
            owsFailDebug("Missing provider.")
            resetContent()
            return
        }
        guard let state = provider.wallpaperBlurState else {
            resetContent()
            return
        }
        guard state.id != self.state?.id else {
            ensurePositioning()
            return
        }
        self.state = state
        imageView.image = state.image
//        imageLayer.contents = state.image.cgImage

        ensurePositioning()
    }

    private var imageViewFrame: CGRect = .zero
    private var maskFrame: CGRect = .zero

    private func ensurePositioning() {
        guard !isPreview else {
            return
        }
//        guard let delegate = delegate else {
//            owsFailDebug("Missing delegate.")
//            resetContent()
//            return
//        }
        guard let state = self.state else {
            resetContent()
            return
        }
//        guard let image = imageView.image else {
//            owsFailDebug("Missing image.")
//            resetContent()
//            return
//        }
        let referenceView = state.referenceView
        self.imageViewFrame = self.convert(referenceView.bounds, from: referenceView)
        self.maskFrame = referenceView.convert(self.bounds, from: self)

//        let widthFactor = referenceView.bounds.width / image.size.width
//        let heightFactor = referenceView.bounds.height / image.size.height
//        let scalingFactor = max(widthFactor, heightFactor)
//        let contentsScale = 1 / scalingFactor
//        Logger.verbose("---- scalingFactor: \(scalingFactor), contentsScale: \(layer.contentsScale), UIScreen.main.scale: \(UIScreen.main.scale)")
////        self.layer.contentsScale
//        // https://developer.apple.com/documentation/quartzcore/calayer/1410746-contentsscale
//        // By using contentsScale to scale the blurred background image, we not only
//        // (increase) the scale so that it is rendered at the correct size, we also
//        // reduce the size of the bitmap used to present the layer content, which
//        // helps perf.
//        self.layer.contentsScale = contentsScale
//        let referencePoint = self.convert(referenceView.bounds.center, from: referenceView)
//        Logger.verbose("---- contentsCenter: \(layer.contentsCenter), position: \(layer.position), anchorPoint: \(layer.anchorPoint), referencePoint: \(referencePoint)")
        Logger.verbose("---- imageViewFrame: \(imageViewFrame)")
        Logger.verbose("---- maskFrame: \(maskFrame)")
//        self.layer.contentsCenter = CGRect(origin: .zero, size: <#T##CGSize#>) referencePoint
//        imageView.frame = imageViewFrame
        applyLayout()
    }

    private func resetContent() {
        isPreview = false
        imageView.image = nil
//        imageLayer.contents = nil
        imageViewFrame = .zero
        maskFrame = .zero
        provider = nil
    }
}
