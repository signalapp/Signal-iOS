//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
open class OWSTextField: UITextField {
    public override init(frame: CGRect) {
        super.init(frame: frame)
        applyTheme()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyTheme()
    }

    private func applyTheme() {
        keyboardAppearance = Theme.keyboardAppearance
    }
}
