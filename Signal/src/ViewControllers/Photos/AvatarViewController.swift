//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

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

    private let closeButton: OWSButton = {
        let button = OWSButton(imageName: "x-24", tintColor: Theme.darkThemePrimaryColor)
        return button
    }()

    @objc
    init?(thread: TSThread, readTx: SDSAnyReadTransaction) {
        guard let avatarImage = Self.avatarBuilder.avatarImage(
                forThread: thread,
                diameterPoints: UInt(UIScreen.main.bounds.size.smallerAxis),
                localUserDisplayMode: .asUser,
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
        view.addSubview(imageView)
        view.addSubview(closeButton)

        let imageRatio = CGFloat(avatarImage.pixelWidth) / CGFloat(avatarImage.pixelHeight)

        imageView.autoCenterInSuperview()
        imageView.autoPin(toAspectRatio: imageRatio)

        imageView.autoMatch(.width, to: .width, of: view).priority = .defaultHigh
        imageView.autoMatch(.width, to: .width, of: view, withOffset: 0, relation: .lessThanOrEqual)
        imageView.autoMatch(.height, to: .height, of: view).priority = .defaultHigh
        imageView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)

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
        return MediaPresentationContext(mediaView: imageView, presentationFrame: imageView.frame, cornerRadius: 0)
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
