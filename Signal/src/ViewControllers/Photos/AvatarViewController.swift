//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI
import UIKit

@objc(OWSAvatarViewController)
class AvatarViewController: UIViewController, InteractivelyDismissableViewController {
    private var interactiveDismissal: MediaInteractiveDismiss?
    let avatarImage: UIImage

    @objc
    var maxAvatarPointSize: CGSize {
        let currentScale = avatarImage.scale
        let desiredScale = UIScreen.main.scale
        let factor = currentScale / desiredScale
        return CGSizeScale(avatarImage.size, factor)
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let circleView = CircleView()

    private let closeButton: OWSButton = {
        let button = OWSButton(imageName: "x-24", tintColor: Theme.darkThemePrimaryColor)
        return button
    }()

    @objc
    init?(thread: TSThread, renderLocalUserAsNoteToSelf: Bool, readTx: SDSAnyReadTransaction) {
        let localUserDisplayMode: LocalUserDisplayMode = (renderLocalUserAsNoteToSelf
                                                            ? .noteToSelf
                                                            : .asUser)
        guard let avatarImage = Self.avatarBuilder.avatarImage(
                forThread: thread,
                diameterPoints: UInt(UIScreen.main.bounds.size.smallerAxis),
                localUserDisplayMode: localUserDisplayMode,
                transaction: readTx) else { return nil }

        self.avatarImage = avatarImage
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    @objc
    init?(address: SignalServiceAddress, renderLocalUserAsNoteToSelf: Bool, readTx: SDSAnyReadTransaction) {
        let diameter = UInt(UIScreen.main.bounds.size.smallerAxis)
        guard let avatarImage: UIImage = {
            let localUserDisplayMode: LocalUserDisplayMode = (renderLocalUserAsNoteToSelf
                                                                ? .noteToSelf
                                                                : .asUser)
            if address.isLocalAddress, !renderLocalUserAsNoteToSelf {
                if let avatar = Self.profileManager.localProfileAvatarImage() {
                    return avatar
                }
                return Self.avatarBuilder.avatarImageForLocalUser(diameterPoints: diameter,
                                                                  localUserDisplayMode: localUserDisplayMode,
                                                                  transaction: readTx)
            } else {
                return Self.avatarBuilder.avatarImage(forAddress: address,
                                                      diameterPoints: diameter,
                                                      localUserDisplayMode: localUserDisplayMode,
                                                      transaction: readTx)
            }
        }() else { return nil }

        self.avatarImage = avatarImage
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = Theme.darkThemeBackgroundColor
        view.addSubview(circleView)
        view.addSubview(closeButton)

        circleView.clipsToBounds = true
        circleView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        circleView.autoCenterInSuperview()
        circleView.autoPinToSquareAspectRatio()

        circleView.autoMatch(.width, to: .width, of: view, withOffset: -48).priority = .defaultHigh
        circleView.autoMatch(.width, to: .width, of: view, withOffset: -48, relation: .lessThanOrEqual)
        circleView.autoMatch(.height, to: .height, of: view, withOffset: -48).priority = .defaultHigh
        circleView.autoMatch(.height, to: .height, of: view, withOffset: -48, relation: .lessThanOrEqual)

        closeButton.autoPinTopToSuperviewMargin(withInset: 8)
        closeButton.autoPinLeadingToSuperviewMargin()

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.image = avatarImage

        interactiveDismissal = MediaInteractiveDismiss(targetViewController: self)
        interactiveDismissal?.addGestureRecognizer(to: view)
        closeButton.block = { [weak self] in
            self?.performInteractiveDismissal(animated: true)
        }
    }

    func performInteractiveDismissal(animated: Bool) {
        dismiss(animated: animated)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension AvatarViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        return MediaPresentationContext(mediaView: circleView, presentationFrame: circleView.frame, cornerRadius: circleView.layer.cornerRadius)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}

extension AvatarViewController: UIViewControllerTransitioningDelegate {
    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController) -> UIViewControllerAnimatedTransitioning? {

        return MediaZoomAnimationController(image: avatarImage)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animationController = MediaDismissAnimationController(
            image: avatarImage,
            interactionController: interactiveDismissal)

        interactiveDismissal?.interactiveDismissDelegate = animationController
        return animationController
    }

    public func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let animator = animator as? MediaDismissAnimationController,
              let interactionController = animator.interactionController,
              interactionController.interactionInProgress
        else {
            return nil
        }
        return interactionController
    }
}
