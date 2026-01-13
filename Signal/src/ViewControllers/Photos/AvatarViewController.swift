//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class AvatarViewController: OWSViewController, InteractivelyDismissableViewController {
    private lazy var interactiveDismissal = MediaInteractiveDismiss(targetViewController: self)
    let avatarImage: UIImage

    var maxAvatarPointSize: CGSize {
        let currentScale = avatarImage.scale
        let desiredScale = UIScreen.main.scale
        let factor = currentScale / desiredScale
        return CGSize.scale(avatarImage.size, factor: factor)
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let circleView = CircleView()

    private var navigationBarTopLayoutConstraint: NSLayoutConstraint?

    private var backgroundColor: UIColor {
        // Not using UIColor.Signal.background here because this VC is presented modally
        // but we need `base` background color and not `elevated`.
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? Theme.darkThemeBackgroundColor
                : Theme.lightThemeBackgroundColor
        }
    }

    init?(thread: TSThread, renderLocalUserAsNoteToSelf: Bool, readTx: DBReadTransaction) {
        let localUserDisplayMode: LocalUserDisplayMode = (renderLocalUserAsNoteToSelf
            ? .noteToSelf
            : .asUser)
        guard
            let avatarImage = SSKEnvironment.shared.avatarBuilderRef.avatarImage(
                forThread: thread,
                diameterPoints: UInt(UIScreen.main.bounds.size.smallerAxis),
                localUserDisplayMode: localUserDisplayMode,
                transaction: readTx,
            ) else { return nil }

        self.avatarImage = avatarImage
        super.init()

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    init?(address: SignalServiceAddress, renderLocalUserAsNoteToSelf: Bool, readTx: DBReadTransaction) {
        let avatarImage = SSKEnvironment.shared.avatarBuilderRef.avatarImage(
            forAddress: address,
            diameterPoints: UInt(UIScreen.main.bounds.size.smallerAxis),
            localUserDisplayMode: renderLocalUserAsNoteToSelf ? .noteToSelf : .asUser,
            transaction: readTx,
        )
        guard let avatarImage else {
            return nil
        }

        self.avatarImage = avatarImage
        super.init()

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = backgroundColor

        imageView.image = avatarImage
        circleView.addSubview(imageView)
        circleView.clipsToBounds = true
        circleView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(circleView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: circleView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: circleView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: circleView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: circleView.bottomAnchor),

            circleView.widthAnchor.constraint(equalTo: circleView.heightAnchor),

            circleView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            circleView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            circleView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, constant: -48),
        ])
        let highPriorityConstraints = [
            circleView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -48),
            circleView.heightAnchor.constraint(equalTo: view.heightAnchor, constant: -48),
        ]
        highPriorityConstraints.forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate(highPriorityConstraints)

        // Use UINavigationBar so that close button X on the left has a standard position in all cases.
        let navigationBar = UINavigationBar()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationBar.standardAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationBar)
        navigationBarTopLayoutConstraint = navigationBar.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([
            navigationBarTopLayoutConstraint!,
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let navigationItem = UINavigationItem(title: "")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: Theme.iconImage(.buttonX),
            style: .plain,
            target: self,
            action: #selector(didTapClose),
        )
        navigationBar.setItems([navigationItem], animated: false)

        if #unavailable(iOS 26) {
            overrideUserInterfaceStyle = .dark
            navigationBar.tintColor = Theme.darkThemeNavbarIconColor
        }

        interactiveDismissal.addGestureRecognizer(to: view)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if let navigationBarTopLayoutConstraint {
            //
            // Copied from MediaPageViewController.
            //

            // On iPhones with a Dynamic Island standard position of a navigation bar is bottom of the status bar,
            // which is ~5 dp smaller than the top safe area inset (https://useyourloaf.com/blog/iphone-14-screen-sizes/) .
            // Since it is not possible to constrain top edge of our manually maintained navigation bar to that position
            // the workaround is to detect when top safe area inset is larger than the status bar height and adjust as needed.
            var topInset = view.safeAreaInsets.top
            if
                #unavailable(iOS 26),
                let statusBarHeight = view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
                statusBarHeight < topInset
            {
                topInset = statusBarHeight
                if #available(iOS 18, *) {
                    topInset += (2 + .hairlineWidth)
                } else if #available(iOS 16, *) {
                    topInset -= .hairlineWidth
                }
            }
            // On iOS 26 in landscape the navigation bar is offset 24 dp from the screen top edge.
            if #available(iOS 26, *), topInset.isZero {
                topInset = 24
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
        view.layoutIfNeeded()

        let backgroundColor: UIColor = if #available(iOS 26, *) { backgroundColor } else { .black }
        return MediaPresentationContext(
            mediaView: circleView,
            presentationFrame: circleView.frame,
            backgroundColor: backgroundColor,
            mediaViewShape: .circle,
        )
    }

    func mediaWillPresent(toContext: MediaPresentationContext) {
        view.backgroundColor = .clear
    }

    func mediaDidPresent(toContext: MediaPresentationContext) {
        view.backgroundColor = backgroundColor
    }

    func mediaWillDismiss(fromContext: MediaPresentationContext) {
        view.backgroundColor = .clear
    }

    func mediaDidDismiss(fromContext: MediaPresentationContext) {
        view.backgroundColor = backgroundColor
    }
}

extension AvatarViewController: UIViewControllerTransitioningDelegate {
    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController,
    ) -> UIViewControllerAnimatedTransitioning? {
        return MediaZoomAnimationController(image: avatarImage)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animationController = MediaDismissAnimationController(
            image: avatarImage,
            interactionController: interactiveDismissal,
        )
        interactiveDismissal.interactiveDismissDelegate = animationController
        return animationController
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard
            let animationController = animator as? MediaDismissAnimationController,
            animationController.interactionController.interactionInProgress
        else {
            return nil
        }
        return animationController.interactionController
    }
}
