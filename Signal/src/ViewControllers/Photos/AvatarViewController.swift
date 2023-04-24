//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI
import UIKit

class AvatarViewController: UIViewController, InteractivelyDismissableViewController {
    private lazy var interactiveDismissal = MediaInteractiveDismiss(targetViewController: self)
    let avatarImage: UIImage

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

    private var navigationBarTopLayoutConstraint: NSLayoutConstraint?

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

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.darkThemeBackgroundColor

        circleView.clipsToBounds = true
        view.addSubview(circleView)
        circleView.autoCenterInSuperview()
        circleView.autoPinToSquareAspectRatio()
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            circleView.autoMatch(.width, to: .width, of: view, withOffset: -48)
            circleView.autoMatch(.height, to: .height, of: view, withOffset: -48)
        }
        circleView.autoMatch(.width, to: .width, of: view, withOffset: -48, relation: .lessThanOrEqual)
        circleView.autoMatch(.height, to: .height, of: view, withOffset: -48, relation: .lessThanOrEqual)

        imageView.image = avatarImage
        circleView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        // Use UINavigationBar so that close button X on the left has a standard position in all cases.
        let navigationBar = UINavigationBar()
        navigationBar.tintColor = Theme.darkThemeNavbarIconColor
        if #available(iOS 13, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            navigationBar.standardAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.overrideUserInterfaceStyle = .dark
        } else {
            navigationBar.barTintColor = .clear
            navigationBar.isTranslucent = false
        }
        view.addSubview(navigationBar)
        navigationBar.autoPinWidthToSuperview()
        navigationBarTopLayoutConstraint = navigationBar.autoPinEdge(toSuperviewEdge: .top)
        navigationBar.autoPinEdge(toSuperviewEdge: .bottom)

        let navigationItem = UINavigationItem(title: "")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(imageLiteralResourceName: "x-24"),
            style: .plain,
            target: self,
            action: #selector(didTapClose),
            accessibilityIdentifier: "close")
        navigationBar.setItems([navigationItem], animated: false)

        interactiveDismissal.addGestureRecognizer(to: view)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if let navigationBarTopLayoutConstraint {
            // On iPhones with a Dynamic Island standard position of a navigation bar is bottom of the status bar,
            // which is ~5 dp smaller than the top safe area (https://useyourloaf.com/blog/iphone-14-screen-sizes/) .
            // Since it is not possible to constrain top edge of our manually maintained navigation bar to that position
            // the workaround is to detect exactly safe area of 59 points and decrease it.
            var topInset = view.safeAreaInsets.top
            if topInset == 59 {
                topInset -= 5 + CGHairlineWidth()
            }
            navigationBarTopLayoutConstraint.constant = topInset
        }
    }

    @objc
    private func didTapClose() {
        performInteractiveDismissal(animated: true)
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
        return MediaPresentationContext(
            mediaView: circleView,
            presentationFrame: circleView.frame,
            mediaViewShape: .circle
        )
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
            interactionController: interactiveDismissal
        )
        interactiveDismissal.interactiveDismissDelegate = animationController
        return animationController
    }

    public func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard
            let animationController = animator as? MediaDismissAnimationController,
            animationController.interactionController.interactionInProgress
        else {
            return nil
        }
        return animationController.interactionController
    }
}
