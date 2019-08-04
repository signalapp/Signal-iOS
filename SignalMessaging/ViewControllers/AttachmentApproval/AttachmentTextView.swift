//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

class AttachmentTextView: UITextView {
    // When creating new lines, contentOffset is animated, but because
    // we are simultaneously resizing the text view, this can cause the
    // text in the textview to be "too high" in the text view.
    // Solution is to disable animation for setting content offset.
    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: false)
    }
}
