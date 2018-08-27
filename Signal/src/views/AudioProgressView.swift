//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalServiceKit

@objc public class AudioProgressView: UIView {

    @objc public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                updateSubviews()
            }
        }
    }

    @objc public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                updateSubviews()
            }
        }
    }

    @objc public var horizontalBarColor = UIColor.black {
        didSet {
            updateContent()
        }
    }

    @objc public var progressColor = UIColor.blue {
        didSet {
            updateContent()
        }
    }

    private let horizontalBarLayer: CAShapeLayer
    private let progressLayer: CAShapeLayer

    @objc public var progress: CGFloat = 0 {
        didSet {
            if oldValue != progress {
                updateContent()
            }
        }
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public required init() {
        self.horizontalBarLayer = CAShapeLayer()
        self.progressLayer = CAShapeLayer()

        super.init(frame: CGRect.zero)

        self.layer.addSublayer(self.horizontalBarLayer)
        self.layer.addSublayer(self.progressLayer)
    }

    internal func updateSubviews() {
        AssertIsOnMainThread()

        self.horizontalBarLayer.frame = self.bounds
        self.progressLayer.frame = self.bounds

        updateContent()
    }

    internal func updateContent() {
        AssertIsOnMainThread()

        // Prevent the shape layer from animating changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let horizontalBarPath = UIBezierPath()
        let horizontalBarHeightFraction = CGFloat(0.25)
        let horizontalBarHeight = bounds.size.height * horizontalBarHeightFraction
        horizontalBarPath.append(UIBezierPath(rect: CGRect(x: 0, y: (bounds.size.height - horizontalBarHeight) * 0.5, width: bounds.size.width, height: horizontalBarHeight)))
        horizontalBarLayer.path = horizontalBarPath.cgPath
        horizontalBarLayer.fillColor = horizontalBarColor.cgColor

        let progressHeight = bounds.self.height
        let progressWidth = progressHeight * 0.15
        let progressX = (bounds.self.width - progressWidth) * max(0.0, min(1.0, progress))
        let progressBounds = CGRect(x: progressX, y: 0, width: progressWidth, height: progressHeight)
        let progressCornerRadius = progressWidth * 0.5
        let progressPath = UIBezierPath()
        progressPath.append(UIBezierPath(roundedRect: progressBounds, cornerRadius: progressCornerRadius))
        progressLayer.path = progressPath.cgPath
        progressLayer.fillColor = progressColor.cgColor

        CATransaction.commit()
    }
}
