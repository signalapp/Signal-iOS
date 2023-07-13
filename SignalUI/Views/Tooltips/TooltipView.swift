//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

open class TooltipView: UIView {
    public enum TailDirection {
        case up
        case down
    }

    private let tailHeight: CGFloat = 8
    private let tailWidth: CGFloat = 16

    /// An invisible view that we use to compute the outline of this view.
    ///
    /// We use the computed outline to mask our content and draw our shadow.
    private lazy var outlineView: OWSLayerView = {
        let outlineView = OWSLayerView()

        outlineView.layoutCallback = { [weak self] view in
            guard
                let self,
                let tailReferenceView = self.tailReferenceView
            else {
                return
            }

            let outlinePath = self.buildOutlinePath(
                bounds: view.bounds,
                tailReferenceView: tailReferenceView
            )

            let maskingLayer = CAShapeLayer()
            maskingLayer.path = outlinePath
            self.contentView.layer.mask = maskingLayer

            self.layer.shadowPath = outlinePath
        }

        return outlineView
    }()

    /// A wrapper for our contents.
    ///
    /// Important that our content is isolated into its own subview, so we can
    /// mask that subview without masking ourselves and thereby clipping our
    /// shadow.
    private lazy var contentView: UIView = {
        let view = UIView()

        view.backgroundColor = bubbleColor

        return view
    }()

    /// A view that this view's "tail" should point towards.
    private weak var tailReferenceView: UIView?

    private let wasTappedBlock: (() -> Void)?

    public init(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView,
        wasTappedBlock: (() -> Void)?
    ) {
        self.tailReferenceView = tailReferenceView
        self.wasTappedBlock = wasTappedBlock

        super.init(frame: .zero)

        setupContents(
            fromView: fromView,
            widthReferenceView: widthReferenceView,
            tailReferenceView: tailReferenceView
        )
    }

    required public init?(coder aDecoder: NSCoder) { owsFail("Not implemented!") }

    // MARK: - Overrides

    open func bubbleContentView() -> UIView {
        owsFail("Implemented by subclasses!")
    }

    open var bubbleColor: UIColor {
        owsFail("Implemented by subclasses!")
    }

    open var bubbleBlur: Bool {
        false
    }

    open var bubbleRounding: CGFloat {
        8
    }

    open var bubbleInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
    }

    open var bubbleHSpacing: CGFloat {
        20
    }

    open var stretchesBubbleHorizontally: Bool {
        false
    }

    open var tailDirection: TailDirection {
        .down
    }

    open var dismissOnTap: Bool {
        true
    }

    // MARK: - Contents

    private func setupContents(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView
    ) {
        layoutMargins = .zero

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 16
        layer.shadowOpacity = 0.2

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap)
        ))

        setupRelationshipWithSuperview(
            superview: fromView,
            tailReferenceView: tailReferenceView,
            widthReferenceView: widthReferenceView
        )
        setupContentView()
    }

    private func setupRelationshipWithSuperview(
        superview: UIView,
        tailReferenceView: UIView,
        widthReferenceView: UIView
    ) {
        superview.addSubview(self)

        switch tailDirection {
        case .up:
            autoPinEdge(.top, to: .bottom, of: tailReferenceView, withOffset: -0)
        case .down:
            autoPinEdge(.bottom, to: .top, of: tailReferenceView, withOffset: -0)
        }

        // Insist on the tooltip fitting within the margins of the widthReferenceView.
        if stretchesBubbleHorizontally {
            autoPinEdge(.left, to: .left, of: widthReferenceView, withOffset: +bubbleHSpacing, relation: .equal)
            autoPinEdge(.right, to: .right, of: widthReferenceView, withOffset: -bubbleHSpacing, relation: .equal)
        } else {
            autoPinEdge(.left, to: .left, of: widthReferenceView, withOffset: +bubbleHSpacing, relation: .greaterThanOrEqual)
            autoPinEdge(.right, to: .right, of: widthReferenceView, withOffset: -bubbleHSpacing, relation: .lessThanOrEqual)
        }

        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultLow) {
            // Prefer that the tooltip's tail is as far as possible.
            // It should point at the center of the "tail reference view".
            let edgeOffset = bubbleRounding + tailWidth * 0.5 - tailReferenceView.width * 0.5
            autoPinEdge(.right, to: .right, of: tailReferenceView, withOffset: edgeOffset)
        }
    }

    private func setupContentView() {
        addSubview(outlineView)
        addSubview(contentView)
        outlineView.autoPinEdgesToSuperviewEdges()
        contentView.autoPinEdgesToSuperviewEdges()

        if bubbleBlur {
            let blurEffect = UIBlurEffect(style: .regular)
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            let vibrancyEffectView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: blurEffect, style: .label))

            contentView.addSubview(blurEffectView)
            contentView.addSubview(vibrancyEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
            vibrancyEffectView.autoPinEdgesToSuperviewEdges()
        }

        let bubbleContentView = self.bubbleContentView()

        let contentEdgeInsets: UIEdgeInsets = {
            switch tailDirection {
            case .up:
                return UIEdgeInsets(top: tailHeight, left: 0, bottom: 0, right: 0)
            case .down:
                return UIEdgeInsets(top: 0, left: 0, bottom: tailHeight, right: 0)
            }
        }()

        contentView.addSubview(bubbleContentView)
        bubbleContentView.autoPinEdgesToSuperviewEdges(with: contentEdgeInsets)
    }

    // MARK: - Outline

    /// Build a path representing the outline of this view; namely, a bubble
    /// with a cute lil' tail pointing at the given reference view, with the
    /// given bounds.
    private func buildOutlinePath(
        bounds originalBubbleBounds: CGRect,
        tailReferenceView: UIView
    ) -> CGPath {
        let bezierPath = UIBezierPath()

        // Bubble

        var bubbleBounds = originalBubbleBounds

        bubbleBounds.size.height -= tailHeight
        if tailDirection == .up {
            bubbleBounds.origin.y += tailHeight
        }

        bezierPath.append(UIBezierPath(
            roundedRect: bubbleBounds,
            cornerRadius: bubbleRounding
        ))

        // Tail, which tries to point to the tail reference view.

        let tailReferenceFrame = self.convert(tailReferenceView.bounds, from: tailReferenceView)
        let tailHalfWidth = tailWidth * 0.5
        let tailHCenterMin = bubbleRounding + tailHalfWidth
        let tailHCenterMax = bubbleBounds.width - tailHCenterMin
        let tailHCenter = tailReferenceFrame.center.x.clamp(tailHCenterMin, tailHCenterMax)

        let tailPoint: CGPoint
        let tailLeft: CGPoint
        let tailRight: CGPoint

        switch tailDirection {
        case .down:
            tailPoint = CGPoint(x: tailHCenter, y: originalBubbleBounds.height)
            tailLeft = CGPoint(x: tailHCenter - tailHalfWidth, y: bubbleBounds.height)
            tailRight = CGPoint(x: tailHCenter + tailHalfWidth, y: bubbleBounds.height)
        case .up:
            tailPoint = CGPoint(x: tailHCenter, y: 0)
            tailLeft = CGPoint(x: tailHCenter - tailHalfWidth, y: tailHeight)
            tailRight = CGPoint(x: tailHCenter + tailHalfWidth, y: tailHeight)
        }

        bezierPath.move(to: tailPoint)
        bezierPath.addLine(to: tailLeft)
        bezierPath.addLine(to: tailRight)
        bezierPath.addLine(to: tailPoint)

        return bezierPath.cgPath
    }

    // MARK: - Events

    @objc
    private func handleTap(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else { return }
        if dismissOnTap { removeFromSuperview() }
        wasTappedBlock?()
    }
}

public extension TooltipView {
    func horizontalStack(forSubviews subviews: [UIView]) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.layoutMargins = bubbleInsets
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }
}
