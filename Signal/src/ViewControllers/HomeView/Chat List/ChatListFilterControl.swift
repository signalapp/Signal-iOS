//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Symbols
import UIKit

protocol ChatListFilterControlDelegate: AnyObject {
    func filterControlDidStartFiltering()
}

final class ChatListFilterControl: UIView, UIScrollViewDelegate {
    private struct AnimationFrame: CaseIterable {
        static let allCases = [
            AnimationFrame(step: 0, relativeStartTime: 0, relativeDuration: 0, isFiltering: false),
            AnimationFrame(step: 1, relativeStartTime: 0.2, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 2, relativeStartTime: 0.4, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 3, relativeStartTime: 0.6, relativeDuration: 0.2, isFiltering: false),
            AnimationFrame(step: 3, relativeStartTime: 0.99, relativeDuration: 0, isFiltering: true),
        ]

        var step: Int
        var relativeStartTime: Double
        var relativeDuration: Double
        var isFiltering: Bool

        var image: UIImage {
            let resource = ImageResource(name: "filter.increment.\(step)", bundle: .main)

            let configuration: UIImage.SymbolConfiguration =
                switch (step, isFiltering) {
                case (0, false): .filterIconBackground
                case (_, false): .filterIconIncrementing
                case (_, true): .filterIconFiltering
                }

            return UIImage(resource: resource)
                .withAlignmentRectInsets(.zero)
                .withConfiguration(configuration)
        }

        func configure(_ imageView: UIView) {
            imageView.alpha = 0
        }

        func animate(_ imageView: UIImageView) {
            imageView.alpha = 1
        }
    }

    private enum State {
        /// Control is not visible, filtering is disabled.
        case inactive

        /// Control is appearing, but not interactively.
        case starting

        /// Control is appearing, tracking scroll position.
        case tracking

        /// Started filtering (i.e., called `delegate.filterControlDidStartFiltering()`),
        /// but still tracking scroll position.
        case pending

        /// Actively filtering and control is docked to the top of the scroll view.
        case filtering

        /// Control is disappearing.
        case stopping

        /// Whether the control is in the filtering state or transitioning into it (i.e., pending).
        var isFiltering: Bool {
            switch self {
            case .pending, .filtering:
                return true
            case .inactive, .starting, .tracking, .stopping:
                return false
            }
        }

        mutating func startOrContinueTracking() -> Bool {
            switch self {
            case .pending, .filtering, .stopping, .starting:
                return false
            case .inactive:
                self = .tracking
                fallthrough
            case .tracking:
                return true
            }
        }
    }

    private let contentView: UIView
    private let overlayView: UIView
    private let imageViews: [UIImageView]
    private let animationFrames: [AnimationFrame]
    private let animator: UIViewPropertyAnimator
    private var feedback: UIImpactFeedbackGenerator?
    private var state = State.inactive

    weak var delegate: (any ChatListFilterControlDelegate)?

    private var animationDuration: CGFloat {
        UIView.inheritedAnimationDuration == 0 ? CATransaction.animationDuration() : UIView.inheritedAnimationDuration
    }

    private var scrollView: UIScrollView? {
        superview as? UIScrollView
    }

    override init(frame: CGRect) {
        var frame = frame
        frame.size.height = 52
        let bounds = CGRect(origin: .zero, size: frame.size)
        contentView = UIView(frame: bounds)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.backgroundColor = .Signal.background
        contentView.preservesSuperviewLayoutMargins = true
        overlayView = UIView(frame: bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.backgroundColor = .Signal.background
        animationFrames = AnimationFrame.allCases
        imageViews = animationFrames.map { UIImageView(image: $0.image) }
        animator = UIViewPropertyAnimator()
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        setContentHuggingPriority(.required, for: .vertical)
        addSubview(contentView)
        addSubview(overlayView)
        contentView.autoPinEdgesToSuperviewEdges()

        for (imageView, frame) in zip(imageViews, animationFrames) {
            contentView.addSubview(imageView)
            imageView.sizeToFit()
            frame.configure(imageView)
        }

        animator.addAnimations { [unowned self] in
            UIView.animateKeyframes(withDuration: animationDuration, delay: 0) { [imageViews, animationFrames] in
                for (imageView, frame) in zip(imageViews, animationFrames) {
                    UIView.addKeyframe(withRelativeStartTime: frame.relativeStartTime, relativeDuration: frame.relativeDuration) {
                        frame.animate(imageView)
                    }
                }
            }
        }

        // Activate the animation but leave it paused to advance it manually.
        animator.pauseAnimation()
    }

    /// Whether the control is in the filtering state or transitioning into it (i.e., pending).
    var isFiltering: Bool {
        state.isFiltering
    }

    func startFiltering(animated: Bool) {
        func startFiltering() {
            scrollView?.contentInset.top = 0
        }

        if animated {
            UIView.animate(withDuration: animationDuration) { [self] in
                state = .starting
                startFiltering()
                UIView.performWithoutAnimation {
                    animator.fractionComplete = 1
                }
            } completion: { [self] _ in
                state = .filtering
            }
        } else {
            state = .filtering
            startFiltering()
            animator.fractionComplete = 1
        }
    }

    func stopFiltering(animated: Bool) {
        func stopFiltering() {
            scrollView?.contentInset.top = -frame.height
        }

        if animated {
            UIView.animate(withDuration: animationDuration) { [self] in
                state = .stopping
                stopFiltering()
            } completion: { [self] _ in
                state = .inactive
                animator.fractionComplete = 0
            }
        } else {
            state = .inactive
            stopFiltering()
            animator.fractionComplete = 0
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 52), height: 52)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        for imageView in imageViews {
            let imageHeight = contentView.bounds.inset(by: contentView.layoutMargins).height
            imageView.frame.size = CGSize(width: imageHeight, height: imageHeight)
            imageView.center = contentView.center
        }
    }

    func updateScrollPosition(in scrollView: UIScrollView) {
        let adjustedOffset = scrollView.adjustedContentInset.top + scrollView.contentOffset.y

        overlayView.frame.origin.y = if scrollView.contentInset.top == 0 {
            // When filtering/"docked", contentView is part of the content area,
            // so make sure overlayView doesn't obscure it.
            adjustedOffset - overlayView.frame.height
        } else {
            // When not docked, contentView  can be obscured by overlayView.
            adjustedOffset
        }

        guard state.startOrContinueTracking() else { return }

        if feedback == nil {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.prepare()
            self.feedback = feedback
        }

        let position = max(0, -adjustedOffset)
        let limit = frame.height * 2
        let progress = min(1, position / limit)
        var didStartFiltering = false

        if progress == 1 {
            self.feedback?.impactOccurred()
            self.feedback = nil
            state = .pending
            didStartFiltering = true
        }

        animator.fractionComplete = progress

        if didStartFiltering {
            delegate?.filterControlDidStartFiltering()
        }
    }

    func draggingWillEnd(in scrollView: UIScrollView) {
        switch state {
        case .pending:
            state = .filtering
            scrollView.contentInset.top = 0
        case .inactive, .filtering, .stopping, .starting:
            break
        case .tracking:
            state = .inactive
        }
    }
}

private extension UIImage.Configuration {
    static var filterIconBase: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(scale: .large)
    }

    static var filterIconBackground: UIImage.SymbolConfiguration {
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.Signal.secondaryBackground]))
    }

    static var filterIconIncrementing: UIImage.SymbolConfiguration {
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.Signal.label, .Signal.secondaryBackground]))
    }

    static var filterIconFiltering: UIImage.SymbolConfiguration {
        filterIconBase.applying(UIImage.SymbolConfiguration(paletteColors: [.Signal.ultramarine, .Signal.secondaryBackground]))
    }
}
