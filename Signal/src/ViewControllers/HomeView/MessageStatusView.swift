//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageStatusView: UIView {

    private let imageView: UIImageView

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

        super.init(frame: frame)

        self.addSubview(imageView)

        imageView.setCompressionResistanceHigh()
        imageView.setContentHuggingHigh()
        imageView.autoPinWidthToSuperview()
        imageView.autoVCenterInSuperview()
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
}
