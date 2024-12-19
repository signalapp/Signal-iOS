//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit

public class LinkingTextView: UITextView {

    public var shouldInteractWithURLOverride: ((URL) -> Bool)?

    /// Creates a text view with the provided action in place of opening
    /// tapped links. If there are multiple links and you want to perform
    /// a different action depending on which was tapped, use
    /// ``LinkingTextView/init(shouldInteractWithURL:)``.
    public convenience init(overrideLinkAction: @escaping () -> Void) {
        self.init { url in
            overrideLinkAction()
            return false
        }
    }

    /// Creates a text view with a closure for determining what to do with tapped links.
    public convenience init(shouldInteractWithURL: @escaping (URL) -> Bool) {
        self.init()
        self.shouldInteractWithURLOverride = shouldInteractWithURL
    }

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)

        self.disableAiWritingTools()

        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        textContainerInset = .zero
        contentInset = .zero
        self.textContainer.lineFragmentPadding = 0
        isScrollEnabled = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // required to prevent blue background selection from any situation
    override public var selectedTextRange: UITextRange? {
        get { return nil }
        set {}
    }

    // disables unwanted UIGestureRecognizer from UITextView
    // to prevent selection, magnification, etc. while still
    // allowing links to be interactable.
    // https://stackoverflow.com/a/49428307/1033581
    override public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer {
            // required for compatibility with isScrollEnabled
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        if let tapGestureRecognizer = gestureRecognizer as? UITapGestureRecognizer,
            tapGestureRecognizer.numberOfTapsRequired == 1 {
            // required for compatibility with links
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        // allowing smallDelayRecognizer for links
        // https://stackoverflow.com/questions/46143868/xcode-9-uitextview-links-no-longer-clickable
        if let longPressGestureRecognizer = gestureRecognizer as? UILongPressGestureRecognizer,
            // comparison value is used to distinguish between 0.12 (smallDelayRecognizer) and 0.5 (textSelectionForce and textLoupe)
            longPressGestureRecognizer.minimumPressDuration < 0.325 {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        // preventing selection from loupe/magnifier (_UITextSelectionForceGesture), multi tap, tap and a half, etc.
        gestureRecognizer.isEnabled = false
        return false
    }
}

extension LinkingTextView: UITextViewDelegate {

    public func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if let shouldInteractWithURLOverride {
            return shouldInteractWithURLOverride(url)
        }

        let vc = SFSafariViewController(url: url)
        CurrentAppContext().frontmostViewController()?.present(vc, animated: true, completion: nil)
        return false
    }
}
