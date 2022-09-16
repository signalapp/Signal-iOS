//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalServiceKit

protocol StoryContextOnboardingOverlayViewDelegate: AnyObject {

    func storyContextOnboardingOverlayWillDisplay(_ : StoryContextOnboardingOverlayView)
    func storyContextOnboardingOverlayDidDismiss(_ : StoryContextOnboardingOverlayView)
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

        // Mark as viewed from now on.
        Self.databaseStorage.write { transaction in
            self.kvStore.setBool(true, key: Self.kvStoreKey, transaction: transaction)
        }
        Self.shouldDisplay = false

        self.superview?.bringSubviewToFront(self)
        isDisplaying = true
        self.isHidden = false
        blurView.effect = .none
        blurView.contentView.alpha = 0
        UIView.animate(withDuration: 0.35) {
            self.blurView.effect = UIBlurEffect(style: .dark)
            self.blurView.contentView.alpha = 1
        }
    }

    func dismiss() {
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

    private func setupSubviews() {
        addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.distribution = .equalCentering

        var prevHStack: UIView?
        for asset in assets {
            let imageContainer = UIView()

            let imageView = UIImageView(image: asset.image?.withRenderingMode(.alwaysTemplate).asTintedImage(color: .ows_white))
            imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            imageContainer.addSubview(imageView)

            imageContainer.autoPinHeight(toHeightOf: imageView)
            imageContainer.autoPinWidth(toWidthOf: imageView)
            imageView.autoVCenterInSuperview()
            imageView.autoAlignAxis(.vertical, toSameAxisOf: imageContainer, withOffset: asset.imageXOffset)

            let label = UILabel()
            label.textColor = .ows_gray05
            label.font = .ows_dynamicTypeBody
            label.text = asset.text
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.alignment = .center
            hStack.distribution = .equalSpacing
            hStack.addArrangedSubviews([imageContainer, label])

            if CurrentAppContext().isRTL {
                label.autoConstrainAttribute(.trailing, to: .vertical, of: imageContainer, withOffset: -46)
            } else {
                label.autoConstrainAttribute(.leading, to: .vertical, of: imageContainer, withOffset: 46)
            }

            vStack.addArrangedSubview(hStack)

            if let prevHStack = prevHStack {
                hStack.autoPinWidth(toWidthOf: prevHStack)
            }
            prevHStack = hStack
        }

        let confirmButtonContainer = ManualLayoutView(name: "confirm_button")
        confirmButtonContainer.shouldDeactivateConstraints = false

        confirmButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        let confirmButton = OWSButton()
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setTitle(
            NSLocalizedString(
                "STORY_VIEWER_ONBOARDING_CONFIRMATION",
                comment: "Confirmation text shown the first time the user opens the story viewer to dismiss instructions."
            ),
            for: .normal
        )
        confirmButton.titleLabel?.font = .ows_dynamicTypeSubheadline.ows_semibold
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

        vStack.addArrangedSubview(confirmButtonContainer)

        blurView.contentView.addSubview(vStack)
        vStack.autoPinHorizontalEdges(toEdgesOf: blurView.contentView)
        vStack.autoVCenterInSuperview()
        vStack.autoConstrainAttribute(.height, to: .height, of: blurView, withMultiplier: 0.6)

        let closeButton = OWSButton()
        closeButton.setImage(
            UIImage(named: "x-24")?
                .withRenderingMode(.alwaysTemplate)
                .asTintedImage(color: .ows_white),
            for: .normal
        )
        closeButton.contentMode = .center
        closeButton.block = { [weak self] in
            self?.dismiss()
        }
        blurView.contentView.addSubview(closeButton)

        closeButton.autoSetDimensions(to: .square(42))
        closeButton.autoPinEdge(toSuperviewEdge: .top, withInset: 20)
        closeButton.autoPinEdge(toSuperviewEdge: .leading, withInset: 20)
    }

    private struct Asset {
        let image: UIImage?
        let imageXOffset: CGFloat
        let text: String
    }

    private var assets: [Asset] {
        [
            Asset(
                image: #imageLiteral(resourceName: "story_viewer_onboarding_1"),
                imageXOffset: 0,
                text: NSLocalizedString(
                    "STORY_VIEWER_ONBOARDING_1",
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it."
                )
            ),
            Asset(
                image: #imageLiteral(resourceName: "story_viewer_onboarding_2"),
                imageXOffset: 0,
                text: NSLocalizedString(
                    "STORY_VIEWER_ONBOARDING_2",
                    comment: "Text shown the first time the user opens the story viewer instructing them how to use it."
                )
            ),
            Asset(
                image: #imageLiteral(resourceName: "story_viewer_onboarding_3"),
                // The asset is "centered" but the designs require misalignment of the
                // assets frame to visually align a sub-part of its contents.
                imageXOffset: -12,
                text: NSLocalizedString(
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
