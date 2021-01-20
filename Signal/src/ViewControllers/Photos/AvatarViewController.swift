//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc(OWSAvatarViewController)
class AvatarViewController: UIViewController, InteractivelyDismissableViewController {
    private var interactiveDismissal: MediaInteractiveDismiss?
    let avatarImage: UIImage

    @objc
    var avatarSize: CGSize {
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

    @objc
    init?(thread: TSThread, readTx: SDSAnyReadTransaction) {
        guard let avatarImage = OWSAvatarBuilder.buildImage(
                thread: thread,
                diameter: UInt(UIScreen.main.bounds.width),
                transaction: readTx) else { return nil }

        self.avatarImage = avatarImage
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    @objc
    init?(address: SignalServiceAddress, readTx: SDSAnyReadTransaction) {
        guard let avatarImage = OWSContactAvatarBuilder.buildImage(
                address: address,
                diameter: UInt(UIScreen.main.bounds.width),
                transaction: readTx) else { return nil }

        self.avatarImage = avatarImage
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .ows_black
        view.addSubview(imageView)

        let imageRatio = CGFloat(avatarImage.pixelWidth()) / CGFloat(avatarImage.pixelHeight())

        imageView.autoCenterInSuperview()
        imageView.autoPin(toAspectRatio: imageRatio)

        imageView.autoMatch(.width, to: .width, of: view).priority = .defaultHigh
        imageView.autoMatch(.width, to: .width, of: view, withOffset: 0, relation: .lessThanOrEqual)
        imageView.autoSetDimension(.width, toSize: avatarSize.width, relation: .lessThanOrEqual)

        imageView.autoMatch(.height, to: .height, of: view).priority = .defaultHigh
        imageView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)
        imageView.autoSetDimension(.height, toSize: avatarSize.height, relation: .lessThanOrEqual)

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.image = avatarImage

        interactiveDismissal = MediaInteractiveDismiss(targetViewController: self)
        interactiveDismissal?.addGestureRecognizer(to: view)
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
