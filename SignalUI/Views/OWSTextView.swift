//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class OWSTextView: UITextView {

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        applyTheme()
        dataDetectorTypes = []
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        applyTheme()
        dataDetectorTypes = []
    }

    private func applyTheme() {
        keyboardAppearance = Theme.keyboardAppearance
    }
}
