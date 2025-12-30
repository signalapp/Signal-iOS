//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PassKit
import SignalServiceKit
import SignalUI

class ApplePayButton: UIButton {
    private let actionBlock: () -> Void
    private let applePayButton: PKPaymentButton

    init(actionBlock: @escaping () -> Void) {
        self.actionBlock = actionBlock

        applePayButton = PKPaymentButton(
            paymentButtonType: .plain,
            paymentButtonStyle: .automatic,
        )

        super.init(frame: .zero)
        applePayButton.addAction(
            UIAction { [weak self] _ in
                self?.actionBlock()
            },
            for: .primaryActionTriggered,
        )

        addSubview(applePayButton)

#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tintColor = .Signal.label
            configuration = .prominentGlass()
        }
#endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applePayButton.frame = bounds
        applePayButton.cornerRadius = if #available(iOS 26, *) {
            height / 2
        } else {
            12
        }
    }
}
