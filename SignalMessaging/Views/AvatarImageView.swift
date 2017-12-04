//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class AvatarImageView: UIImageView {

    public init() {
        super.init(frame: CGRect.zero)
        self.configureView()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.configureView()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.configureView()
    }

    override init(image: UIImage?) {
        super.init(image: image)
        self.configureView()
    }

    func configureView() {
        self.layer.minificationFilter = kCAFilterTrilinear
        self.layer.magnificationFilter = kCAFilterTrilinear
        self.layer.borderWidth = 0.5
        self.layer.masksToBounds = true
        self.contentMode = .scaleToFill
    }

    override public func layoutSubviews() {
        self.layer.borderColor = UIColor.black.cgColor.copy(alpha: 0.15)
        self.layer.cornerRadius = self.frame.size.width / 2
    }
}
