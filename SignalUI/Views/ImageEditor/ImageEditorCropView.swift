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

private class CropCornerView: OWSLayerView {
    let cropRegion: CropRegion

    init(cropRegion: CropRegion) {
        self.cropRegion = cropRegion
        super.init()
    }

    @available(*, unavailable, message: "Use init(cropRegion:) instead.")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class CropBackgroundView: UIView {

    enum Style {
        case none
        case blur
        case darkening
    }

    var style: Style = .none {
        didSet {
            updateStyle()
        }
    }

    var maskRect: CGRect = .zero {
        didSet {
            updateMask()
        }
    }

    private var blurView: UIView?
    private var darkeningView: UIView?

    required init(style: Style) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        self.style = style
        updateStyle()
    }

    @available(*, unavailable, message: "Use init(style:)")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateStyle() {
        switch style {
        case .none:
            if let blurView = blurView {
                blurView.alpha = 0
            }
            if let darkeningView = darkeningView {
                darkeningView.alpha = 0
            }

        case .blur:
            if let darkeningView = darkeningView {
                darkeningView.alpha = 0
            }
            if blurView == nil {
                let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
                addSubview(blurView)
                blurView.autoPinEdgesToSuperviewEdges()
                self.blurView = blurView
            }
            blurView?.alpha = 1

        case .darkening:
            if let blurView = blurView {
                blurView.alpha = 0
            }
            if darkeningView == nil {
                let darkeningView = UIView()
                darkeningView.backgroundColor = .ows_blackAlpha50
                addSubview(darkeningView)
                darkeningView.autoPinEdgesToSuperviewEdges()
                self.darkeningView = darkeningView
            }
            darkeningView?.alpha = 1
        }
    }

    private func updateMask() {
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(maskRect)
        let maskLayer = CAShapeLayer()
        maskLayer.path = path
        maskLayer.fillRule = .evenOdd
        layer.mask = maskLayer
    }
}

class CropView: UIView {

    static let desiredCornerSize: CGFloat = 22 // adjusted for stroke width, visible size is 24
    private(set) var cornerSize = CGSize.zero

    private let backgroundView = CropBackgroundView(style: .darkening)

    /**
     * In coordinates of CropView.
     */
    var cropFrame: CGRect {
        get {
            cropFrameView.frame
        }
        set {
            set(cropFrame: newValue)
        }
    }
    private let cropFrameView = UIView()

    private let cropCornerViews: [CropCornerView] = [
        CropCornerView(cropRegion: .topLeft),
        CropCornerView(cropRegion: .topRight),
        CropCornerView(cropRegion: .bottomLeft),
        CropCornerView(cropRegion: .bottomRight)
    ]

    private let verticalGridLines: [UIView] = [ UIView(), UIView() ]
    private let horizontalGridLines: [UIView] = [ UIView(), UIView() ]

    private var cropViewConstraints = [NSLayoutConstraint]()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        addSubview(cropFrameView)
        set(cropFrame: bounds)

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

        setupConstraints()
    }

    @available(*, unavailable, message: "Use init(frame:)")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConstraints() {
        // Corners
        let cornerSize = CGSize(width: min(width * 0.5, CropView.desiredCornerSize),
                                height: min(height * 0.5, CropView.desiredCornerSize))
        self.cornerSize = cornerSize
        for cropCornerView in cropCornerViews {
            let cornerThickness: CGFloat = 2

            let shapeLayer = CAShapeLayer()
            cropCornerView.layer.addSublayer(shapeLayer)
            shapeLayer.fillColor = UIColor.white.cgColor
            shapeLayer.strokeColor = nil
            cropCornerView.layoutCallback = { (view) in
                let shapeFrame = view.bounds.insetBy(dx: -cornerThickness, dy: -cornerThickness)
                shapeLayer.frame = shapeFrame

                let bezierPath = UIBezierPath()

                switch cropCornerView.cropRegion {
                case .topLeft:
                    bezierPath.addRegion(withPoints: [
                        CGPoint.zero,
                        CGPoint(x: shapeFrame.width - cornerThickness, y: 0),
                        CGPoint(x: shapeFrame.width - cornerThickness, y: cornerThickness),
                        CGPoint(x: cornerThickness, y: cornerThickness),
                        CGPoint(x: cornerThickness, y: shapeFrame.height - cornerThickness),
                        CGPoint(x: 0, y: shapeFrame.height - cornerThickness)
                    ])
                case .topRight:
                    bezierPath.addRegion(withPoints: [
                        CGPoint(x: shapeFrame.width, y: 0),
                        CGPoint(x: shapeFrame.width, y: shapeFrame.height - cornerThickness),
                        CGPoint(x: shapeFrame.width - cornerThickness, y: shapeFrame.height - cornerThickness),
                        CGPoint(x: shapeFrame.width - cornerThickness, y: cornerThickness),
                        CGPoint(x: cornerThickness, y: cornerThickness),
                        CGPoint(x: cornerThickness, y: 0)
                    ])
                case .bottomLeft:
                    bezierPath.addRegion(withPoints: [
                        CGPoint(x: 0, y: shapeFrame.height),
                        CGPoint(x: 0, y: cornerThickness),
                        CGPoint(x: cornerThickness, y: cornerThickness),
                        CGPoint(x: cornerThickness, y: shapeFrame.height - cornerThickness),
                        CGPoint(x: shapeFrame.width - cornerThickness, y: shapeFrame.height - cornerThickness),
                        CGPoint(x: shapeFrame.width - cornerThickness, y: shapeFrame.height)
                    ])
                case .bottomRight:
                    bezierPath.addRegion(withPoints: [
                        CGPoint(x: shapeFrame.width, y: shapeFrame.height),
                        CGPoint(x: cornerThickness, y: shapeFrame.height),
                        CGPoint(x: cornerThickness, y: shapeFrame.height - cornerThickness),
                        CGPoint(x: shapeFrame.width - cornerThickness, y: shapeFrame.height - cornerThickness),
                        CGPoint(x: shapeFrame.width - cornerThickness, y: cornerThickness),
                        CGPoint(x: shapeFrame.width, y: cornerThickness)
                    ])
                default:
                    owsFailDebug("Invalid crop region: \(cropCornerView.cropRegion)")
                }

                shapeLayer.path = bezierPath.cgPath
            }
        }

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
        setGrid(hidden: true)

        // Border
        cropFrameView.addBorder(with: .white)
    }

    func setGrid(hidden: Bool, animated: Bool = false) {
        let layoutBlock = {
            self.verticalGridLines.forEach { $0.alpha = hidden ? 0 : 1 }
            self.horizontalGridLines.forEach { $0.alpha = hidden ? 0 : 1 }
            self.backgroundView.style = hidden ? .blur : .darkening
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: layoutBlock)
        } else {
            layoutBlock()
        }
    }

    func updateLayout(using clipView: UIView) {
        NSLayoutConstraint.deactivate(cropViewConstraints)
        cropViewConstraints.removeAll()

        cornerSize = CGSize(width: min(clipView.width * 0.5, CropView.desiredCornerSize),
                            height: min(clipView.height * 0.5, CropView.desiredCornerSize))
        for cropCornerView in cropCornerViews {
            cropViewConstraints.append(contentsOf: cropCornerView.autoSetDimensions(to: cornerSize))
        }
    }

    private func set(cropFrame: CGRect) {
        cropFrameView.frame = cropFrame
        backgroundView.maskRect = backgroundView.convert(cropFrameView.frame, from: self)
    }
}
