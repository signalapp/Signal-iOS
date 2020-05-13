//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc (OWSCircleView)
public class CircleView: UIView {

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
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

@objc (OWSPillView)
public class PillView: UIView {

    public override init(frame: CGRect) {
        super.init(frame: frame)

        // Constrain to be a pill that is at least a circle, and maybe wider.
        autoPin(toAspectRatio: 1.0, relation: .greaterThanOrEqual)

        // low priority contstraint to ensure the pill
        // is no taller than necessary
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            self.autoSetDimension(.height, toSize: 0)
        }
    }

    required init?(coder aDecoder: NSCoder) {
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
