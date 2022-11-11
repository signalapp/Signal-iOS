//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class OWSLayerView: UIView {
    let layoutCallback: ((UIView) -> Void)

    @objc
    public required init(frame: CGRect, layoutCallback: @escaping (UIView) -> Void) {
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
            updateLayer()
        }
    }

    override var frame: CGRect {
        didSet {
            updateLayer()
        }
    }

    override var center: CGPoint {
        didSet {
            updateLayer()
        }
    }

    private func updateLayer() {
        // Prevent the shape layer from animating changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layoutCallback(self)

        CATransaction.commit()
    }
}
