//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

        autoSetDimensions(to: CGSize(width: diameter, height: diameter))
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
