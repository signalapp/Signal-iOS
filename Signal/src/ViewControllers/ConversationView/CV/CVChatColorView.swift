//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVChatColorView: ManualLayoutViewWithLayer {
//
//    private var isPreview = false
//
//    private weak var provider: WallpaperBlurProvider?
//
//    private let imageView = CVImageView()
//    private let maskLayer = CAShapeLayer()
//
//    private var state: WallpaperBlurState?
//    private var maskCornerRadius: CGFloat = 0
//
//    required init() {
//        super.init(name: "CVWallpaperBlurView")
//
//        self.clipsToBounds = true
//        self.layer.zPosition = -1
//
//        imageView.contentMode = .scaleAspectFill
//        imageView.layer.mask = maskLayer
//        imageView.layer.masksToBounds = true
//        addSubview(imageView)
//
//        addLayoutBlock { [weak self] _ in
//            self?.applyLayout()
//        }
//    }
//
//    private func applyLayout() {
//        // Prevent the layers from animating changes.
//        CATransaction.begin()
//        CATransaction.setDisableActions(true)
//
//        imageView.frame = imageViewFrame
//        maskLayer.frame = imageView.bounds
//        let maskPath = UIBezierPath(roundedRect: maskFrame, cornerRadius: maskCornerRadius)
//        maskLayer.path = maskPath.cgPath
//
//        CATransaction.commit()
//    }
//
//    @available(swift, obsoleted: 1.0)
//    required init(name: String) {
//        owsFail("Do not use this initializer.")
//    }
//
//    public func configureForPreview(maskCornerRadius: CGFloat) {
//        resetContentAndConfiguration()
//
//        self.isPreview = true
//        self.maskCornerRadius = maskCornerRadius
//
//        updateIfNecessary()
//    }
//
//    public func configure(provider: WallpaperBlurProvider,
//                          maskCornerRadius: CGFloat) {
//        resetContentAndConfiguration()
//
//        self.isPreview = false
//        // TODO: Observe provider changes.
//        self.provider = provider
//        self.maskCornerRadius = maskCornerRadius
//
//        updateIfNecessary()
//    }
//
//    public func updateIfNecessary() {
//        guard !isPreview else {
//            self.backgroundColor = Theme.backgroundColor
//            imageView.isHidden = true
//            return
//        }
//        guard let provider = provider else {
//            owsFailDebug("Missing provider.")
//            resetContentAndConfiguration()
//            return
//        }
//        guard let state = provider.wallpaperBlurState else {
//            resetContent()
//            return
//        }
//        guard state.id != self.state?.id else {
//            ensurePositioning()
//            return
//        }
//        self.state = state
//        imageView.image = state.image
//        imageView.isHidden = false
//
//        ensurePositioning()
//    }
//
//    private var imageViewFrame: CGRect = .zero
//    private var maskFrame: CGRect = .zero
//
//    private func ensurePositioning() {
//        guard !isPreview else {
//            return
//        }
//        guard let state = self.state else {
//            resetContent()
//            return
//        }
//        let referenceView = state.referenceView
//        self.imageViewFrame = self.convert(referenceView.bounds, from: referenceView)
//        self.maskFrame = referenceView.convert(self.bounds, from: self)
//
//        applyLayout()
//    }
//
//    private func resetContent() {
//        backgroundColor = nil
//        imageView.image = nil
//        imageView.isHidden = false
//        imageViewFrame = .zero
//        maskFrame = .zero
//        state = nil
//    }
//
//    public func resetContentAndConfiguration() {
//        isPreview = false
//        provider = nil
//        maskCornerRadius = 0
//
//        resetContent()
//    }
// }

    public var chatColor: CVChatColor? {
        didSet {
            configure()
        }
    }

    private let gradientLayer = CAGradientLayer()

    public init() {
        super.init(name: "CVChatColorView")

        addLayoutBlock { view in
            guard let view = view as? CVChatColorView else { return }
            view.gradientLayer.frame = view.bounds
            view.configure()
        }
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    private func configure() {
        guard let chatColor = self.chatColor else {
            self.backgroundColor = nil
            gradientLayer.removeFromSuperlayer()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch chatColor {
        case .solidColor(let color):
            backgroundColor = color
            gradientLayer.removeFromSuperlayer()
            Logger.verbose("---- solid bounds: \(bounds), color: \(color.asOWSColor), ")
        case .gradient(let color1, let color2, let angleRadians):

            if gradientLayer.superlayer != self.layer {
                gradientLayer.removeFromSuperlayer()
                layer.addSublayer(gradientLayer)
            }

            gradientLayer.frame = self.bounds

            gradientLayer.colors = [
                color1.cgColor,
                color2.cgColor
            ]
            // TODO:

            /* The start and end points of the gradient when drawn into the layer's
             * coordinate space. The start point corresponds to the first gradient
             * stop, the end point to the last gradient stop. Both points are
             * defined in a unit coordinate space that is then mapped to the
             * layer's bounds rectangle when drawn. (I.e. [0,0] is the bottom-left
             * corner of the layer, [1,1] is the top-right corner.) The default values
             * are [.5,0] and [.5,1] respectively. Both are animatable. */
            let unitCenter = CGPoint(x: 0.5, y: 0.5)
            let startVector = CGPoint(x: +sin(angleRadians), y: +cos(angleRadians))
            let startScale: CGFloat
            // In rectangle mode, we want the startPoint and endPoint to reside
            // on the edge of the unit square, and thus edge of the rectangle.
            // We therefore scale such that longer axis is a half unit.
            let startSquareScale: CGFloat = max(abs(startVector.x), abs(startVector.y))
            startScale = 0.5 / startSquareScale

            // UIKit uses an upper-left origin.
            // Core Graphics uses a lower-left origin.
            func convertToCoreGraphicsUnit(point: CGPoint) -> CGPoint {
                CGPoint(x: point.x.clamp01(), y: (1 - point.y).clamp01())
            }
            gradientLayer.startPoint = convertToCoreGraphicsUnit(point: unitCenter + startVector * +startScale)
            // The endpoint should be "opposite" the start point, on the opposite edge of the view.
            gradientLayer.endPoint = convertToCoreGraphicsUnit(point: unitCenter + startVector * -startScale)

            Logger.verbose("---- gradientLayer.frame: \(gradientLayer.frame), color1: \(color1.asOWSColor), color2: \(color2.asOWSColor), ")
            Logger.verbose("---- gradientLayer.startPoint: \(gradientLayer.startPoint), gradientLayer.endPoint: \(gradientLayer.endPoint), ")
        }

        CATransaction.commit()
    }

    public override func reset() {
        super.reset()

        self.chatColor = nil
        self.backgroundColor = nil
        gradientLayer.removeFromSuperlayer()
    }
}
