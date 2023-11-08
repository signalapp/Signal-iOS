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
        layer.borderWidth = 0

        backgroundColor = UIColor(rgbHex: 0xF6C757)
    }

    // MARK: Actions

    @objc
    private func didTouchUpInside() {
        actionBlock()
    }
}
