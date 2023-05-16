//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol InputAccessoryViewPlaceholderDelegate: AnyObject {
    func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func inputAccessoryPlaceholderKeyboardDidPresent()
    func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func inputAccessoryPlaceholderKeyboardDidDismiss()
    func inputAccessoryPlaceholderKeyboardIsDismissingInteractively()
}

// MARK: -

/// Input accessory views always render at the full width of the window.
/// This wrapper allows resizing the accessory view to fit within its
/// presenting view.
public class InputAccessoryViewPlaceholder: UIView {

    public weak var delegate: InputAccessoryViewPlaceholderDelegate?

    /// The amount of the application frame that is overlapped
    /// by the keyboard.
    public var keyboardOverlap: CGFloat {
        // Subtract our own height as this view is not actually
        // visible, but is represented in the keyboard.

        let ownHeight = superview != nil ? desiredHeight : 0

        return max(0, visibleKeyboardHeight - ownHeight)
    }

    public weak var referenceView: UIView?

    private var visibleKeyboardHeight: CGFloat {
        guard var keyboardFrame = transitioningKeyboardFrame ?? superview?.frame else { return 0 }
        guard keyboardFrame.height > 0 else { return 0 }

        let referenceFrame: CGRect

        if let referenceView = referenceView {
            keyboardFrame = referenceView.convert(keyboardFrame, from: nil)
            referenceFrame = referenceView.frame
        } else {
            referenceFrame = CurrentAppContext().frame
        }

        // Measure how much of the keyboard is currently offscreen.
        let offScreenHeight = keyboardFrame.maxY - referenceFrame.maxY

        // The onscreen region represents the overlap.
        return max(0, keyboardFrame.height - offScreenHeight)
    }

    private var transitioningKeyboardFrame: CGRect? {
        switch keyboardState {
        case .dismissing:
            return .zero
        case .presenting(let frame):
            return frame
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
    public var desiredHeight: CGFloat {
        get {
            return heightConstraint.constant
        }
        set {
            guard newValue != desiredHeight else { return }
            heightConstraint.constant = newValue
            UIView.performWithoutAnimation {
                heightConstraintView.layoutIfNeeded()
                self.layoutIfNeeded()
                superview?.layoutIfNeeded()
            }
        }
    }

    private let heightConstraintView = UIView()

    private lazy var heightConstraint: NSLayoutConstraint = {
        addSubview(heightConstraintView)
        heightConstraintView.autoPinHeightToSuperview()
        return heightConstraintView.autoSetDimension(.height, toSize: 0)
    }()

    private enum KeyboardState: CustomStringConvertible {
        case dismissed
        case dismissing
        case presented
        case presenting(frame: CGRect)

        public var description: String {
            switch self {
            case .dismissed:
                return "dismissed"
            case .dismissing:
                return "dismissing"
            case .presented:
                return "presented"
            case .presenting:
                return "presenting"
            }
        }
    }
    private var keyboardState: KeyboardState = .dismissed

    public init() {
        super.init(frame: .zero)

        // Disable user interaction, the accessory view
        // should never actually contain any UI.
        isUserInteractionEnabled = false
        autoresizingMask = .flexibleHeight

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

    deinit {
        superviewCenterObserver?.invalidate()
    }

    public override var intrinsicContentSize: CGSize {
        return .zero
    }

    private var superviewCenterObserver: NSKeyValueObservation?

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)

        // By observing the .center property of our superview, we can
        // follow along as the keyboard moves up and down.
        superviewCenterObserver?.invalidate()
        superviewCenterObserver = newSuperview?.observe(\.center, options: [.initial, .new]) { [weak self] (_, _) in
            guard let self = self else { return }

            // Do nothing unless the keyboard is currently presented.
            // We're only checking for interactive dismissal, which
            // can only happen while presented.
            guard case .presented = self.keyboardState else { return }

            guard self.superview != nil else { return }

            // While the visible keyboard height is greater than zero,
            // and the keyboard is presented, we can safely assume
            // an interactive dismissal is in progress.
            if self.visibleKeyboardHeight > 0 {
                self.delegate?.inputAccessoryPlaceholderKeyboardIsDismissingInteractively()
            }
        }
    }

    // MARK: - Presentation / Dismissal wrangling.

    @objc
    private func keyboardWillPresent(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let beginFrame = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve) else {
                return owsFailDebug("keyboard notification missing expected userInfo properties")
        }

        // We only want to do an animated presentation if either a) the height changed or b) the view is
        // starting from off the bottom of the screen (a full presentation). This provides the best experience
        // when canceling an interactive dismissal or changing orientations.
        guard beginFrame.height != endFrame.height || beginFrame.minY == UIScreen.main.bounds.height else { return }

        keyboardState = .presenting(frame: endFrame)

        delegate?.inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    @objc
    private func keyboardDidPresent(_ notification: Notification) {
        keyboardState = .presented
        delegate?.inputAccessoryPlaceholderKeyboardDidPresent()
    }

    @objc
    private func keyboardWillDismiss(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve) else {
                return owsFailDebug("keyboard notification missing expected userInfo properties")
        }

        keyboardState = .dismissing

        delegate?.inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    @objc
    private func keyboardDidDismiss(_ notification: Notification) {
        keyboardState = .dismissed
        delegate?.inputAccessoryPlaceholderKeyboardDidDismiss()
    }
}
