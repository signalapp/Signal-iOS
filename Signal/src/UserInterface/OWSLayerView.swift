//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class OWSLayerView: UIView {
    let layoutCallback : (() -> Void)

    @objc
    public required init(frame: CGRect, layoutCallback : @escaping () -> Void) {
        self.layoutCallback = layoutCallback
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        self.layoutCallback = {
        }
        super.init(coder: aDecoder)
    }

    override var bounds: CGRect {
        didSet {
            layoutCallback()
        }
    }

    override var frame: CGRect {
        didSet {
            layoutCallback()
        }
    }

    override var center: CGPoint {
        didSet {
            layoutCallback()
        }
    }
}
