//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageStatusView: UIView {

    private let imageView: UIImageView
    private let lastBaselineView: UIView

    // MessageStatusView is aligned 1pt below it's baseline.
    private let kBaselineOverhang: CGFloat = 1

    @objc
    public var image: UIImage? {
        get {
            return imageView.image
        }
        set {
            imageView.image = newValue
        }
    }

    public override init(frame: CGRect) {
        self.imageView = UIImageView()
        self.lastBaselineView = UIView()

        super.init(frame: frame)

        self.addSubview(imageView)
        self.addSubview(lastBaselineView)

        imageView.setCompressionResistanceHigh()
        imageView.setContentHuggingHigh()
        imageView.autoPinEdgesToSuperviewEdges()

        lastBaselineView.autoSetDimension(.height, toSize: 1)
        lastBaselineView.autoPinEdge(toSuperviewEdge: .left)
        lastBaselineView.autoPinEdge(toSuperviewEdge: .right)
        lastBaselineView.autoPinEdge(toSuperviewEdge: .bottom, withInset: kBaselineOverhang)
    }

    public override var forLastBaselineLayout: UIView {
        return self.lastBaselineView
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
}
