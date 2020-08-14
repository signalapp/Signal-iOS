//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MediaUploadView: UIView {

    // MARK: -

    private let attachmentId: String
    private let radius: CGFloat
    private let shapeLayer1 = CAShapeLayer()
    private let shapeLayer2 = CAShapeLayer()

    private var isAttachmentReady: Bool = false
    private var lastProgress: CGFloat = 0

    @objc
    public required init(attachmentId: String, radius: CGFloat) {
        self.attachmentId = attachmentId
        self.radius = radius

        super.init(frame: .zero)

        layer.addSublayer(shapeLayer1)
        layer.addSublayer(shapeLayer2)

        NotificationCenter.default.addObserver(forName: .attachmentUploadProgress, object: nil, queue: nil) { [weak self] notification in
            self?.attachmentUploadNotification(notification)
        }
    }

    private func attachmentUploadNotification(_ notification: Notification) {
        guard let notificationAttachmentId = notification.userInfo?[kAttachmentUploadAttachmentIDKey] as? String else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard notificationAttachmentId == attachmentId else {
            return
        }
        guard let progress = notification.userInfo?[kAttachmentUploadProgressKey] as? NSNumber else {
            owsFailDebug("Missing progress.")
            return
        }
        lastProgress = CGFloat(progress.floatValue)
        updateLayers()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                updateLayers()
            }
        }
    }

    @objc public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                updateLayers()
            }
        }
    }

    internal func updateLayers() {
        AssertIsOnMainThread()

        shapeLayer1.frame = self.bounds
        shapeLayer2.frame = self.bounds

        guard !isAttachmentReady else {
            shapeLayer1.path = nil
            shapeLayer2.path = nil
            return
        }

        // Prevent the shape layer from animating changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let center = CGPoint(x: self.bounds.width * 0.5,
                             y: self.bounds.height * 0.5)
        let outerRadius: CGFloat = radius * 1.0
        let innerRadius: CGFloat = radius * 0.9
        let startAngle: CGFloat = CGFloat.pi * 1.5
        let endAngle: CGFloat = CGFloat.pi * (1.5 + 2 * lastProgress)

        let bezierPath1 = UIBezierPath()
        bezierPath1.addArc(withCenter: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        bezierPath1.addArc(withCenter: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: false)
        shapeLayer1.path = bezierPath1.cgPath
        shapeLayer1.fillColor = UIColor.ows_white.cgColor

        let innerCircleBounds = CGRect(x: center.x - innerRadius,
                                       y: center.y - innerRadius,
                                       width: innerRadius * 2,
                                       height: innerRadius * 2)
        let outerCircleBounds = CGRect(x: center.x - outerRadius,
                                       y: center.y - outerRadius,
                                       width: outerRadius * 2,
                                       height: outerRadius * 2)
        let bezierPath2 = UIBezierPath()
        bezierPath2.append(UIBezierPath(ovalIn: innerCircleBounds))
        bezierPath2.append(UIBezierPath(ovalIn: outerCircleBounds))
        shapeLayer2.path = bezierPath2.cgPath
        shapeLayer2.fillColor = UIColor(white: 1.0, alpha: 0.4).cgColor
        shapeLayer2.fillRule = .evenOdd

        CATransaction.commit()
    }
}
