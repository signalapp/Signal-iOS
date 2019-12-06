//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class TooltipView: UIView {

    private let wasTappedBlock: (() -> Void)?

    // MARK: Initializers

    public init(fromView: UIView,
                widthReferenceView: UIView,
                tailReferenceView: UIView,
                wasTappedBlock: (() -> Void)?) {
        self.wasTappedBlock = wasTappedBlock

        super.init(frame: .zero)

        createContents(fromView: fromView,
                       widthReferenceView: widthReferenceView,
                       tailReferenceView: tailReferenceView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let tailHeight: CGFloat = 8
    private let tailWidth: CGFloat = 16
    private let bubbleRounding: CGFloat = 8

    public func bubbleContentView() -> UIView {
        owsFailDebug("Not implemented.")
        return UIView()
    }

    public var bubbleColor: UIColor {
        owsFailDebug("Not implemented.")
        return UIColor.ows_signalBlue
    }

    public var bubbleInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
    }

    public var bubbleHSpacing: CGFloat {
        return 20
    }

    private func createContents(fromView: UIView,
                                widthReferenceView: UIView,
                                tailReferenceView: UIView) {
        backgroundColor = .clear
        isOpaque = false

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                    action: #selector(handleTap)))

        // Bubble View

        let bubbleView = OWSLayerView()
        let shapeLayer = CAShapeLayer()
        shapeLayer.shadowColor = UIColor.black.cgColor
        shapeLayer.shadowOffset = CGSize(width: 0, height: 40)
        shapeLayer.shadowRadius = 40
        shapeLayer.shadowOpacity = 0.33
        shapeLayer.fillColor = bubbleColor.cgColor
        bubbleView.layer.addSublayer(shapeLayer)
        addSubview(bubbleView)
        bubbleView.autoPinEdgesToSuperviewEdges()
        bubbleView.layoutCallback = { [weak self] view in
            guard let self = self else {
                return
            }
            let bezierPath = UIBezierPath()

            // Bubble
            var bubbleBounds = view.bounds
            bubbleBounds.size.height -= self.tailHeight
            bezierPath.append(UIBezierPath(roundedRect: bubbleBounds, cornerRadius: self.bubbleRounding))

            // Tail
            //
            // The tail should _try_ to point to the "tail reference view".
            let tailReferenceFrame = self.convert(tailReferenceView.bounds, from: tailReferenceView)
            let tailHalfWidth = self.tailWidth * 0.5
            let tailHCenterMin = self.bubbleRounding + tailHalfWidth
            let tailHCenterMax = bubbleBounds.width - tailHCenterMin
            let tailHCenter = tailReferenceFrame.center.x.clamp(tailHCenterMin, tailHCenterMax)
            let tailBottom = CGPoint(x: tailHCenter, y: view.bounds.height)
            let tailLeft = CGPoint(x: tailHCenter - tailHalfWidth, y: bubbleBounds.height)
            let tailRight = CGPoint(x: tailHCenter + tailHalfWidth, y: bubbleBounds.height)
            bezierPath.move(to: tailBottom)
            bezierPath.addLine(to: tailLeft)
            bezierPath.addLine(to: tailRight)
            bezierPath.addLine(to: tailBottom)

            shapeLayer.path = bezierPath.cgPath
            shapeLayer.frame = view.bounds
        }

        // Bubble Contents

        let bubbleContentView = self.bubbleContentView()

        addSubview(bubbleContentView)
        bubbleContentView.autoPinEdgesToSuperviewMargins()
        layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: tailHeight, right: 0)

        fromView.addSubview(self)
        autoPinEdge(.bottom, to: .top, of: tailReferenceView, withOffset: -0)
        // Insist on the tooltip fitting within the margins of the widthReferenceView.
        autoPinEdge(.left, to: .left, of: widthReferenceView, withOffset: +bubbleHSpacing, relation: .greaterThanOrEqual)
        autoPinEdge(.right, to: .right, of: widthReferenceView, withOffset: -bubbleHSpacing, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultLow) {
            // Prefer that the tooltip's tail is as far as possible.
            // It should point at the center of the "tail reference view".
            let edgeOffset = bubbleRounding + tailWidth * 0.5 - tailReferenceView.width() * 0.5
            autoPinEdge(.right, to: .right, of: tailReferenceView, withOffset: edgeOffset)
        }
    }

    public func horizontalStack(forSubviews subviews: [UIView]) -> UIView {
        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.layoutMargins = bubbleInsets
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }

    // MARK: Events

    @objc
    func handleTap(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        Logger.verbose("")
        removeFromSuperview()
        wasTappedBlock?()
    }
}
