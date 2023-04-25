//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SignalServiceKit
import UIKit

protocol StoryContextOnboardingOverlayViewDelegate: AnyObject {

    func storyContextOnboardingOverlayWillDisplay(_: StoryContextOnboardingOverlayView)
    func storyContextOnboardingOverlayDidDismiss(_: StoryContextOnboardingOverlayView)

    /// Called to exit the entire viewer, not just the onboarding overlay.
    func storyContextOnboardingOverlayWantsToExitStoryViewer(_: StoryContextOnboardingOverlayView)
}

class StoryContextOnboardingOverlayView: UIView, Dependencies {

    private let kvStore = SDSKeyValueStore(collection: "StoryViewerOnboardingOverlay")
    static let kvStoreKey = "hasSeenStoryViewerOnboardingOverlay"

    private weak var delegate: StoryContextOnboardingOverlayViewDelegate?

    public init(delegate: StoryContextOnboardingOverlayViewDelegate) {
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
        Self.shouldDisplay = Self.databaseStorage.read { transaction in
            if self.kvStore.getBool(Self.kvStoreKey, defaultValue: false, transaction: transaction) {
                return false
            }

            if Self.systemStoryManager.isOnboardingStoryViewed(transaction: transaction) {
                // We don't sync view state for the onboarding overlay. But we can use
                // viewing of the onboarding story as an imperfect proxy; if they viewed it
                // that means they also definitely saw the viewer overlay.
                return false
            }
            return true
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
            }
        )
    }

    func dismiss() {
        // Mark as viewed from now on.
        Self.databaseStorage.write { transaction in
            self.kvStore.setBool(true, key: Self.kvStoreKey, transaction: transaction)
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
            }
        )
    }

    private lazy var blurView = UIVisualEffectView()

    private var animationViews = [AnimationView]()

    private func setupSubviews() {
        addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.distribution = .equalSpacing
        vStack.spacing = 42

        animationViews = []

        for asset in assets {
            let imageContainer = UIView()

            let animationView = AnimationView(name: asset.lottieName)
            animationView.loopMode = .playOnce
            animationView.backgroundBehavior = .forceFinish
            animationView.autoSetDimensions(to: .square(54))

            imageContainer.addSubview(animationView)

            imageContainer.autoPinHeight(toHeightOf: animationView)
            imageContainer.autoPinWidth(toWidthOf: animationView)
            animationView.autoVCenterInSuperview()
            animationView.autoAlignAxis(.vertical, toSameAxisOf: imageContainer)

            let label = UILabel()
            label.textColor = .ows_gray05
            label.font = .dynamicTypeBodyClamped
            label.text = asset.text
            label.numberOfLines = 0
            label.textAlignment = .center
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let innerVStack = UIStackView()
            innerVStack.axis = .vertical
            innerVStack.alignment = .center
            innerVStack.distribution = .equalSpacing
            innerVStack.spacing = 12
            innerVStack.addArrangedSubviews([imageContainer, label])

            vStack.addArrangedSubview(innerVStack)

            animationViews.append(animationView)
        }

        let confirmButtonContainer = ManualLayoutView(name: "confirm_button")
        confirmButtonContainer.shouldDeactivateConstraints = false

        confirmButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        let confirmButton = OWSButton()
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setTitle(
            OWSLocalizedString(
                "STORY_VIEWER_ONBOARDING_CONFIRMATION",
                comment: "Confirmation text shown the first time the user opens the story viewer to dismiss instructions."
            ),
            for: .normal
        )
        confirmButton.titleLabel?.font = .dynamicTypeSubheadlineClamped.semibold()
        confirmButton.backgroundColor = .ows_white
        confirmButton.setTitleColor(.ows_black, for: .normal)
        confirmButton.contentEdgeInsets = UIEdgeInsets(hMargin: 23, vMargin: 8)
        confirmButton.block = { [weak self] in
            self?.dismiss()
        }

        confirmButtonContainer.addSubview(confirmButton) { view in
            confirmButton.layer.cornerRadius = confirmButton.height / 2
        }
        confirmButton.autoPinEdges(toEdgesOf: confirmButtonContainer)

        let closeButton = OWSButton()
        closeButton.setImage(
            UIImage(named: "x-24")?
                .withRenderingMode(.alwaysTemplate)
                .asTintedImage(color: .ows_white),
            for: .normal
        )
        closeButton.contentMode = .center
        closeButton.block = { [weak self] in
            guard let self = self else { return }
            self.delegate?.storyContextOnboardingOverlayWantsToExitStoryViewer(self)
        }
        blurView.contentView.addSubview(closeButton)
        blurView.contentView.addSubview(vStack)
        blurView.contentView.addSubview(confirmButtonContainer)

        let vStackLayoutGuide = UILayoutGuide()
        blurView.contentView.addLayoutGuide(vStackLayoutGuide)

        confirmButtonContainer.autoHCenterInSuperview()
        confirmButtonContainer.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 32)

        vStack.autoPinEdge(.leading, to: .leading, of: blurView, withOffset: 12)
        vStack.autoPinEdge(.trailing, to: .trailing, of: blurView, withOffset: -12)
        vStack.autoPinEdge(.top, to: .bottom, of: closeButton, withOffset: 12, relation: .greaterThanOrEqual)
        vStack.autoPinEdge(.bottom, to: .top, of: confirmButtonContainer, withOffset: -42, relation: .lessThanOrEqual)

        NSLayoutConstraint.activate([
            vStackLayoutGuide.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 12),
            vStackLayoutGuide.bottomAnchor.constraint(equalTo: confirmButtonContainer.topAnchor, constant: -42),
            vStack.centerYAnchor.constraint(equalTo: vStackLayoutGuide.centerYAnchor)
        ])

        closeButton.autoSetDimensions(to: .square(42))
        closeButton.autoPinEdge(toSuperviewEdge: .top, withInset: 20)
        closeButton.autoPinEdge(toSuperviewEdge: .leading, withInset: 20)
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
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it."
                )
            ),
            Asset(
                lottieName: "story_viewer_onboarding_2",
                text: OWSLocalizedString(
                    "STORY_VIEWER_ONBOARDING_2",
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it."
                )
            ),
            Asset(
                lottieName: "story_viewer_onboarding_3",
                text: OWSLocalizedString(
                    "STORY_VIEWER_ONBOARDING_3",
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it."
                )
            )
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
