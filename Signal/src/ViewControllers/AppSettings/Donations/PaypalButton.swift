//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

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
        adjustsImageWhenDisabled = false
        adjustsImageWhenHighlighted = false
        layer.cornerRadius = 12

        if Theme.isDarkThemeEnabled {
            backgroundColor = UIColor(rgbHex: 0xEEEEEE)
            layer.borderWidth = 0
        } else {
            backgroundColor = .white
            layer.borderWidth = 1.5
            layer.borderColor = UIColor.ows_gray25.cgColor
        }
    }

    // MARK: Actions

    @objc
    private func didTouchUpInside() {
        actionBlock()
    }
}
