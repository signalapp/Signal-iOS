//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol CallVideoHintViewDelegate: AnyObject {
    func didTapCallVideoHintView(_ videoHintView: CallVideoHintView)
}

class CallVideoHintView: UIView {
    let label = UILabel()
    var tapGesture: UITapGestureRecognizer!
    weak var delegate: CallVideoHintViewDelegate?

    let kTailHMargin: CGFloat = 12
    let kTailWidth: CGFloat = 16
    let kTailHeight: CGFloat = 8

    init() {
        super.init(frame: .zero)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(tapGesture:)))
        addGestureRecognizer(tapGesture)

        let layerView = OWSLayerView()
        let shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.ows_signalBlue.cgColor
        layerView.layer.addSublayer(shapeLayer)
        addSubview(layerView)
        layerView.autoPinEdgesToSuperviewEdges()

        let container = UIView()
        addSubview(container)
        container.autoSetDimension(.width, toSize: ScaleFromIPhone5(250), relation: .lessThanOrEqual)
        container.layoutMargins = UIEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
        container.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 0, leading: 0, bottom: kTailHeight, trailing: 0))

        container.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.setCompressionResistanceHigh()
        label.setContentHuggingHigh()
        label.font = UIFont.ows_dynamicTypeBody
        label.textColor = .ows_white
        label.numberOfLines = 0
        label.text = NSLocalizedString("CALL_VIEW_ENABLE_VIDEO_HINT", comment: "tooltip label when remote party has enabled their video")

        layerView.layoutCallback = { view in
            let bezierPath = UIBezierPath()

            // Bubble
            let bubbleBounds = container.bounds
            bezierPath.append(UIBezierPath(roundedRect: bubbleBounds, cornerRadius: 8))

            // Tail
            var tailBottom = CGPoint(x: self.kTailHMargin + self.kTailWidth * 0.5, y: view.height())
            var tailLeft = CGPoint(x: self.kTailHMargin, y: view.height() - self.kTailHeight)
            var tailRight = CGPoint(x: self.kTailHMargin + self.kTailWidth, y: view.height() - self.kTailHeight)
            if (!CurrentAppContext().isRTL) {
                tailBottom.x = view.width() - tailBottom.x
                tailLeft.x = view.width() - tailLeft.x
                tailRight.x = view.width() - tailRight.x
            }
            bezierPath.move(to: tailBottom)
            bezierPath.addLine(to: tailLeft)
            bezierPath.addLine(to: tailRight)
            bezierPath.addLine(to: tailBottom)
            shapeLayer.path = bezierPath.cgPath
            shapeLayer.frame = view.bounds
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    func didTap(tapGesture: UITapGestureRecognizer) {
        self.delegate?.didTapCallVideoHintView(self)
    }
}
