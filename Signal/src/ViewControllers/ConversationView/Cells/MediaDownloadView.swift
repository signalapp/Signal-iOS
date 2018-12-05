//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MediaDownloadView: UIView {

    // MARK: - Dependencies

    private var attachmentDownloads: OWSAttachmentDownloads {
        return SSKEnvironment.shared.attachmentDownloads
    }

    // MARK: -

    private let attachmentId: String
    private let radius: CGFloat
    private let shapeLayer = CAShapeLayer()

    @objc
    public required init(attachmentId: String, radius: CGFloat) {
        self.attachmentId = attachmentId
        self.radius = radius

        super.init(frame: .zero)

        layer.addSublayer(shapeLayer)

        NotificationCenter.default.addObserver(forName: NSNotification.Name.attachmentDownloadProgress, object: nil, queue: nil) { [weak self] notification in
            guard let strongSelf = self else { return }
            guard let notificationAttachmentId = notification.userInfo?[kAttachmentDownloadAttachmentIDKey] as? String else {
                return
            }
            guard notificationAttachmentId == strongSelf.attachmentId else {
                return
            }
            strongSelf.updateLayers()
        }
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

        shapeLayer.frame = self.bounds

        guard let progress = attachmentDownloads.downloadProgress(forAttachmentId: attachmentId) else {
            Logger.warn("No progress for attachment.")
            shapeLayer.path = nil
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
        let endAngle: CGFloat = CGFloat.pi * (1.5 + 2 * CGFloat(progress.floatValue))

        let bezierPath = UIBezierPath()
        bezierPath.addArc(withCenter: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        bezierPath.addArc(withCenter: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: false)

        shapeLayer.path = bezierPath.cgPath
        let fillColor: UIColor = (Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray60)
        shapeLayer.fillColor = fillColor.cgColor

        CATransaction.commit()
    }
}
