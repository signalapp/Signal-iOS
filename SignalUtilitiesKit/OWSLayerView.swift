//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OWSLayerView: UIView {
    @objc
    public var layoutCallback: ((UIView) -> Void)

    @objc
    public init() {
        self.layoutCallback = { (_) in
        }
        super.init(frame: .zero)
    }

    @objc
    public init(frame: CGRect, layoutCallback : @escaping (UIView) -> Void) {
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
