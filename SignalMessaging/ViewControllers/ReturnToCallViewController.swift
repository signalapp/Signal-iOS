//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol CallViewControllerWindowReference: class {
    var localVideoViewReference: UIView { get }
    var remoteVideoViewReference: UIView { get }
    var remoteVideoAddress: SignalServiceAddress { get }
    var view: UIView! { get }

    func returnFromPip(pipWindow: UIWindow)
}

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

        let (profileImage, conversationColorName) = databaseStorage.uiRead { transaction in
            return (
                self.profileManager.profileAvatar(for: callViewController.remoteVideoAddress, transaction: transaction),
                self.contactsManager.conversationColorName(for: callViewController.remoteVideoAddress, transaction: transaction)
            )
        }

        backgroundAvatarView.image = profileImage

        avatarView.image = OWSContactAvatarBuilder(
            address: callViewController.remoteVideoAddress,
            colorName: conversationColorName,
            diameter: 60
        ).build()

        animatePipPresentation(snapshot: callViewSnapshot)
    }

    @objc
    public func resignCall() {
        callViewController?.localVideoViewReference.removeFromSuperview()
        callViewController?.remoteVideoViewReference.removeFromSuperview()
        callViewController = nil
    }

    private lazy var avatarView = AvatarImageView()
    private lazy var backgroundAvatarView = UIImageView()
    private lazy var blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))

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
        avatarView.autoSetDimensions(to: CGSize(square: 60))
        avatarView.autoCenterInSuperview()

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
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

    private var pipBoundingRect: CGRect {
        let padding: CGFloat = 4
        var rect = CurrentAppContext().frame

        let safeAreaInsets = OWSWindowManager.shared.rootWindow.safeAreaInsets

        let leftInset = safeAreaInsets.left + padding
        let rightInset = safeAreaInsets.right + padding
        rect.origin.x += leftInset
        rect.size.width -= leftInset + rightInset

        let topInset = safeAreaInsets.top + padding
        let bottomInset = safeAreaInsets.bottom + padding
        rect.origin.y += topInset
        rect.size.height -= topInset + bottomInset

        return rect
    }

    private func updatePipLayout() {
        guard !isAnimating else { return }
        guard let window = view.window else { return owsFailDebug("missing window") }
        let newFrame = CGRect(
            origin: window.frame.origin,
            size: Self.pipSize
        ).pinnedToVerticalEdge(of: pipBoundingRect)
        UIView.animate(withDuration: 0.25) {
            self.updateLocalVideoFrame()
            window.frame = newFrame
        }
    }

    @objc func handlePan(sender: UIPanGestureRecognizer) {
        guard let window = view.window else { return owsFailDebug("missing window") }

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

    // MARK: Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

}
