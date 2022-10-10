// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

extension UIView {

    convenience init(wrapping view: UIView, withInsets insets: UIEdgeInsets, shouldAdaptForIPadWithWidth width: CGFloat? = nil) {
        self.init()
        addSubview(view)
        if UIDevice.current.isIPad, let width = width {
            view.set(.width, to: width)
            view.center(in: self)
        } else {
            view.pin(.leading, to: .leading, of: self, withInset: insets.left)
            self.pin(.trailing, to: .trailing, of: view, withInset: insets.right)
        }
        view.pin(.top, to: .top, of: self, withInset: insets.top)
        self.pin(.bottom, to: .bottom, of: view, withInset: insets.bottom)
    }
}
