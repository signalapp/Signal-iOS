//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol CallViewControllerWindowReference: class {
    var localVideoViewReference: UIView { get }
    var remoteVideoViewReference: UIView { get }
    var thread: TSContactThread { get }
    var view: UIView { get }

    func returnFromPip(pipWindow: UIWindow)
}

@objc
public protocol ReturnToCallViewControllerDelegate: class {
    func returnToCallWasTapped(_ viewController: ReturnToCallViewController)
}

@objc
public class ReturnToCallViewController: UIViewController {

    @objc
    public static var pipSize = UIDevice.current.isIPad ? CGSize(width: 272, height: 204) : CGSize(width: 90, height: 160)

    @objc
    public weak var delegate: ReturnToCallViewControllerDelegate?

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

        let localVideoSize = CGSizeScale(Self.pipSize, 0.3)
        callViewController.localVideoViewReference.frame = CGRect(
            origin: CGPoint(
                x: Self.pipSize.width - 6 - localVideoSize.width,
                y: Self.pipSize.height - 6 - localVideoSize.height
            ),
            size: localVideoSize
        )

        backgroundAvatarView.image = Environment.shared.contactsManager.profileImageForAddress(
            withSneakyTransaction: callViewController.thread.contactAddress
        )
        avatarView.image = OWSAvatarBuilder.buildImage(thread: callViewController.thread, diameter: 60)

        animatePipPresentation(snapshot: callViewSnapshot)
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

    // MARK: -

    private func animatePipPresentation(snapshot: UIView) {
        guard let window = view.window else { return owsFailDebug("missing window") }
        let previousOrigin = window.frame.origin
        window.frame = OWSWindowManager.shared.rootWindow.bounds

        view.addSubview(snapshot)
        snapshot.autoPinEdgesToSuperviewEdges()

        window.layoutIfNeeded()

        UIView.animate(withDuration: 0.2, animations: {
            snapshot.alpha = 0
            window.frame = self.nearestValidPipFrame(for: previousOrigin)
            window.layoutIfNeeded()
        }) { _ in
            snapshot.removeFromSuperview()
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

    private func nearestValidPipFrame(for origin: CGPoint) -> CGRect {
        var newFrame = CGRect(origin: origin, size: Self.pipSize)

        let boundingRect = pipBoundingRect

        // If the origin is zero, we always want to position
        // the pip in the top right
        let hasZeroOrigin = newFrame.origin == .zero

        // If we're positioned outside of the vertical bounds, we
        // want to position the pip at the nearest bound
        let positionedOutOfVerticalBounds = newFrame.minY < boundingRect.minY || newFrame.maxY > boundingRect.maxY

        // If we're position anywhere but exactly at the horizontal
        // edges, we want to position the pip at the nearest edge
        let positionedAwayFromHorizontalEdges = boundingRect.minX != newFrame.minX && boundingRect.maxX != newFrame.maxX

        if positionedOutOfVerticalBounds {
            if newFrame.minY < boundingRect.minY || hasZeroOrigin {
                newFrame.origin.y = boundingRect.minY
            } else {
                newFrame.origin.y = boundingRect.maxY - newFrame.height
            }
        }

        if positionedAwayFromHorizontalEdges {
            let distanceFromLeading = newFrame.minX - boundingRect.minX
            let distanceFromTrailing = boundingRect.maxX - newFrame.maxX

            if distanceFromLeading > distanceFromTrailing || hasZeroOrigin {
                newFrame.origin.x = boundingRect.maxX - newFrame.width
            } else {
                newFrame.origin.x = boundingRect.minX
            }
        }

        return newFrame
    }

    private func updatePipLayout() {
        guard let window = view.window else { return owsFailDebug("missing window") }
        let newFrame = nearestValidPipFrame(for: window.frame.origin)
        UIView.animate(withDuration: 0.25) { window.frame = newFrame }
    }

    private var startingTranslation: CGPoint?
    @objc func handlePan(sender: UIPanGestureRecognizer) {
        guard let window = view.window else { return owsFailDebug("missing window") }

        switch sender.state {
        case .began, .changed:
            let translation = sender.translation(in: view)
            sender.setTranslation(.zero, in: view)

            window.frame.origin.y += translation.y
            window.frame.origin.x += translation.x
        case .ended, .cancelled, .failed:
            let velocity = sender.velocity(in: view)

            // TODO: maybe do more sophisticated deceleration

            let duration: CGFloat = 0.35

            let additionalDistanceX = velocity.x * duration
            let additionalDistanceY = velocity.y * duration

            let finalDestination = CGPoint(
                x: window.frame.origin.x + additionalDistanceX,
                y: window.frame.origin.y + additionalDistanceY
            )

            let finalFrame = nearestValidPipFrame(for: finalDestination)

            UIView.animate(withDuration: TimeInterval(duration)) { window.frame = finalFrame }
        default:
            break
        }
    }

    @objc
    private func handleTap(sender: UITapGestureRecognizer) {
        callViewController?.localVideoViewReference.removeFromSuperview()
        callViewController?.remoteVideoViewReference.removeFromSuperview()
        callViewController = nil
        self.delegate?.returnToCallWasTapped(self)
    }

    // MARK: Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

}
