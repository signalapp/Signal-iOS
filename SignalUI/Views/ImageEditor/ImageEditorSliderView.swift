//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

class ImageEditorSlider: UISlider {

    private let backgroundView = BackgroundView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        semanticContentAttribute = .forceLeftToRight
        maximumTrackTintColor = .clear
        minimumTrackTintColor = .clear

        addSubview(backgroundView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let backgroundWidth: CGFloat = 16
        let backgroundViewFrame = bounds.insetBy(dx: 6, dy: 0.5*(bounds.height - backgroundWidth))
        backgroundView.frame = backgroundViewFrame.offsetBy(dx: 0, dy: -CGHairlineWidth())
        sendSubviewToBack(backgroundView)
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        // Increase size to make slider more accessible because it is aligned vertically along a screen edge.
        size.height *= 2
        size.width = 180
        return size
    }

    private class BackgroundView: UIView {

        override class var layerClass: AnyClass {
            return CAShapeLayer.self
        }

        private var shapeLayer: CAShapeLayer? {
            return layer as? CAShapeLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            isUserInteractionEnabled = false
            shapeLayer?.fillColor = UIColor.ows_whiteAlpha60.cgColor
        }

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

        private func updatePath() {
            guard let shapeLayer = shapeLayer else {
                return
            }

            let endWidth = (bounds.height / 4).rounded()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: bounds.minX, y: bounds.center.y - endWidth / 2))
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY))
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
            path.addLine(to: CGPoint(x: bounds.minX, y: bounds.center.y + endWidth / 2))
            path.close()
            shapeLayer.path = path.cgPath
        }
    }

}
