//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

// This view can be used to safely fill a region of a table
// or collection view cell.  These cells change the background
// colors of their subviews when selected.  This can inadvertently
// change the color of filled subviews.  This view will
// reject a new background once its background has been set.
@objc class NeverClearView: UIView {
    override var backgroundColor: UIColor? {
        didSet {
            if backgroundColor?.cgColor.alpha == 0 {
                backgroundColor = oldValue
            }
        }
    }
}
