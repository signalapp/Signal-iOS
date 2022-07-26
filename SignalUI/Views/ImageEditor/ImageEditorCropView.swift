//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit

enum CropRegion {
    // The sides of the crop region.
    case left, right, top, bottom
    // The corners of the crop region.
    case topLeft, topRight, bottomLeft, bottomRight
}

private class CropCornerView: UIView {

    let cropRegion: CropRegion

    var size: CGSize = CGSize(square: CropView.desiredCornerSize) {
        didSet {
            widthConstraint.constant = size.width
            heightConstraint.constant = size.height
        }
    }

    lazy private var widthConstraint: NSLayoutConstraint = self.widthAnchor.constraint(equalToConstant: size.width)
    lazy private var heightConstraint: NSLayoutConstraint = self.heightAnchor.constraint(equalToConstant: size.width)

    init(cropRegion: CropRegion) {
        self.cropRegion = cropRegion
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
        shapeLayer?.fillColor = UIColor.white.cgColor
        addConstraints([ widthConstraint, heightConstraint ])
    }

    @available(*, unavailable, message: "Use init(cropRegion:) instead.")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer? {
        return layer as? CAShapeLayer
    }

    override var bounds: CGRect {
        didSet {
            if bounds != oldValue {
                updatePath()
            }
        }
    }

    private func updatePath() {
        guard let shapeLayer = shapeLayer else {
            return
        }

        let cornerThickness: CGFloat = 2
        let shapeFrame = bounds.insetBy(dx: -cornerThickness, dy: -cornerThickness)
        let bezierPath = UIBezierPath()
        switch cropRegion {
        case .topLeft:
            bezierPath.addRegion(withPoints: [
                shapeFrame.origin,
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.minX, y: shapeFrame.maxY - cornerThickness)
            ])
        case .topRight:
            bezierPath.addRegion(withPoints: [
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.minY),
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY)
            ])
        case .bottomLeft:
            bezierPath.addRegion(withPoints: [
                CGPoint(x: shapeFrame.minX, y: shapeFrame.maxY),
                CGPoint(x: shapeFrame.minX, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY)
            ])
        case .bottomRight:
            bezierPath.addRegion(withPoints: [
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.maxY),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.minY + cornerThickness)
            ])
        default:
            owsFailDebug("Invalid crop region: \(cropRegion)")
        }

        shapeLayer.path = bezierPath.cgPath
    }
}

private class CropBackgroundView: UIView {

    enum Style {
        case blur
        case darkening
        case blackout
    }

    var style: Style {
        didSet {
            updateStyle()
        }
    }

    private let blurView = UIVisualEffectView()
    private let darkeningView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }()

    required init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(blurView)
        addSubview(darkeningView)
        updateStyle()
    }

    @available(*, unavailable, message: "Use init(style:)")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        darkeningView.frame = bounds
    }

    private func updateStyle() {
        switch style {
        case .blur:
            darkeningView.alpha = 0
            blurView.effect = UIBlurEffect(style: .dark)

        case .darkening:
            darkeningView.alpha = 0.5
            blurView.effect = nil

        case .blackout:
            darkeningView.alpha = 1
        }
    }

    var lastKnownMaskRect: CGRect?

    fileprivate func setMaskRect(_ maskRect: CGRect, animationDuration: TimeInterval) {
        if let lastKnownMaskRect = lastKnownMaskRect, lastKnownMaskRect == maskRect {
            return
        }

        let maskLayer: CAShapeLayer
        if let existingMaskLayer = layer.mask as? CAShapeLayer {
            maskLayer = existingMaskLayer
        } else {
            maskLayer = CAShapeLayer()
            maskLayer.fillRule = .evenOdd
            layer.mask = maskLayer
        }
        maskLayer.frame = layer.bounds

        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(maskRect)

        if animationDuration > 0 {
            let animation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.path))
            animation.duration = animationDuration
            animation.fromValue = maskLayer.path
            animation.toValue = path
            maskLayer.add(animation, forKey: "path")
        }

        maskLayer.path = path

        lastKnownMaskRect = maskRect
    }
}

class CropView: UIView {

    static let desiredCornerSize: CGFloat = 22 // adjusted for stroke width, visible size is 24
    private(set) var cornerSize = CGSize(square: CropView.desiredCornerSize)

    private lazy var backgroundView = CropBackgroundView(style: CropView.backgroundStyle(forState: state))

    private let cropFrameView: UIView = {
        let view = UIView()
        view.addBorder(with: .white)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let cropCornerViews: [CropCornerView] = [
        CropCornerView(cropRegion: .topLeft),
        CropCornerView(cropRegion: .topRight),
        CropCornerView(cropRegion: .bottomLeft),
        CropCornerView(cropRegion: .bottomRight)
    ]

    private let verticalGridLines: [UIView] = [ UIView(), UIView() ]
    private let horizontalGridLines: [UIView] = [ UIView(), UIView() ]

    enum State {
        case initial    // no crop frame visible, background set to `blackout`
        case normal     // default look: crop frame visible, grid lines hidden, background set to `blur`
        case resizing   // user is resizing: crop frame and grid lines visible, background set to `darkening`
    }
    private var state: State = .initial

    // Defines crop frame.
    let cropFrameLayoutGuide = UILayoutGuide()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        addSubview(backgroundView)

        // Crop Frame
        cropFrameLayoutGuide.identifier = "CropFrame"
        addLayoutGuide(cropFrameLayoutGuide)
        addSubview(cropFrameView)
        addConstraints([
            cropFrameView.leadingAnchor.constraint(equalTo: cropFrameLayoutGuide.leadingAnchor),
            cropFrameView.topAnchor.constraint(equalTo: cropFrameLayoutGuide.topAnchor),
            cropFrameView.trailingAnchor.constraint(equalTo: cropFrameLayoutGuide.trailingAnchor),
            cropFrameView.bottomAnchor.constraint(equalTo: cropFrameLayoutGuide.bottomAnchor)
        ])

        // Crop Frame Corners
        for cropCornerView in cropCornerViews {
            cropFrameView.addSubview(cropCornerView)

            switch cropCornerView.cropRegion {
            case .topLeft, .bottomLeft:
                cropCornerView.autoPinEdge(toSuperviewEdge: .left)
            case .topRight, .bottomRight:
                cropCornerView.autoPinEdge(toSuperviewEdge: .right)
            default:
                owsFailDebug("Invalid crop region: \(String(describing: cropCornerView.cropRegion))")
            }
            switch cropCornerView.cropRegion {
            case .topLeft, .topRight:
                cropCornerView.autoPinEdge(toSuperviewEdge: .top)
            case .bottomLeft, .bottomRight:
                cropCornerView.autoPinEdge(toSuperviewEdge: .bottom)
            default:
                owsFailDebug("Invalid crop region: \(String(describing: cropCornerView.cropRegion))")
            }
        }

        // Spacer Layout Guide that allows to space grid lines evenly
        let spacerLayoutGuide = UILayoutGuide()
        cropFrameView.addLayoutGuide(spacerLayoutGuide)
        NSLayoutConstraint(item: spacerLayoutGuide, attribute: .left, relatedBy: .equal,
                           toItem: cropFrameView, attribute: .left, multiplier: 1, constant: 0).isActive = true
        NSLayoutConstraint(item: spacerLayoutGuide, attribute: .top, relatedBy: .equal,
                           toItem: cropFrameView, attribute: .top, multiplier: 1, constant: 0).isActive = true
        NSLayoutConstraint(item: spacerLayoutGuide, attribute: .width, relatedBy: .equal,
                           toItem: cropFrameView, attribute: .width, multiplier: 1/CGFloat(verticalGridLines.count + 1), constant: 0).isActive = true
        NSLayoutConstraint(item: spacerLayoutGuide, attribute: .height, relatedBy: .equal,
                           toItem: cropFrameView, attribute: .height, multiplier: 1/CGFloat(horizontalGridLines.count + 1), constant: 0).isActive = true

        // Grid Lines
        for (index, line) in verticalGridLines.enumerated() {
            line.backgroundColor = .ows_white
            cropFrameView.addSubview(line)
            line.autoSetDimension(.width, toSize: 1)
            line.autoPinHeightToSuperview()
            NSLayoutConstraint(item: line, attribute: .centerX, relatedBy: .equal,
                               toItem: spacerLayoutGuide, attribute: .right,
                               multiplier: CGFloat(index + 1),
                               constant: 0).isActive = true
        }
        for (index, line) in horizontalGridLines.enumerated() {
            line.backgroundColor = .ows_white
            cropFrameView.addSubview(line)
            line.autoSetDimension(.height, toSize: 1)
            line.autoPinWidthToSuperview()
            NSLayoutConstraint(item: line, attribute: .centerY, relatedBy: .equal,
                               toItem: spacerLayoutGuide, attribute: .bottom,
                               multiplier: CGFloat(index + 1),
                               constant: 0).isActive = true
        }
        setState(.initial, animated: false)
    }

    @available(*, unavailable, message: "Use init(frame:)")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        // `inheritedAnimationDuration` will return a non-zero value when called from within an animation block.
        // That allows me to attach CAAnimation with the correct duration (if necessary).
        let animationDuration = UIView.inheritedAnimationDuration
        let maskRect = backgroundView.convert(cropFrameView.frame, from: self)
        backgroundView.setMaskRect(maskRect, animationDuration: animationDuration)
        updateCornerSize()
    }

    func setState(_ state: State, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let cropFrameAlpha: CGFloat = state == .initial ? 0 : 1
        let gridLinesAlpha: CGFloat = state == .resizing ? 1 : 0
        let backgroundStyle = CropView.backgroundStyle(forState: state)
        let layoutBlock = {
            self.cropFrameView.alpha = cropFrameAlpha
            self.verticalGridLines.forEach { $0.alpha = gridLinesAlpha }
            self.horizontalGridLines.forEach { $0.alpha = gridLinesAlpha }
            self.backgroundView.style = backgroundStyle
        }
        if animated {
            UIView.animate(withDuration: 0.15, animations: layoutBlock, completion: completion)
        } else {
            layoutBlock()
            completion?(true)
        }
    }

    private class func backgroundStyle(forState state: State) -> CropBackgroundView.Style {
        switch state {
        case .initial: return .blackout
        case .normal: return .blur
        case .resizing: return .darkening
        }
    }

    private func updateCornerSize() {
        guard cropFrameView.width > 0, cropFrameView.height > 0 else { return }

        self.cornerSize = CGSize(width: min(cropFrameView.width * 0.5, CropView.desiredCornerSize),
                                 height: min(cropFrameView.height * 0.5, CropView.desiredCornerSize))
        cropCornerViews.forEach { $0.size = cornerSize }
    }
}
