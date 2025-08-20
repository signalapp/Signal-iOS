//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PassKit
import SignalUI
import SignalServiceKit

class ApplePayButton: UIButton {
    private let actionBlock: () -> Void
    private let applePayButton: PKPaymentButton

    init(actionBlock: @escaping () -> Void) {
        self.actionBlock = actionBlock

        applePayButton = PKPaymentButton(
            paymentButtonType: .plain,
            paymentButtonStyle: Theme.isDarkThemeEnabled ? .white : .black
        )

        super.init(frame: .zero)
        applePayButton.addTarget(self, action: #selector(self.didTouchUpInside), for: .touchUpInside)

        self.addSubview(applePayButton)
        applePayButton.autoPinEdgesToSuperviewEdges()

#if compiler(>=6.2)
        if #available(iOS 26.0, *){
            tintColor = Theme.isDarkThemeEnabled ? .white : .black
            configuration = .prominentGlass()
        }
#endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTouchUpInside() {
        actionBlock()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applePayButton.cornerRadius = if #available(iOS 26, *), FeatureFlags.iOS26SDKIsAvailable {
            height / 2
        } else {
            12
        }
    }
}
