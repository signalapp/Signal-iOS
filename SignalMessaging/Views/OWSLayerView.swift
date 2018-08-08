//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OWSLayerView: UIView {
    let layoutCallback: ((UIView) -> Void)

    @objc
    public required init(frame: CGRect, layoutCallback : @escaping (UIView) -> Void) {
        self.layoutCallback = layoutCallback
        super.init(frame: frame)
    }

    public required init?(coder aDecoder: NSCoder) {
        self.layoutCallback = { _ in
        }
        super.init(coder: aDecoder)
    }

    public override var bounds: CGRect {
        didSet {
            layoutCallback(self)
        }
    }

    public override var frame: CGRect {
        didSet {
            layoutCallback(self)
        }
    }

    public override var center: CGPoint {
        didSet {
            layoutCallback(self)
        }
    }
}
