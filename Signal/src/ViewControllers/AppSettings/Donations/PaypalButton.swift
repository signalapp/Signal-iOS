//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class PaypalButton: UIButton {
    private let actionBlock: () -> Void

    init(actionBlock: @escaping () -> Void) {
        self.actionBlock = actionBlock

        super.init(frame: .zero)

        addTarget(self, action: #selector(didTouchUpInside), for: .touchUpInside)

        configureStyling()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not implemented.")
    }

    // MARK: Styling

    private func configureStyling() {
        setImage(UIImage(named: "paypal-logo"), for: .normal)
        ows_adjustsImageWhenDisabled = false
        ows_adjustsImageWhenHighlighted = false
        if #available(iOS 26.0, *), BuildFlags.iOS26SDKIsAvailable {
#if compiler(>=6.2)
            configuration = .prominentGlass()
            tintColor = UIColor(rgbHex: 0xF6C757)
#endif
        } else {
            layer.cornerRadius = 12
            backgroundColor = UIColor(rgbHex: 0xF6C757)
        }
    }

    // MARK: Actions

    @objc
    private func didTouchUpInside() {
        actionBlock()
    }
}
