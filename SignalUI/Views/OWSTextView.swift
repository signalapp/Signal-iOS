//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

open class OWSTextView: UITextView {

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        self.disableAiWritingTools()
        keyboardAppearance = Theme.keyboardAppearance
        dataDetectorTypes = []
    }

    public required init?(coder: NSCoder) {
        owsFail("Not implemented!")
    }
}
