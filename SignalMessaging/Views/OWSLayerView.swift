//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
open class OWSLayerView: UIView {
    @objc
    public var shouldAnimate = true

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

    public static func circleView(size: CGFloat? = nil) -> OWSLayerView {
        let result = OWSLayerView(frame: .zero) { view in
            view.layer.cornerRadius = min(view.width, view.height) * 0.5
        }
        if let size = size {
            result.autoSetDimensions(to: CGSize.square(size))
        }
        return result
    }

    // Circle and pills are the same.
    public static func pillView(size: CGFloat? = nil) -> OWSLayerView {
        circleView(size: size)
    }

    public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                layoutCallback(self)
            }
        }
    }

    public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                layoutCallback(self)
            }
        }
    }

    public override var center: CGPoint {
        didSet {
            if oldValue != center {
                layoutCallback(self)
            }
        }
    }

    public func updateContent() {
        if shouldAnimate {
            layoutCallback(self)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutCallback(self)
            CATransaction.commit()
        }
    }
}
