//  Created by Michael Kirk on 12/11/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import UIKit

@IBDesignable
class AvatarImageView: UIImageView {

    override func layoutSubviews() {
        self.layer.masksToBounds = true
        self.layer.cornerRadius = self.frame.size.width / 2
    }

}
