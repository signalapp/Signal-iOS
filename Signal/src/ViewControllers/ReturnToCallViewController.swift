//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

@objc
public protocol CallViewControllerWindowReference: AnyObject {
    var localVideoViewReference: UIView { get }
    var remoteVideoViewReference: UIView { get }
    var remoteVideoAddress: SignalServiceAddress { get }
    var view: UIView! { get }

    func returnFromPip(pipWindow: UIWindow)
}

// MARK: -

@objc
public class ReturnToCallViewController: UIViewController {

    @objc
    public static var pipSize: CGSize {
        let nineBySixteen = CGSize(width: 90, height: 160)
        let fourByThree = CGSize(width: 272, height: 204)
        let threeByFour = CGSize(width: 204, height: 272)

        if UIDevice.current.isIPad && UIDevice.current.isFullScreen {
            if CurrentAppContext().frame.size.width > CurrentAppContext().frame.size.height {
                return fourByThree
            } else {
                return threeByFour
            }
        } else {
            return nineBySixteen
        }
    }

    private weak var callViewController: CallViewControllerWindowReference?

    @objc
    public func displayForCallViewController(_ callViewController: CallViewControllerWindowReference) {
        guard callViewController !== self.callViewController else { return }

        guard let callViewSnapshot = callViewController.view.snapshotView(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot call view")
        }

        self.callViewController = callViewController

        view.addSubview(callViewController.remoteVideoViewReference)
        callViewController.remoteVideoViewReference.autoPinEdgesToSuperviewEdges()

        view.addSubview(callViewController.localVideoViewReference)
        callViewController.localVideoViewReference.layer.cornerRadius = 6
        updateLocalVideoFrame()

        let profileImage = databaseStorage.read { transaction -> UIImage? in
            avatarView.update(transaction) { config in
                config.dataSource = .address(callViewController.remoteVideoAddress)
            }
            return self.profileManagerImpl.profileAvatar(
                for: callViewController.remoteVideoAddress,
                downloadIfMissing: true,
                authedAccount: .implicit(),
                transaction: transaction
            )
        }

        backgroundAvatarView.image = profileImage

        animatePipPresentation(snapshot: callViewSnapshot)
    }

    @objc
    public func resignCall() {
        callViewController?.localVideoViewReference.removeFromSuperview()
        callViewController?.remoteVideoViewReference.removeFromSuperview()
        callViewController = nil
    }

    private lazy var avatarView = ConversationAvatarView(
        sizeClass: .customDiameter(60),
        localUserDisplayMode: .asUser,
        badged: false)
    private lazy var backgroundAvatarView = UIImageView()
    private lazy var blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))

    /// Tracks the frame of the keyboard if it is showing and docked (attached to the bottom of the screen).
    ///
    /// `nil` if the keyboard is hidden, undocked, or floating (the latter two only apply to iOS).
    /// Used to restrict `pipBoundingRect` to exclude the keyboard.
    private var dockedKeyboardFrame: CGRect?
    /// The frame of the PiP window before the user brings up the keyboard.
    ///
    /// Captured at the moment the user brings up the keyboard, and used to set the position of the PiP window while
    /// the keyboard is up (by clamping it to the new `pipBoundingRect`) as well as resetting the position when the
    /// keyboard is dismissed.
    ///
    /// `nil` if the keyboard is hidden, undocked, or floating, as well as when the user manually adjusts the PiP
    /// while the keyboard is docked (because then we no longer have anything to reset to).
    private var frameBeforeAdjustingForKeyboard: CGRect?

    override public func loadView() {
        view = UIView()

        view.backgroundColor = .black
        view.clipsToBounds = true
        view.layer.cornerRadius = 8

        backgroundAvatarView.contentMode = .scaleAspectFill
        view.addSubview(backgroundAvatarView)
        backgroundAvatarView.autoPinEdgesToSuperviewEdges()

        view.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        view.addSubview(avatarView)
        avatarView.autoCenterInSuperview()

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(keyboardFrameWillChange),
                                       name: UIWindow.keyboardWillChangeFrameNotification,
                                       object: nil)
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updatePipLayout()
        }, completion: nil)
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updatePipLayout()
    }

    // MARK: -

    private func updateLocalVideoFrame() {
        let localVideoSize = CGSizeScale(Self.pipSize, 0.3)
        callViewController?.localVideoViewReference.frame = CGRect(
            origin: CGPoint(
                x: Self.pipSize.width - 6 - localVideoSize.width,
                y: Self.pipSize.height - 6 - localVideoSize.height
            ),
            size: localVideoSize
        )
    }

    private var isAnimating = false
    private func animatePipPresentation(snapshot: UIView) {
        guard let window = view.window else { return owsFailDebug("missing window") }

        isAnimating = true

        let previousOrigin = window.frame.origin
        window.frame = OWSWindowManager.shared.rootWindow.bounds

        view.addSubview(snapshot)
        snapshot.autoPinEdgesToSuperviewEdges()

        window.layoutIfNeeded()

        UIView.animate(withDuration: 0.2, animations: {
            snapshot.alpha = 0
            window.frame = CGRect(
                origin: previousOrigin,
                size: Self.pipSize
            ).pinnedToVerticalEdge(of: self.pipBoundingRect)
            window.layoutIfNeeded()
        }) { _ in
            snapshot.removeFromSuperview()
            self.isAnimating = false
        }
    }

    /// The frame that the PiP window must be contained within, in screen coordinates.
    ///
    /// Essentially "a rect inset from the main window safe areas".
    private var pipBoundingRect: CGRect {
        let padding: CGFloat = 4
        // Don't let the PiP window overlap the chat list tab bar or the message input box in a conversation.
        // This is a hardcoded estimate that doesn't adjust with dynamic type because
        // - the height of the tab bar and the height of the message input box could change differently, and
        // - trying to track either would require exposing that information in a way this controller could get at it;
        // - trying to account for all that as well as for the user changing their preferences while the app is running
        //   would be hard, and
        // - this is just a nicety; nothing bad actually happens if the PiP window overlaps those views.
        let bottomBarEstimatedHeight: CGFloat = 56
        let safeAreaInsets = OWSWindowManager.shared.rootWindow.safeAreaInsets

        var rect = CurrentAppContext().frame
        rect = rect.inset(by: safeAreaInsets)
        rect.size.height -= bottomBarEstimatedHeight
        if let dockedKeyboardFrame = dockedKeyboardFrame, rect.maxY > dockedKeyboardFrame.minY {
            rect.size.height -= rect.maxY - dockedKeyboardFrame.minY
        }
        rect = rect.inset(by: UIEdgeInsets(margin: padding))

        return rect
    }

    /// Animates the PiP window to its new position.
    ///
    /// This gets the position of `frameBeforeAdjustingForKeyboard`, falling back to the current frame, and pins it to
    /// one of the vertical edges of `pipBoundingRect` (bringing the resulting frame fully within the bounding rect and
    /// adjusting it to the nearest vertical edge).
    ///
    /// If `animationDuration` and `animationCurve` are nil, a default animation is used.
    private func updatePipLayout(animationDuration: CGFloat? = nil,
                                 animationCurve: UIView.AnimationCurve? = nil) {
        guard !isAnimating else { return }
        guard let window = view.window else { return owsFailDebug("missing window") }
        let origin = frameBeforeAdjustingForKeyboard?.origin ?? window.frame.origin
        let newFrame = CGRect(
            origin: origin,
            size: Self.pipSize
        ).pinnedToVerticalEdge(of: pipBoundingRect)

        let animationOptions: UIView.AnimationOptions
        switch animationCurve ?? .easeInOut {
        case .easeInOut:
            animationOptions = .curveEaseInOut
        case .easeIn:
            animationOptions = .curveEaseIn
        case .easeOut:
            animationOptions = .curveEaseOut
        case .linear:
            animationOptions = .curveLinear
        @unknown default:
            animationOptions = .curveEaseInOut
        }
        UIView.animate(withDuration: animationDuration ?? 0.25, delay: 0, options: animationOptions) {
            self.updateLocalVideoFrame()
            window.frame = newFrame
        }
    }

    @objc
    private func handlePan(sender: UIPanGestureRecognizer) {
        guard let window = view.window else { return owsFailDebug("missing window") }

        // Don't try to reset to the old frame when the keyboard is dismissed.
        frameBeforeAdjustingForKeyboard = nil

        switch sender.state {
        case .began, .changed:
            let translation = sender.translation(in: window)
            sender.setTranslation(.zero, in: window)

            window.frame.origin.y += translation.y
            window.frame.origin.x += translation.x
        case .ended, .cancelled, .failed:
            window.animateDecelerationToVerticalEdge(
                withDuration: 0.35,
                velocity: sender.velocity(in: window),
                boundingRect: pipBoundingRect
            )
        default:
            break
        }
    }

    @objc
    private func handleTap(sender: UITapGestureRecognizer) {
        OWSWindowManager.shared.returnToCallView()
    }

    @objc
    private func keyboardFrameWillChange(_ notification: Notification) {
        guard let window = view.window else { return }

        guard
            let userInfo = notification.userInfo,
            let startFrame = userInfo[UIWindow.keyboardFrameBeginUserInfoKey] as? CGRect,
            let endFrame = userInfo[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            owsFailDebug("bad notification")
            return
        }

        // On an iPhone the keyboard only has two positions: showing and hidden.
        // But iPads have many more:
        // - hidden
        // - showing
        // - shortcut bar only (for hardware keyboards)
        // - floating (on newer iPads)
        // - undocked (on iPads with home buttons)
        // - undocked and split (on iPads with home buttons)
        // When changing this method, please be sure to check all iPad state transitions (on both old and new iPads),
        // as well as dragging an undocked or floating keyboard around (which should do nothing).
        // You should also check phones with and without home buttons.

        guard dockedKeyboardFrame != endFrame else {
            // The older iPad "dock" action transitions to the end frame twice;
            // ignore the second one so we don't get messed up.
            return
        }

        let animationDuration = userInfo[UIWindow.keyboardAnimationDurationUserInfoKey] as? CGFloat
        let rawAnimationCurve = userInfo[UIWindow.keyboardAnimationDurationUserInfoKey] as? Int
        let animationCurve = rawAnimationCurve.flatMap { UIView.AnimationCurve(rawValue: $0) }

        let fullFrame = CurrentAppContext().frame
        func isDockedAndOnscreen(_ keyboardFrame: CGRect) -> Bool {
            if keyboardFrame.minY >= fullFrame.maxY {
                // off-screen
                return false
            }
            if keyboardFrame.maxY < fullFrame.maxY {
                // on-screen, but floating or undocked (iPad)
                return false
            }
            return true
        }

        // Useful when debugging state transitions.
        Logger.verbose("\(userInfo)")
        Logger.verbose("keyboard start: \((startFrame.minY, startFrame.maxY))")
        Logger.verbose("keyboard end: \((endFrame.minY, endFrame.maxY))")
        Logger.verbose("full height: \(fullFrame.maxY)")
        Logger.verbose("current bottom: \(window.frame.maxY)")
        Logger.verbose("saved bottom: \(frameBeforeAdjustingForKeyboard?.maxY ?? 0)")

        if isDockedAndOnscreen(endFrame) {
            guard !(animationDuration == 0 && endFrame.maxY > fullFrame.maxY) else {
                // The older iPad "undock" action has a mysterious zero-duration transition
                // from an empty rect to a half-offscreen frame, *after* a normal transition
                // from a valid docked to a valid undocked frame. We want to ignore that.
                // This is very subtle, and could be broken by a later OS update...
                // but keep in mind that the failure mode here is that the PiP window ends up somewhere it shouldn't.
                // Not the end of the world.
                return
            }
            dockedKeyboardFrame = endFrame
            if !isDockedAndOnscreen(startFrame) {
                // The keyboard is newly docked-and-on-screen;
                // save the current PiP window position so we can reset to it later.
                frameBeforeAdjustingForKeyboard = window.frame
            }
            updatePipLayout(animationDuration: animationDuration, animationCurve: animationCurve)
        } else {
            dockedKeyboardFrame = nil
            if frameBeforeAdjustingForKeyboard != nil {
                // This handles both dismissing the keyboard and changing from docked to undocked/floating.
                updatePipLayout(animationDuration: animationDuration, animationCurve: animationCurve)
                frameBeforeAdjustingForKeyboard = nil
            }
        }
    }

    // MARK: Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

}
