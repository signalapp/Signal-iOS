//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class OWSLayerView: UIView {
    let layoutCallback: ((UIView) -> Void)

    @objc
    public required init(frame: CGRect, layoutCallback : @escaping (UIView) -> Void) {
        self.layoutCallback = layoutCallback
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        self.layoutCallback = { _ in
        }
        super.init(coder: aDecoder)
    }

    override var bounds: CGRect {
        didSet {
            layoutCallback(self)
        }
    }

    override var frame: CGRect {
        didSet {
            layoutCallback(self)
        }
    }

    override var center: CGPoint {
        didSet {
            layoutCallback(self)
        }
    }
}
