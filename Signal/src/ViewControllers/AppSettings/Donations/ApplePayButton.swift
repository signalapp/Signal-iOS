//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit

class ApplePayButton: PKPaymentButton {
    private let actionBlock: () -> Void

    init(actionBlock: @escaping () -> Void) {
        self.actionBlock = actionBlock

        super.init(paymentButtonType: .donate,
                   paymentButtonStyle: Theme.isDarkThemeEnabled ? .white : .black)
        cornerRadius = 12
        addTarget(self, action: #selector(self.didTouchUpInside), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTouchUpInside() {
        actionBlock()
    }
}
