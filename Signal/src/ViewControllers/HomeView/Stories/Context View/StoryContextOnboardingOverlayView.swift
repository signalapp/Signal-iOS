//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

protocol StoryContextOnboardingOverlayViewDelegate: AnyObject {

    func storyContextOnboardingOverlayWillDisplay(_: StoryContextOnboardingOverlayView)
    func storyContextOnboardingOverlayDidDismiss(_: StoryContextOnboardingOverlayView)

    /// Called to exit the entire viewer, not just the onboarding overlay.
    func storyContextOnboardingOverlayWantsToExitStoryViewer(_: StoryContextOnboardingOverlayView)
}

class StoryContextOnboardingOverlayView: UIView {

    private weak var delegate: StoryContextOnboardingOverlayViewDelegate?

    init(delegate: StoryContextOnboardingOverlayViewDelegate) {
        self.delegate = delegate
        super.init(frame: .zero)

        self.isHidden = true
        setupSubviews()

        // The simplest way to have this overlay block all gestures, especially those
        // that would go to the parent UIPageViewController, is to give it no-op
        // gesture recognizers of its own and make them override everything.
        isUserInteractionEnabled = true
        for captureRecognizer in [UIPanGestureRecognizer(), UITapGestureRecognizer(), UILongPressGestureRecognizer()] {
            captureRecognizer.cancelsTouchesInView = true
            captureRecognizer.delegate = self
            addGestureRecognizer(captureRecognizer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Static so multiple parallel instances stay in sync.
    private static var shouldDisplay: Bool?

    func checkIfShouldDisplay() {
        Self.shouldDisplay = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let isOverlayViewed = SSKEnvironment.shared.systemStoryManagerRef.isOnboardingOverlayViewed(transaction: transaction)
            return !isOverlayViewed
        }
    }

    private(set) var isDisplaying: Bool = false {
        didSet {
            guard oldValue != isDisplaying else { return }
            if isDisplaying {
                delegate?.storyContextOnboardingOverlayWillDisplay(self)
            } else {
                delegate?.storyContextOnboardingOverlayDidDismiss(self)
            }
        }
    }

    /// Returns nil if no overlay needs to be shown.
    func showIfNeeded() {
        if Self.shouldDisplay == nil {
            checkIfShouldDisplay()
        }
        guard Self.shouldDisplay ?? false else {
            return
        }

        self.superview?.bringSubviewToFront(self)
        isDisplaying = true
        self.isHidden = false
        blurView.effect = .none
        blurView.contentView.alpha = 0
        UIView.animate(
            withDuration: 0.35,
            animations: {
                self.blurView.effect = UIBlurEffect(style: .dark)
                self.blurView.contentView.alpha = 1
            },
            completion: { [weak self] _ in
                self?.startAnimations()
            },
        )
    }

    func dismiss() {
        // Mark as viewed from now on.
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            SSKEnvironment.shared.systemStoryManagerRef.setOnboardingOverlayViewed(value: true, transaction: transaction)
        }
        Self.shouldDisplay = false

        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.blurView.effect = .none
                self.blurView.contentView.alpha = 0
            },
            completion: { _ in
                self.isHidden = true
                self.isDisplaying = false
            },
        )
    }

    private lazy var blurView = UIVisualEffectView()

    private var animationViews = [LottieAnimationView]()

    private func setupSubviews() {
        addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.distribution = .equalSpacing
        vStack.spacing = 42
        vStack.translatesAutoresizingMaskIntoConstraints = false

        animationViews = []

        for asset in assets {
            let animationView = LottieAnimationView(name: asset.lottieName)
            animationView.loopMode = .playOnce
            animationView.backgroundBehavior = .forceFinish

            let imageContainer = UIView()
            imageContainer.addSubview(animationView)
            animationView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                animationView.widthAnchor.constraint(equalToConstant: 54),
                animationView.heightAnchor.constraint(equalTo: animationView.widthAnchor),

                animationView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
                animationView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
                animationView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
                animationView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            ])

            let label = UILabel()
            label.textColor = .Signal.label
            label.font = .dynamicTypeBodyClamped
            label.text = asset.text
            label.numberOfLines = 0
            label.textAlignment = .center
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let innerVStack = UIStackView(arrangedSubviews: [imageContainer, label])
            innerVStack.axis = .vertical
            innerVStack.alignment = .center
            innerVStack.spacing = 12

            vStack.addArrangedSubview(innerVStack)
            animationViews.append(animationView)
        }

        let confirmButtonTitle = NSLocalizedString(
            "STORY_VIEWER_ONBOARDING_CONFIRMATION",
            comment: "Confirmation text shown the first time the user opens the story viewer to dismiss instructions.",
        )
        var confirmButtonConfiguration: UIButton.Configuration
        if #available(iOS 26, *) {
            confirmButtonConfiguration = .largeSecondary(title: confirmButtonTitle)
        } else {
            confirmButtonConfiguration = UIButton.Configuration.bordered()
            confirmButtonConfiguration.baseForegroundColor = .black
            confirmButtonConfiguration.baseBackgroundColor = .white
            confirmButtonConfiguration.title = confirmButtonTitle
            confirmButtonConfiguration.attributedTitle?.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
            confirmButtonConfiguration.contentInsets = .init(hMargin: 24, vMargin: 8)
            confirmButtonConfiguration.cornerStyle = .capsule
        }

        let confirmButton = UIButton(
            configuration: confirmButtonConfiguration,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss()
            },
        )
        confirmButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(
            configuration: .round(themeIcon: .buttonX),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.storyContextOnboardingOverlayWantsToExitStoryViewer(self)
            },
        )
        closeButton.isPointerInteractionEnabled = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        blurView.contentView.addSubview(closeButton)
        blurView.contentView.addSubview(vStack)
        blurView.contentView.addSubview(confirmButton)

        let vStackLayoutGuide = UILayoutGuide()
        blurView.contentView.addLayoutGuide(vStackLayoutGuide)

        let horizontalMargin = OWSTableViewController2.defaultHOuterMargin
        var closeButtonMargin = horizontalMargin
        if #unavailable(iOS 26), let buttonConfiguration = closeButton.configuration {
            // Button has no background so decrease margin by its content inset amount (should be equal on all sides).
            closeButtonMargin -= buttonConfiguration.contentInsets.leading
        }
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: blurView.topAnchor, constant: closeButtonMargin),
            closeButton.trailingAnchor.constraint(equalTo: blurView.trailingAnchor, constant: -closeButtonMargin),

            vStackLayoutGuide.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 12),
            vStackLayoutGuide.leadingAnchor.constraint(equalTo: blurView.leadingAnchor, constant: horizontalMargin),
            vStackLayoutGuide.trailingAnchor.constraint(equalTo: blurView.trailingAnchor, constant: -horizontalMargin),
            vStackLayoutGuide.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -42),

            vStack.topAnchor.constraint(greaterThanOrEqualTo: vStackLayoutGuide.topAnchor),
            vStack.centerYAnchor.constraint(equalTo: vStackLayoutGuide.centerYAnchor),
            vStack.leadingAnchor.constraint(equalTo: vStackLayoutGuide.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: vStackLayoutGuide.trailingAnchor),

            confirmButton.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
            confirmButton.bottomAnchor.constraint(equalTo: blurView.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])

        // When using glass button make it generously wide - at least 44% of the screen width.
        if #available(iOS 26, *) {
            confirmButton.widthAnchor.constraint(greaterThanOrEqualTo: blurView.widthAnchor, multiplier: 0.44).isActive = true
        }
    }

    private func startAnimations() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.playAnimation(at: 0)
        }
    }

    private func playAnimation(at index: Int) {
        guard !animationViews.isEmpty, self.isDisplaying else {
            return
        }
        guard let animationView = animationViews[safe: index] else {
            startAnimations()
            return
        }
        animationView.play { [weak self] _ in
            self?.playAnimation(at: index + 1)
        }
    }

    private struct Asset {
        let lottieName: String
        let text: String
    }

    private var assets: [Asset] {
        [
            Asset(
                lottieName: "story_viewer_onboarding_1",
                text: OWSLocalizedString(
                    "STORY_VIEWER_ONBOARDING_1",
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it.",
                ),
            ),
            Asset(
                lottieName: "story_viewer_onboarding_2",
                text: OWSLocalizedString(
                    "STORY_VIEWER_ONBOARDING_2",
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it.",
                ),
            ),
            Asset(
                lottieName: "story_viewer_onboarding_3",
                text: OWSLocalizedString(
                    "STORY_VIEWER_ONBOARDING_3",
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it.",
                ),
            ),
        ]
    }
}

extension StoryContextOnboardingOverlayView: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
