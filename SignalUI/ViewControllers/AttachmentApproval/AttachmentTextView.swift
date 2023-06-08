//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

class AttachmentTextView: MentionTextView {

    private var textIsChanging = false

    override func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        textIsChanging = true
        return super.textView(self, shouldChangeTextIn: range, replacementText: text)
    }

    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        textIsChanging = false
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: animated)
    }
}
