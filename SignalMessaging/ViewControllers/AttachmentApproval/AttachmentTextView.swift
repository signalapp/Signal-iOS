//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
        // When creating new lines, contentOffset is animated, but because because
        // we are simultaneously resizing the text view, on pre-iOS 13 this can
        // cause the text in the textview to be "too high" in the text view.
        // Solution is to disable animation for setting content offset between
        // -textViewShouldChange... and -textViewDidChange.
        //
        // We can't unilaterally disable *all* animated scrolling because that breaks
        // manipulation of the cursor in scrollable text. Animation is required to
        // slow the text view scrolling down to human scale when the cursor reaches
        // the top or bottom edge.
        let shouldAnimate: Bool
        if #available(iOS 13, *) {
            shouldAnimate = animated
        } else {
            shouldAnimate = animated && !textIsChanging
        }
        super.setContentOffset(contentOffset, animated: shouldAnimate)
    }
}
