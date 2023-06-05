//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalUI

class AnimatedProgressView: UIView {
    var hidesWhenStopped = true
    private(set) var isAnimating = false

    var loadingText: String? {
        get { label.text }
        set { label.text = newValue }
    }

    private let label = UILabel()
    private let progressAnimation = AnimationView(name: "pinCreationInProgress")
    private let errorAnimation = AnimationView(name: "pinCreationFail")
    private let successAnimation = AnimationView(name: "pinCreationSuccess")

    required init(loadingText: String? = nil) {
        super.init(frame: .zero)

        let animationContainer = UIView()
        progressAnimation.backgroundBehavior = .pauseAndRestore
        progressAnimation.loopMode = .playOnce
        progressAnimation.contentMode = .scaleAspectFit
        animationContainer.addSubview(progressAnimation)
        progressAnimation.autoPinEdgesToSuperviewEdges()

        errorAnimation.backgroundBehavior = .pauseAndRestore
        errorAnimation.loopMode = .playOnce
        errorAnimation.contentMode = .scaleAspectFit
        animationContainer.addSubview(errorAnimation)
        errorAnimation.autoPinEdgesToSuperviewEdges()

        successAnimation.backgroundBehavior = .pauseAndRestore
        successAnimation.loopMode = .playOnce
        successAnimation.contentMode = .scaleAspectFit
        animationContainer.addSubview(successAnimation)
        successAnimation.autoPinEdgesToSuperviewEdges()

        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17)
        label.textColor = Theme.primaryTextColor
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        self.loadingText = loadingText

        addSubview(animationContainer)
        addSubview(label)

        animationContainer.autoPinWidthToSuperview()
        label.autoPinWidthToSuperview(withMargin: 8)

        animationContainer.autoPinEdge(toSuperviewEdge: .top)
        label.autoPinEdge(.top, to: .bottom, of: animationContainer, withOffset: 12)
        label.autoPinBottomToSuperviewMargin()

        reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func reset() {
        progressAnimation.isHidden = false
        progressAnimation.stop()
        successAnimation.isHidden = true
        successAnimation.stop()
        errorAnimation.isHidden = true
        errorAnimation.stop()
        completedSuccessfully = nil
        animationCompletionHandler = nil
        isAnimating = false

        if hidesWhenStopped {
            alpha = 0
        }
    }

    func startAnimating(alongside animationBlock: @escaping () -> Void = {}) {
        AssertIsOnMainThread()
        owsAssertDebug(!isAnimating)
        reset()
        isAnimating = true

        self.startNextLoopOrFinish()

        UIView.animate(withDuration: 0.15) {
            if self.hidesWhenStopped {
                self.alpha = 1
            }
            animationBlock()
        }
    }

    func stopAnimatingImmediately() {
        AssertIsOnMainThread()
        owsAssertDebug(isAnimating)

        if let animationCompletionHandler = animationCompletionHandler {
            UIView.performWithoutAnimation(animationCompletionHandler)
        } else {
            reset()
        }
    }

    func stopAnimating(success: Bool, animateAlongside: (() -> Void)? = nil, completion: @escaping () -> Void) {
        AssertIsOnMainThread()
        owsAssertDebug(isAnimating)

        // Marking the animation complete does not immediately stop the animation,
        // instead it sets this flag which waits until the animation is at the point
        // it can transition to the next state.
        completedSuccessfully = success

        animationCompletionHandler = { [weak self] in
            guard let self = self else {
                animateAlongside?()
                completion()
                return
            }

            self.animationCompletionHandler = nil
            UIView.animate(withDuration: 0.15, animations: {
                if self.hidesWhenStopped == true {
                    self.alpha = 0
                }
                animateAlongside?()
            }) { _ in
                self.reset()
                completion()
            }
        }
    }

    private var completedSuccessfully: Bool?
    private var animationCompletionHandler: (() -> Void)?

    private func startNextLoopOrFinish() {
        // If we haven't yet completed, start another loop of the progress animation.
        // We'll check again when it's done.
        guard let completedSuccessfully = completedSuccessfully else {
            return progressAnimation.playAndWhenFinished { [weak self] in
                self?.startNextLoopOrFinish()
            }
        }

        guard !progressAnimation.isHidden else { return }

        progressAnimation.stop()
        progressAnimation.isHidden = true

        if completedSuccessfully {
            successAnimation.isHidden = false
            successAnimation.play { [weak self] _ in self?.completeAnimation() }
        } else {
            errorAnimation.isHidden = false
            errorAnimation.play { [weak self] _ in self?.completeAnimation() }
        }
    }

    private func completeAnimation() {
        guard let animationCompletion = self.animationCompletionHandler else { return }
        self.animationCompletionHandler = nil

        animationCompletion()
    }
}

private extension AnimationView {
    func playAndWhenFinished(_ completion: @escaping () -> Void) {
        play { didComplete in
            if didComplete {
                completion()
            } else {
                // Animation was interrupted before completing, skipping completion.
            }
        }
    }
}
