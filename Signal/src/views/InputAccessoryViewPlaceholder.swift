//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol InputAccessoryViewPlaceholderDelegate: class {
    func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval)
    func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval)
    func inputAccessoryPlaceholderKeyboardIsDismissingInteractively()
}

/// Input accessory views always render at the full width of the window.
/// This wrapper allows resizing the accessory view to fit within its
/// presenting view.
@objc
class InputAccessoryViewPlaceholder: UIView {
    @objc weak var delegate: InputAccessoryViewPlaceholderDelegate?

    /// The amount of the application frame that is overlapped
    /// by the keyboard.
    @objc
    var keyboardOverlap: CGFloat {
        // Subtract our own height as this view is not actually
        // visible, but is represnted in the keyboard.

        let ownHeight = superview != nil ? frame.height : 0

        return max(0, visibleKeyboardHeight - ownHeight)
    }

    private var visibleKeyboardHeight: CGFloat {
        if let transitioningKeyboardHeight = transitioningKeyboardHeight {
            return transitioningKeyboardHeight
        }

        guard let keyboardFrame = superview?.frame else { return 0 }

        let appFrame = CurrentAppContext().frame

        // Measure how much of the keyboard is currently offscreen.
        let offScreenHeight = keyboardFrame.maxY - appFrame.maxY

        // The onscreen region represents the overlap.
        return max(0, keyboardFrame.height - offScreenHeight)
    }

    private var transitioningKeyboardHeight: CGFloat? {
        switch keyboardState {
        case .dismissing:
            return 0
        case .presenting(let height):
            return height
        default:
            return nil
        }
    }

    /// The height that the accessory view should take up. This is
    /// automatically subtracted from the keyboard overlap and is
    /// intended to represent the extent to which you want the
    /// accessory view to overlap the presenting view, primarily
    /// for the purpose of defining the start point for interactive
    /// dismissals.
    @objc var desiredHeight: CGFloat {
        set {
            frame.size.height = newValue
        }
        get {
            return frame.size.height
        }
    }

    private enum KeyboardState {
        case dismissed
        case dismissing
        case presented
        case presenting(height: CGFloat)
    }
    private var keyboardState: KeyboardState = .dismissed

    init() {
        super.init(frame: .zero)

        // Disable user interaction, the accessory view
        // should never actually contain any UI.
        isUserInteractionEnabled = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillDismiss),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidDismiss),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillPresent),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidPresent),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)

        // By observing the "center" property of our superview, we can
        // follow along as the keyboard moves up and down.
        superview?.removeObserver(self, forKeyPath: "center")
        newSuperview?.addObserver(self, forKeyPath: "center", options: [.initial, .new], context: nil)
    }

    deinit {
        superview?.removeObserver(self, forKeyPath: "center")
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        // Do nothing unless the keyboard is currently presented.
        // We're only checking for interactive dismissal, which
        // can only happen while presented.
        guard case .presented = keyboardState else { return }

        guard superview != nil else { return }

        // While the visible keyboard height is greater than zero,
        // and the keyboard is presented, we can safely assume
        // an interactive dismissal is in progress.
        if visibleKeyboardHeight > 0 {
            delegate?.inputAccessoryPlaceholderKeyboardIsDismissingInteractively()
        }
    }

    // MARK: - Presentation / Dismissal wrangling.

    @objc
    private func keyboardWillPresent(_ notification: Notification) {
        // We could theoretically get the animation curve from the userInfo as well,
        // but iOS 12+ uses a private value of 7 that is not associated with any
        // public curves. We could technically translate this to an animation
        // option without knowing the curve, but the default curve looks fine.
        guard let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }

        keyboardState = .presenting(height: endFrame.height)

        delegate?.inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: animationDuration)
    }

    @objc
    private func keyboardDidPresent(_ notification: Notification) {
        keyboardState = .presented
    }

    @objc
    private func keyboardWillDismiss(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }

        keyboardState = .dismissing

        delegate?.inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: animationDuration)
    }

    @objc
    private func keyboardDidDismiss(_ notification: Notification) {
        keyboardState = .dismissed
    }
}
