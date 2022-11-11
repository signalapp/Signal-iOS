//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

@objc(OWSCircleView)
public class CircleView: UIView {

    @available(*, unavailable, message: "use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public required init() {
        super.init(frame: .zero)
    }

    @objc
    public required init(diameter: CGFloat) {
        super.init(frame: .zero)

        autoSetDimensions(to: CGSize(square: diameter))
    }

    @objc
    override public var frame: CGRect {
        didSet {
            updateRadius()
        }
    }

    @objc
    override public var bounds: CGRect {
        didSet {
            updateRadius()
        }
    }

    private func updateRadius() {
        self.layer.cornerRadius = self.bounds.size.height / 2
    }
}

@objc(OWSCircleBlurView)
public class CircleBlurView: UIVisualEffectView {

    @available(*, unavailable, message: "use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        frame = .zero
    }

    @objc
    public required init(effect: UIVisualEffect, diameter: CGFloat) {
        super.init(effect: effect)
        frame = .zero

        autoSetDimensions(to: CGSize(square: diameter))
    }

    @objc
    override public var frame: CGRect {
        didSet {
            updateRadius()
        }
    }

    @objc
    override public var bounds: CGRect {
        didSet {
            updateRadius()
        }
    }

    private func updateRadius() {
        layer.cornerRadius = bounds.size.height / 2
        clipsToBounds = true
    }
}

@objc(OWSPillView)
open class PillView: UIView {

    public override init(frame: CGRect) {
        super.init(frame: frame)

        layer.masksToBounds = true

        // Constrain to be a pill that is at least a circle, and maybe wider.
        autoPin(toAspectRatio: 1.0, relation: .greaterThanOrEqual)

        // low priority constraint to ensure the pill
        // is no taller than necessary
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            self.autoSetDimension(.height, toSize: 0)
        }
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    override public var frame: CGRect {
        didSet {
            updateRadius()
        }
    }

    @objc
    override public var bounds: CGRect {
        didSet {
            updateRadius()
        }
    }

    private func updateRadius() {
        layer.cornerRadius = bounds.size.height / 2
    }
}
